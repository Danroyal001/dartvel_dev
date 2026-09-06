/// The serial port on Windows: CreateFileW, SetCommState, SetCommTimeouts,
/// ReadFile, WriteFile.
///
/// The one bus an embedded device is most likely to have, and the last
/// desktop it was missing from — Linux has had it through termios and macOS
/// through its own eight-byte flag words, and a Windows deployment talking
/// to a scale, a till drawer or a controller had nothing.
///
/// The parts that can be wrong quietly are not here: which ports exist and
/// what to say when one will not open are string work, they live in
/// windows_serial_names.dart, and they are tested on any platform. What is
/// left is the FFI, which only Windows can run and only a real device can
/// fully prove.
library dartvel_flutter.platform.windows.serial;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'windows_serial_names.dart';

// DCB, as declared in winbase.h. The bitfield word is one Uint32 here: Dart
// has no bitfields, and the only bit this sets is fBinary, which is bit 0 and
// must be 1 — Windows refuses a DCB with it clear.
final class _Dcb extends Struct {
  @Uint32()
  external int dcbLength;
  @Uint32()
  external int baudRate;
  @Uint32()
  external int flags;
  @Uint16()
  external int wReserved;
  @Uint16()
  external int xonLim;
  @Uint16()
  external int xoffLim;
  @Uint8()
  external int byteSize;
  @Uint8()
  external int parity;
  @Uint8()
  external int stopBits;
  @Int8()
  external int xonChar;
  @Int8()
  external int xoffChar;
  @Int8()
  external int errorChar;
  @Int8()
  external int eofChar;
  @Int8()
  external int evtChar;
  @Uint16()
  external int wReserved1;
}

final class _CommTimeouts extends Struct {
  @Uint32()
  external int readIntervalTimeout;
  @Uint32()
  external int readTotalTimeoutMultiplier;
  @Uint32()
  external int readTotalTimeoutConstant;
  @Uint32()
  external int writeTotalTimeoutMultiplier;
  @Uint32()
  external int writeTotalTimeoutConstant;
}

typedef _CreateFileWNative = IntPtr Function(Pointer<Utf16> name, Uint32 access,
    Uint32 share, Pointer<Void> security, Uint32 disposition, Uint32 flags,
    IntPtr template);
typedef _CreateFileWDart = int Function(Pointer<Utf16> name, int access,
    int share, Pointer<Void> security, int disposition, int flags,
    int template);
typedef _CloseHandleNative = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);
typedef _GetCommStateNative = Int32 Function(IntPtr handle, Pointer<_Dcb> dcb);
typedef _GetCommStateDart = int Function(int handle, Pointer<_Dcb> dcb);
typedef _SetCommTimeoutsNative = Int32 Function(
    IntPtr handle, Pointer<_CommTimeouts> timeouts);
typedef _SetCommTimeoutsDart = int Function(
    int handle, Pointer<_CommTimeouts> timeouts);
typedef _ReadFileNative = Int32 Function(IntPtr handle, Pointer<Uint8> buffer,
    Uint32 count, Pointer<Uint32> read, Pointer<Void> overlapped);
typedef _ReadFileDart = int Function(int handle, Pointer<Uint8> buffer,
    int count, Pointer<Uint32> read, Pointer<Void> overlapped);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _RegOpenKeyExWNative = Int32 Function(IntPtr key, Pointer<Utf16> path,
    Uint32 options, Uint32 desired, Pointer<IntPtr> result);
typedef _RegOpenKeyExWDart = int Function(int key, Pointer<Utf16> path,
    int options, int desired, Pointer<IntPtr> result);
typedef _RegEnumValueWNative = Int32 Function(
    IntPtr key,
    Uint32 index,
    Pointer<Utf16> name,
    Pointer<Uint32> nameLength,
    Pointer<Uint32> reserved,
    Pointer<Uint32> type,
    Pointer<Uint8> data,
    Pointer<Uint32> dataLength);
typedef _RegEnumValueWDart = int Function(
    int key,
    int index,
    Pointer<Utf16> name,
    Pointer<Uint32> nameLength,
    Pointer<Uint32> reserved,
    Pointer<Uint32> type,
    Pointer<Uint8> data,
    Pointer<Uint32> dataLength);

