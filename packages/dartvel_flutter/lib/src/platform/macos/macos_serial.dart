/// The serial port on macOS.
///
/// The same POSIX calls as Linux and not the same structures. macOS's
/// `termios` has eight-byte flag words where Linux has four, twenty control
/// characters where Linux has thirty-two, and speeds that are the numbers
/// themselves -- 9600 is 9600 -- where Linux uses small indices, so a struct
/// or a constant table copied across would read the wrong fields and set a
/// speed nobody asked for, quietly, on a working-looking port.
///
/// Everything else is the reasoning in the Linux binding: raw mode always,
/// because a terminal's default line discipline turns carriage returns into
/// newlines and stops at the first 0x1a; and `poll` with a deadline rather
/// than a blocking read, because a device that goes quiet must not be able to
/// hang the application.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _oRdwr = 0x0002;
const int _oNoctty = 0x20000;
const int _oNonblock = 0x0004;

/// macOS's `struct termios`: four `unsigned long` flag words, twenty control
/// characters, and two `unsigned long` speeds.
final class _Termios extends Struct {
  @Uint64()
  external int iflag;
  @Uint64()
  external int oflag;
  @Uint64()
  external int cflag;
  @Uint64()
  external int lflag;
  @Array(20)
  external Array<Uint8> cc;
  @Uint64()
  external int ispeed;
  @Uint64()
  external int ospeed;
}

final class _PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

const int _pollIn = 0x0001;

typedef _OpenN = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenD = int Function(Pointer<Utf8>, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);
typedef _RwN = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _RwD = int Function(int, Pointer<Uint8>, int);
typedef _TermiosN = Int32 Function(Int32, Pointer<_Termios>);
typedef _TermiosD = int Function(int, Pointer<_Termios>);
typedef _SetTermiosN = Int32 Function(Int32, Int32, Pointer<_Termios>);
typedef _SetTermiosD = int Function(int, int, Pointer<_Termios>);
typedef _SpeedN = Int32 Function(Pointer<_Termios>, Uint64);
typedef _SpeedD = int Function(Pointer<_Termios>, int);
typedef _GetSpeedN = Uint64 Function(Pointer<_Termios>);
typedef _GetSpeedD = int Function(Pointer<_Termios>);
typedef _RawN = Void Function(Pointer<_Termios>);
typedef _RawD = void Function(Pointer<_Termios>);
typedef _PollN = Int32 Function(Pointer<_PollFd>, Uint32, Int32);
typedef _PollD = int Function(Pointer<_PollFd>, int, int);
typedef _ErrnoN = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();
typedef _StrerrorN = Pointer<Utf8> Function(Int32);
typedef _StrerrorD = Pointer<Utf8> Function(int);

/// The serial bindings, over the C library macOS already has.
class DVMacosSerial {
  DVMacosSerial._();

  static final DynamicLibrary _c = DynamicLibrary.process();

  static final Map<int, int> _open = <int, int>{};
  static int _nextHandle = 1;

