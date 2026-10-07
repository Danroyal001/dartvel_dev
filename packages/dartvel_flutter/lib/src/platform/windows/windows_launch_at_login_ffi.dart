/// Launch at login on Windows: the per-user Run key.
///
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` holds a value per
/// application, the command line to start at login, which is what Task
/// Manager's Startup tab lists. A user who disables it there is recorded
/// under `Explorer\StartupApproved\Run`, with the low bit of the first byte
/// set, so that is read too: the state is the desktop's, not what this
/// application last wrote. Per-user, so no elevation.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _SetKeyValueN = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Uint32);
typedef _SetKeyValueD = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int);
typedef _GetValueN = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _GetValueD = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _DeleteKeyValueN = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>);
typedef _DeleteKeyValueD = int Function(int, Pointer<Utf16>, Pointer<Utf16>);

/// `HKEY_CURRENT_USER`, as windows_associations_ffi.dart passes it.
const int _hkcu = 0x80000001;
const int _regSz = 1;
const int _rrfRtRegSz = 0x00000002;
const int _rrfRtRegBinary = 0x00000008;
const String _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
const String _approvedKey = r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

class DVWindowsLaunchAtLogin {
  const DVWindowsLaunchAtLogin._();

  static const Set<String> implemented = <String>{'launchAtLogin.isEnabled', 'launchAtLogin.setEnabled'};

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    final DynamicLibrary advapi32;
    try {
      advapi32 = DynamicLibrary.open('advapi32.dll');
    } on ArgumentError {
      return;
    }
    bind('launchAtLogin.isEnabled', (Object? _) => _isEnabled(advapi32));
    bind('launchAtLogin.setEnabled', (Object? arguments) =>
        _setEnabled(advapi32, arguments is Map && arguments['enabled'] == true));
  }

  /// The value's name: the executable's, without `.exe`.
  static String get _name {
    final String file = Platform.resolvedExecutable.split(r'\').last;
    return file.toLowerCase().endsWith('.exe') ? file.substring(0, file.length - 4) : file;
  }

  static bool _isEnabled(DynamicLibrary advapi32) {
    final _GetValueD getValue = advapi32.lookupFunction<_GetValueN, _GetValueD>('RegGetValueW');
    final Pointer<Utf16> run = _runKey.toNativeUtf16();
    final Pointer<Utf16> approved = _approvedKey.toNativeUtf16();
    final Pointer<Utf16> name = _name.toNativeUtf16();
    final Pointer<Uint8> flags = calloc<Uint8>(12);
    final Pointer<Uint32> size = calloc<Uint32>()..value = 12;
    try {
      if (getValue(_hkcu, run, name, _rrfRtRegSz, nullptr, nullptr, nullptr) != 0) return false;
      // No StartupApproved entry is enabled; one with the low bit of its
      // first byte set is the user switching it off in Task Manager.
      if (getValue(_hkcu, approved, name, _rrfRtRegBinary, nullptr, flags.cast(), size) != 0) return true;
      return flags[0] & 1 == 0;
    } finally {
      calloc.free(run);
      calloc.free(approved);
      calloc.free(name);
      calloc.free(flags);
      calloc.free(size);
    }
  }

  static bool _setEnabled(DynamicLibrary advapi32, bool enabled) {
    final _DeleteKeyValueD delete = advapi32.lookupFunction<_DeleteKeyValueN, _DeleteKeyValueD>('RegDeleteKeyValueW');
    final Pointer<Utf16> run = _runKey.toNativeUtf16();
    final Pointer<Utf16> approved = _approvedKey.toNativeUtf16();
    final Pointer<Utf16> name = _name.toNativeUtf16();
    final String command = '"${Platform.resolvedExecutable}"';
    final Pointer<Utf16> data = command.toNativeUtf16();
    try {
      // A disabled-in-Task-Manager record would keep it off whatever the
      // Run key says, so turning it on clears that too.
      delete(_hkcu, approved, name);
      if (!enabled) {
        final int result = delete(_hkcu, run, name);
        return result == 0 || result == 2; // ERROR_FILE_NOT_FOUND: already off.
      }
      return advapi32.lookupFunction<_SetKeyValueN, _SetKeyValueD>('RegSetKeyValueW')(
            _hkcu, run, name, _regSz, data.cast(), (command.length + 1) * 2) ==
          0;
    } finally {
      calloc.free(run);
      calloc.free(approved);
      calloc.free(name);
      calloc.free(data);
    }
  }
}
