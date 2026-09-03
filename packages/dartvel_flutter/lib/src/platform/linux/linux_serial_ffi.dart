/// The serial port on Linux, through libc.
///
/// A serial device is a character device and a `termios` line discipline, and
/// both halves matter. Opening the device is the easy half; the line
/// discipline is where a port that looks like it works mangles data. A
/// terminal in its default cooked mode turns carriage returns into newlines,
/// treats 0x1a as end of file and buffers by line, so a text protocol works
/// and the first binary frame arrives short and altered. Every port opened
/// here is put in raw mode before it is handed back.
///
/// Reading waits on `poll` rather than on a blocking `read`, because a read
/// that cannot be given up on is a device that can hang an application by
/// going quiet.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// open(2) flags. O_NOCTTY matters: without it, opening a terminal from a
// process with no controlling terminal makes the port one, and then a modem
// hangup delivers SIGHUP to the application.
const int _oRdwr = 0x0002;
const int _oNoctty = 0x0100;
const int _oNonblock = 0x0800;

/// glibc's `struct termios`: four flag words, the line discipline byte, the
/// 32 control characters, and the two speeds.
final class _Termios extends Struct {
  @Uint32()
  external int iflag;
  @Uint32()
  external int oflag;
  @Uint32()
  external int cflag;
  @Uint32()
  external int lflag;
  @Uint8()
  external int line;
  @Array(32)
  external Array<Uint8> cc;
  @Uint32()
  external int ispeed;
  @Uint32()
  external int ospeed;
}

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
typedef _SpeedN = Int32 Function(Pointer<_Termios>, Uint32);
typedef _SpeedD = int Function(Pointer<_Termios>, int);
typedef _GetSpeedN = Uint32 Function(Pointer<_Termios>);
typedef _GetSpeedD = int Function(Pointer<_Termios>);
typedef _RawN = Void Function(Pointer<_Termios>);
typedef _RawD = void Function(Pointer<_Termios>);
typedef _PollN = Int32 Function(Pointer<_PollFd>, Uint64, Int32);
typedef _PollD = int Function(Pointer<_PollFd>, int, int);
typedef _ErrnoN = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();
typedef _StrerrorN = Pointer<Utf8> Function(Int32);
typedef _StrerrorD = Pointer<Utf8> Function(int);

final class _PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

const int _pollIn = 0x001;

/// The serial bindings, over the C library the platform already has.
class DVLinuxSerial {
  DVLinuxSerial._();

  static DynamicLibrary? _libc;
  static DynamicLibrary get _c => _libc ??= DynamicLibrary.open('libc.so.6');

  static final Map<int, int> _open = <int, int>{};
  static int _nextHandle = 1;

  /// The bindings this platform provides.
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
      return openPort(
        '${a['path']}',
        baud: a['baud'] is int ? a['baud']! as int : 9600,
      );
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
  /// `/dev/serial/by-id` is the list udev keeps of devices that are actually
  /// serial ports, with a name that survives a reboot -- unlike `ttyUSB0`,
  /// which is whichever adapter was plugged in first. A machine with no such
  /// directory has its `ttyUSB*`/`ttyACM*` nodes read instead; `ttyS*` is
  /// deliberately not guessed at, because almost every one of the 32 nodes a
  /// kernel creates is not a port.
  static List<Map<String, Object?>> listPorts() {
    final List<Map<String, Object?>> ports = <Map<String, Object?>>[];
    final Directory byId = Directory('/dev/serial/by-id');
    if (byId.existsSync()) {
      for (final FileSystemEntity entry in byId.listSync()) {
        final String path = entry.path;
        String resolved = path;
        try {
          resolved = Link(path).resolveSymbolicLinksSync();
        } on Object {
          // A dangling link: the adapter went away between listing and
          // resolving. The stable name is still what a caller opens.
        }
        ports.add(<String, Object?>{
          'path': resolved,
          'name': path.split('/').last,
        });
      }
      return ports;
    }
    final Directory dev = Directory('/dev');
    if (!dev.existsSync()) return ports;
    for (final FileSystemEntity entry in dev.listSync()) {
      final String name = entry.path.split('/').last;
      if (name.startsWith('ttyUSB') || name.startsWith('ttyACM')) {
        ports.add(<String, Object?>{'path': entry.path, 'name': name});
      }
    }
    return ports;
  }

  /// Opens [path] at [baud] in raw mode, and returns a handle.
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

