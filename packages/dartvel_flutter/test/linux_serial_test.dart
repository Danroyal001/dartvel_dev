@TestOn('linux')
library;

// The serial port, against real file descriptors.
//
// A pseudo-terminal is not a UART, but it is a real character device with
// real termios state, so everything this binding actually does -- open the
// device, put the line in raw mode, set the speed, wait for bytes with a
// timeout, write, close -- happens for real here. What it cannot prove is
// that a particular baud rate produces a particular bit rate on a wire, and
// nothing available to CI can prove that.
//
// The failures worth catching are quiet ones. A read that returns empty
// because it timed out and a read that returns empty because the port is
// shut look identical unless the binding says which. A port opened in
// cooked mode delivers the right bytes for text and mangles the first 0x1a
// in a binary frame. And a device that is not there has to come back as a
// refusal with the reason, not as a handle that fails on first use.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_serial_ffi.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

final DynamicLibrary _libc = DynamicLibrary.open('libc.so.6');

/// A pseudo-terminal pair: the master fd this test writes to and reads from,
/// and the slave path the binding opens as if it were a serial device.
class Pty {
  Pty(this.master, this.slavePath);

  final int master;
  final String slavePath;

  static Pty open() {
    final int master = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('posix_openpt')(2 | 0x800);
    expect(master, greaterThan(0), reason: 'posix_openpt failed');
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('grantpt')(master);
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('unlockpt')(master);
    final Pointer<Utf8> name = _libc
        .lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('ptsname')(master);
    return Pty(master, name.toDartString());
  }

  void writeToPort(List<int> bytes) {
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final int written = _libc.lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
          int Function(int, Pointer<Uint8>, int)>('write')(master, buffer, bytes.length);
      expect(written, bytes.length);
    } finally {
      calloc.free(buffer);
    }
  }

  List<int> readFromPort(int max) {
    final Pointer<Uint8> buffer = calloc<Uint8>(max);
    try {
      final int read = _libc.lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
          int Function(int, Pointer<Uint8>, int)>('read')(master, buffer, max);
      if (read <= 0) return const <int>[];
      return buffer.asTypedList(read).sublist(0, read);
    } finally {
      calloc.free(buffer);
    }
  }

  /// The speed the port is set to, read back through termios.
  int get speed => DVLinuxSerial.speedOf(master);

  void close() =>
      _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close')(master);
}

void main() {
  setUpAll(() {
    DVLinuxSerial.register(DVNativeBridge.register);
  });

  late Pty pty;
  setUp(() => pty = Pty.open());
  tearDown(() {
    pty.close();
    DVLinuxSerial.closeAll();
  });

  test('a port that is not there is refused with the reason', () async {
    // Not a handle that fails later: the caller can only act on the reason
    // if it arrives where the mistake was made.
    await expectLater(
      const DVSerial().open('/dev/ttyNotHere'),
      throwsA(predicate((Object e) => '$e'.contains('/dev/ttyNotHere'))),
    );
  });

  test('bytes written to the device arrive at the port', () async {
    final DVSerialConnection port =
        await const DVSerial().open(pty.slavePath, baud: 115200);
    addTearDown(port.close);

    pty.writeToPort(<int>[0x01, 0x1a, 0x0d, 0x0a, 0xff]);
    final Uint8List got = await port.read(timeout: const Duration(seconds: 2));

    // 0x1a is end-of-file to a cooked terminal and 0x0d becomes 0x0a: in
    // cooked mode this frame arrives short and altered, and a text protocol
    // would never notice.
    expect(got, <int>[0x01, 0x1a, 0x0d, 0x0a, 0xff]);
  });

  test('bytes written to the port arrive at the device', () async {
    final DVSerialConnection port = await const DVSerial().open(pty.slavePath);
    addTearDown(port.close);

    final int written = await port.write(Uint8List.fromList(<int>[0x02, 0x00, 0x7f]));

    expect(written, 3);
    expect(pty.readFromPort(16), <int>[0x02, 0x00, 0x7f]);
  });

  test('a read with nothing to read comes back empty at the timeout', () async {
    final DVSerialConnection port = await const DVSerial().open(pty.slavePath);
    addTearDown(port.close);

    final Stopwatch clock = Stopwatch()..start();
    final Uint8List got = await port.read(timeout: const Duration(milliseconds: 200));
    clock.stop();

    expect(got, isEmpty);
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(150),
        reason: 'it waited rather than returning at once');
    expect(clock.elapsedMilliseconds, lessThan(2000),
        reason: 'and it stopped waiting');
  });

  test('the speed asked for is the speed the line is set to', () async {
    final DVSerialConnection port =
        await const DVSerial().open(pty.slavePath, baud: 115200);
    addTearDown(port.close);

    expect(pty.speed, 115200);
  });

  test('a closed port refuses further use rather than reading nothing', () async {
    // A closed port that answered empty reads would look exactly like a
    // device that has gone quiet, which is the fault it would be hiding.
    final DVSerialConnection port = await const DVSerial().open(pty.slavePath);
    await port.close();

    await expectLater(
      port.read(timeout: const Duration(milliseconds: 50)),
      throwsA(isA<Object>()),
    );
  });

  test('two ports open at once are two ports', () async {
    final Pty other = Pty.open();
    addTearDown(other.close);
    final DVSerialConnection a = await const DVSerial().open(pty.slavePath);
    final DVSerialConnection b = await const DVSerial().open(other.slavePath);
    addTearDown(a.close);
    addTearDown(b.close);

    await a.write(Uint8List.fromList(<int>[0xaa]));
    await b.write(Uint8List.fromList(<int>[0xbb]));

    expect(pty.readFromPort(4), <int>[0xaa]);
    expect(other.readFromPort(4), <int>[0xbb]);
  });

  test('the ports it lists are ports that exist', () async {
    // A pty is not a serial port and must not be listed as one; whether this
    // runner has any real port is not this test's business.
    final List<DVSerialPort> ports = await const DVSerial().ports();

    expect(ports.map((DVSerialPort p) => p.path), isNot(contains(pty.slavePath)));
    for (final DVSerialPort port in ports) {
      expect(File(port.path).existsSync() || Link(port.path).existsSync(), isTrue,
          reason: '${port.path} was listed and is not there');
    }
  });
}