  static const Set<String> bindings = <String>{
    'device.serial.ports',
    'device.serial.open',
    'device.serial.write',
    'device.serial.read',
    'device.serial.close',
  };

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    bind('device.serial.ports', (Object? _) => listPorts());
    bind('device.serial.open', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      return openPort('${a['path']}',
          baud: a['baud'] is int ? a['baud']! as int : 9600);
    });
    bind('device.serial.write', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      final Object? bytes = a['bytes'];
      return writePort(
        a['handle']! as int,
        Uint8List.fromList(<int>[
          for (final Object? b in bytes is List ? bytes : const <Object?>[])
            if (b is int) b,
        ]),
      );
    });
    bind('device.serial.read', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      return readPort(
        a['handle']! as int,
        max: a['max'] is int ? a['max']! as int : 4096,
        timeoutMs: a['timeoutMs'] is int ? a['timeoutMs']! as int : 1000,
      );
    });
    bind('device.serial.close', (Object? args) {
      closePort(_args(args)['handle']! as int);
      return true;
    });
  }

  static Map<Object?, Object?> _args(Object? args) =>
      args is Map ? args : const <Object?, Object?>{};

  /// The serial ports this machine has.
  ///
  /// `/dev/cu.*` rather than `/dev/tty.*`. The two are the same hardware
  /// through different doors: opening the tty door blocks until the line
  /// asserts carrier, which a three-wire adapter never does, so a program
  /// that opened it would appear to hang on a working cable.
  static List<Map<String, Object?>> listPorts() {
    final Directory dev = Directory('/dev');
    if (!dev.existsSync()) return const <Map<String, Object?>>[];
    final List<Map<String, Object?>> ports = <Map<String, Object?>>[];
    for (final FileSystemEntity entry in dev.listSync()) {
      final String name = entry.path.split('/').last;
      if (!name.startsWith('cu.')) continue;
      // The Bluetooth and debug consoles macOS creates on every machine are
      // not somebody's device, and listing them makes the real one harder to
      // find.
      if (name.startsWith('cu.Bluetooth') || name.startsWith('cu.debug')) {
        continue;
      }
      ports.add(<String, Object?>{
        'path': entry.path,
        'name': name.substring(3),
      });
    }
    ports.sort((Map<String, Object?> a, Map<String, Object?> b) =>
        '${a['path']}'.compareTo('${b['path']}'));
    return ports;
  }

  static int openPort(String path, {int baud = 9600}) {
    final Pointer<Utf8> name = path.toNativeUtf8();
    final int fd;
    try {
      fd = _c.lookupFunction<_OpenN, _OpenD>('open')(
        name,
        _oRdwr | _oNoctty | _oNonblock,
      );
    } finally {
      calloc.free(name);
    }
    if (fd < 0) {
      throw StateError('Opening the serial port $path failed: ${_errno()}.');
    }
    try {
      _configure(fd, baud);
    } on Object {
      _c.lookupFunction<_CloseN, _CloseD>('close')(fd);
      rethrow;
    }
    final int handle = _nextHandle++;
    _open[handle] = fd;
    return handle;
  }

  static void _configure(int fd, int baud) {
    final Pointer<_Termios> tio = calloc<_Termios>();
    try {
      if (_c.lookupFunction<_TermiosN, _TermiosD>('tcgetattr')(fd, tio) != 0) {
        throw StateError('Reading the line settings failed: ${_errno()}.');
      }
      _c.lookupFunction<_RawN, _RawD>('cfmakeraw')(tio);
      // VMIN and VTIME. macOS's array is twenty long and puts them at 16 and
      // 17, where Linux has them at 6 and 5.
      tio.ref.cc[16] = 0;
      tio.ref.cc[17] = 0;
      // CREAD | CLOCAL, the same bits as Linux: receive, and do not wait for
      // a carrier a three-wire cable will never assert.
      tio.ref.cflag |= 0x800 | 0x8000;
      // macOS speeds are the numbers themselves, so any rate the hardware
      // supports can be asked for -- there is no table to be missing from.
      if (baud <= 0) {
        throw StateError('A serial speed of $baud is not a speed.');
      }
      final _SpeedD setIn = _c.lookupFunction<_SpeedN, _SpeedD>('cfsetispeed');
      final _SpeedD setOut = _c.lookupFunction<_SpeedN, _SpeedD>('cfsetospeed');
      if (setIn(tio, baud) != 0 || setOut(tio, baud) != 0) {
        throw StateError('Setting the speed to $baud failed: ${_errno()}.');
      }
      if (_c.lookupFunction<_SetTermiosN, _SetTermiosD>('tcsetattr')(fd, 0, tio) != 0) {
        throw StateError('Applying the line settings failed: ${_errno()}.');
      }
    } finally {
      calloc.free(tio);
    }
  }

  /// The speed set on [fd], in bits per second. For tests and diagnostics.
  static int speedOf(int fd) {
    final Pointer<_Termios> tio = calloc<_Termios>();
    try {
      if (_c.lookupFunction<_TermiosN, _TermiosD>('tcgetattr')(fd, tio) != 0) {
        return 0;
      }
      return _c.lookupFunction<_GetSpeedN, _GetSpeedD>('cfgetospeed')(tio);
    } finally {
      calloc.free(tio);
    }
  }

  static int writePort(int handle, Uint8List bytes) {
    final int fd = _fd(handle);
    if (bytes.isEmpty) return 0;
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final int written =
          _c.lookupFunction<_RwN, _RwD>('write')(fd, buffer, bytes.length);
      if (written < 0) {
        throw StateError('Writing to the serial port failed: ${_errno()}.');
      }
      return written;
    } finally {
      calloc.free(buffer);
    }
  }

  static List<int> readPort(int handle, {int max = 4096, int timeoutMs = 1000}) {
    final int fd = _fd(handle);
    // The deadline, not the interval: a poll interrupted by a signal is
    // restarted with the time that is left, and a Dart VM raises signals all
    // the time.
    final Stopwatch clock = Stopwatch()..start();
    final Pointer<_PollFd> poll = calloc<_PollFd>();
    try {
      while (true) {
        final int remaining = timeoutMs - clock.elapsedMilliseconds;
        if (remaining <= 0) return const <int>[];
        poll.ref
          ..fd = fd
          ..events = _pollIn
          ..revents = 0;
        final int ready =
            _c.lookupFunction<_PollN, _PollD>('poll')(poll, 1, remaining);
        if (ready > 0) break;
        if (ready == 0) return const <int>[];
        if (_errnoCode() == _eintr) continue;
        throw StateError('Waiting on the serial port failed: ${_errno()}.');
      }
    } finally {
      calloc.free(poll);
    }
    final Pointer<Uint8> buffer = calloc<Uint8>(max);
    try {
      while (true) {
        final int read = _c.lookupFunction<_RwN, _RwD>('read')(fd, buffer, max);
        if (read > 0) return buffer.asTypedList(read).sublist(0, read);
        if (read == 0) return const <int>[];
        final int code = _errnoCode();
        if (code == _eintr) continue;
        if (code == _eagain) return const <int>[];
        throw StateError('Reading from the serial port failed: ${_errno()}.');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  static void closePort(int handle) {
    final int? fd = _open.remove(handle);
    if (fd == null) return;
    _c.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }

  /// Closes every open port. For tests, and for an application shutting down.
  static void closeAll() {
    for (final int handle in _open.keys.toList()) {
      closePort(handle);
    }
  }

  static int _fd(int handle) {
    final int? fd = _open[handle];
    if (fd == null) throw StateError('Serial port $handle is not open.');
    return fd;
  }

  static const int _eintr = 4;
  static const int _eagain = 35;

  static int _errnoCode() =>
      _c.lookupFunction<_ErrnoN, _ErrnoD>('__error')().value;

  static String _errno() {
    final int code = _errnoCode();
    final Pointer<Utf8> message =
        _c.lookupFunction<_StrerrorN, _StrerrorD>('strerror')(code);
    return message == nullptr ? 'errno $code' : message.toDartString();
  }
}