  /// Raw mode and the speed, on the open descriptor.
  static void _configure(int fd, int baud) {
    final Pointer<_Termios> tio = calloc<_Termios>();
    try {
      if (_c.lookupFunction<_TermiosN, _TermiosD>('tcgetattr')(fd, tio) != 0) {
        throw StateError('Reading the line settings failed: ${_errno()}.');
      }
      // cfmakeraw is the C library's own definition of "do not interpret
      // anything", which is what a serial protocol needs and what writing the
      // flag words by hand gets subtly wrong.
      _c.lookupFunction<_RawN, _RawD>('cfmakeraw')(tio);
      // Read whatever has arrived and return; the waiting is poll's job, and
      // VMIN/VTIME would make it the kernel's as well.
      tio.ref.cc[6] = 0; // VMIN
      tio.ref.cc[5] = 0; // VTIME
      // CREAD | CLOCAL: receive, and do not wait on carrier detect -- a
      // three-wire cable has no carrier, and a port that waits for one never
      // opens.
      tio.ref.cflag |= 0x80 | 0x800;
      final int speed = _speedConstant(baud);
      final _SpeedD setIn = _c.lookupFunction<_SpeedN, _SpeedD>('cfsetispeed');
      final _SpeedD setOut = _c.lookupFunction<_SpeedN, _SpeedD>('cfsetospeed');
      if (setIn(tio, speed) != 0 || setOut(tio, speed) != 0) {
        throw StateError('Setting the speed to $baud failed: ${_errno()}.');
      }
      // TCSANOW: now, rather than after what is already queued -- there is
      // nothing queued on a port that has just been opened.
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
      final int constant =
          _c.lookupFunction<_GetSpeedN, _GetSpeedD>('cfgetospeed')(tio);
      for (final MapEntry<int, int> e in _speeds.entries) {
        if (e.value == constant) return e.key;
      }
      return 0;
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
      final int written = _c.lookupFunction<_RwN, _RwD>('write')(
        fd,
        buffer,
        bytes.length,
      );
      if (written < 0) {
        throw StateError('Writing to the serial port failed: ${_errno()}.');
      }
      return written;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Waits up to [timeoutMs] for bytes and returns what arrived.
  ///
  /// An empty list is a timeout, which is a normal thing for a quiet device
  /// to do. A closed handle throws, because a shut port and a silent device
  /// are the two explanations for no bytes and only one of them is a fault
  /// in the program.
  static List<int> readPort(int handle, {int max = 4096, int timeoutMs = 1000}) {
    final int fd = _fd(handle);
    // The deadline rather than the interval, because a poll interrupted by a
    // signal has to be restarted with the time that is left. Restarting it
    // with the original interval turns a stream of signals -- and a Dart VM
    // produces those all the time, for timers and for the collector -- into a
    // read that waits far longer than it was asked to, or never returns.
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
        // The descriptor is non-blocking, so a read that raced the poll and
        // found the buffer already drained says "try again" rather than
        // failing. Nothing arrived, which is what an empty result means.
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

  /// Closes every open port. For tests, and for a kiosk restarting itself.
  static void closeAll() {
    for (final int handle in _open.keys.toList()) {
      closePort(handle);
    }
  }

  static int _fd(int handle) {
    final int? fd = _open[handle];
    if (fd == null) {
      throw StateError('Serial port $handle is not open.');
    }
    return fd;
  }

  /// EINTR: a signal arrived while the call was waiting. Not a fault, and
  /// unavoidable in a process with a garbage collector and timers.
  static const int _eintr = 4;

  /// EAGAIN: nothing to read on a non-blocking descriptor.
  static const int _eagain = 11;

  static int _errnoCode() =>
      _c.lookupFunction<_ErrnoN, _ErrnoD>('__errno_location')().value;

  static String _errno() {
    final int code = _errnoCode();
    final Pointer<Utf8> message =
        _c.lookupFunction<_StrerrorN, _StrerrorD>('strerror')(code);
    return message == nullptr ? 'errno $code' : message.toDartString();
  }

  /// The `B*` constants, which are indices rather than numbers: a speed the
  /// kernel has no constant for cannot be set, and saying so beats setting a
  /// different one.
  static const Map<int, int> _speeds = <int, int>{
    1200: 9,
    2400: 11,
    4800: 12,
    9600: 13,
    19200: 14,
    38400: 15,
    57600: 0x1001,
    115200: 0x1002,
    230400: 0x1003,
    460800: 0x1004,
    921600: 0x1007,
  };

  static int _speedConstant(int baud) {
    final int? constant = _speeds[baud];
    if (constant == null) {
      throw StateError(
        'A serial speed of $baud is not one the kernel has a constant for; '
        'it accepts ${_speeds.keys.join(', ')}.',
      );
    }
    return constant;
  }
}