const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _openExisting = 3;
const int _invalidHandle = -1;
const int _hkeyLocalMachine = 0x80000002;
const int _keyRead = 0x20019;
const int _errorSuccess = 0;

/// The serial port bindings on Windows.
class DVWindowsSerial {
  DVWindowsSerial._();

  static DynamicLibrary? _kernel;
  static DynamicLibrary get _k => _kernel ??= DynamicLibrary.open('kernel32.dll');
  static DynamicLibrary? _advapi;
  static DynamicLibrary get _a => _advapi ??= DynamicLibrary.open('advapi32.dll');

  /// Open ports, by the handle a caller was given.
  ///
  /// A Win32 HANDLE is an opaque pointer-sized number and handing one to
  /// application code invites it to be closed twice or passed to something
  /// else. The caller gets a small integer instead.
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
        '${a['path'] ?? a['name'] ?? ''}',
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
  /// `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` is the list Windows itself keeps,
  /// and it is the one every serial library reads: the alternative, walking
  /// the setup device tree, finds ports that exist and cannot be opened.
  /// A machine with no serial hardware has no key at all, which is an empty
  /// list rather than a failure — that is a laptop and it is every CI runner.
  static List<Map<String, Object?>> listPorts() {
    final Pointer<IntPtr> key = calloc<IntPtr>();
    final Pointer<Utf16> path =
        r'HARDWARE\DEVICEMAP\SERIALCOMM'.toNativeUtf16();
    try {
      final int opened = _a.lookupFunction<_RegOpenKeyExWNative,
          _RegOpenKeyExWDart>('RegOpenKeyExW')(
        _hkeyLocalMachine,
        path,
        0,
        _keyRead,
        key,
      );
      if (opened != _errorSuccess) return const <Map<String, Object?>>[];

      final Map<String, String> values = <String, String>{};
      final _RegEnumValueWDart enumerate = _a
          .lookupFunction<_RegEnumValueWNative, _RegEnumValueWDart>(
              'RegEnumValueW');
      for (int index = 0;; index++) {
        const int nameChars = 512;
        const int dataBytes = 512;
        final Pointer<Utf16> name = calloc<Uint16>(nameChars).cast<Utf16>();
        final Pointer<Uint32> nameLength = calloc<Uint32>()..value = nameChars;
        final Pointer<Uint8> data = calloc<Uint8>(dataBytes);
        final Pointer<Uint32> dataLength = calloc<Uint32>()..value = dataBytes;
        final Pointer<Uint32> type = calloc<Uint32>();
        try {
          final int result = enumerate(key.value, index, name, nameLength,
              nullptr, type, data, dataLength);
          if (result != _errorSuccess) break;
          values[name.toDartString()] = data.cast<Utf16>().toDartString();
        } finally {
          calloc
            ..free(name)
            ..free(nameLength)
            ..free(data)
            ..free(dataLength)
            ..free(type);
        }
      }
      return dvWindowsSerialPorts(values);
    } finally {
      calloc
        ..free(key)
        ..free(path);
    }
  }

  /// Opens [pathOrName] and returns a handle, or throws with the reason.
  static int openPort(String pathOrName, {int baud = 9600}) {
    // A caller that passed COM10 rather than the path gets the same thing a
    // caller that passed the path gets. The prefix is legal for every name,
    // and applying it twice would not be.
    final String path =
        pathOrName.startsWith(r'\\.\') ? pathOrName : dvWindowsSerialPath(pathOrName);
    final Pointer<Utf16> native = path.toNativeUtf16();
    try {
      final int handle = _k.lookupFunction<_CreateFileWNative,
          _CreateFileWDart>('CreateFileW')(
        native,
        _genericRead | _genericWrite,
        // A serial port is exclusive. Sharing it is the one thing Windows
        // will not do, and asking produces a handle that fails on first use.
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (handle == _invalidHandle) {
        final int code =
            _k.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
                'GetLastError')();
        throw StateError(dvWindowsSerialFailure(code, pathOrName));
      }

      _configure(handle, baud);
      final int id = _nextHandle++;
      _open[id] = handle;
      return id;
    } finally {
      calloc.free(native);
    }
  }

  /// 8N1 at [baud], binary, no flow control, and timeouts that return rather
  /// than block forever.
  static void _configure(int handle, int baud) {
    final Pointer<_Dcb> dcb = calloc<_Dcb>();
    final Pointer<_CommTimeouts> timeouts = calloc<_CommTimeouts>();
    try {
      // Read the current state first rather than filling a DCB from nothing:
      // the reserved words and the flow-control bits have to be what the
      // driver expects, and a zeroed DCB is rejected.
      _k.lookupFunction<_GetCommStateNative, _GetCommStateDart>(
          'GetCommState')(handle, dcb);
      dcb.ref
        ..dcbLength = sizeOf<_Dcb>()
        ..baudRate = baud
        ..byteSize = 8
        ..parity = 0
        ..stopBits = 0
        // fBinary. Windows refuses a DCB without it, and every other bit
        // here is flow control this deliberately leaves off.
        ..flags = 0x0001;
      _k.lookupFunction<_GetCommStateNative, _GetCommStateDart>(
          'SetCommState')(handle, dcb);

      // A read that waits forever is a UI that never comes back. These make
      // ReadFile return what has arrived, and the caller's own timeout is
      // applied on top.
      timeouts.ref
        ..readIntervalTimeout = 0xFFFFFFFF
        ..readTotalTimeoutMultiplier = 0
        ..readTotalTimeoutConstant = 0
        ..writeTotalTimeoutMultiplier = 0
        ..writeTotalTimeoutConstant = 1000;
      _k.lookupFunction<_SetCommTimeoutsNative, _SetCommTimeoutsDart>(
          'SetCommTimeouts')(handle, timeouts);
    } finally {
      calloc
        ..free(dcb)
        ..free(timeouts);
    }
  }

  /// Writes [bytes] and answers how many went out.
  static int writePort(int id, Uint8List bytes) {
    final int handle = _handle(id);
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    final Pointer<Uint32> written = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final int ok = _k.lookupFunction<_ReadFileNative, _ReadFileDart>(
          'WriteFile')(handle, buffer, bytes.length, written, nullptr);
      if (ok == 0) {
        final int code =
            _k.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
                'GetLastError')();
        throw StateError('The write failed (error $code).');
      }
      return written.value;
    } finally {
      calloc
        ..free(buffer)
        ..free(written);
    }
  }

  /// Reads up to [max] bytes, waiting no longer than [timeoutMs].
  ///
  /// An empty list means nothing arrived in the time allowed. It is not an
  /// error and it is not a closed port — a caller that cannot tell those
  /// apart writes a retry loop around a dead handle.
  static Uint8List readPort(int id, {int max = 4096, int timeoutMs = 1000}) {
    final int handle = _handle(id);
    final Pointer<Uint8> buffer = calloc<Uint8>(max);
    final Pointer<Uint32> read = calloc<Uint32>();
    final DateTime deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));
    try {
      while (true) {
        final int ok = _k.lookupFunction<_ReadFileNative, _ReadFileDart>(
            'ReadFile')(handle, buffer, max, read, nullptr);
        if (ok == 0) {
          final int code =
              _k.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
                  'GetLastError')();
          throw StateError('The read failed (error $code).');
        }
        if (read.value > 0) {
          return Uint8List.fromList(buffer.asTypedList(read.value));
        }
        if (!DateTime.now().isBefore(deadline)) return Uint8List(0);
      }
    } finally {
      calloc
        ..free(buffer)
        ..free(read);
    }
  }

  /// Closes the port, and forgets the handle.
  static void closePort(int id) {
    final int? handle = _open.remove(id);
    if (handle == null) return;
    _k.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
        'CloseHandle')(handle);
  }

  static int _handle(int id) {
    final int? handle = _open[id];
    if (handle == null) {
      throw StateError('Serial handle $id is closed, or was never opened.');
    }
    return handle;
  }
}
