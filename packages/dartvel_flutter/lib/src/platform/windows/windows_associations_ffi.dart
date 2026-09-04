/// File associations on Windows: the per-user part of the registry.
///
/// Windows learns what opens a file from `HKEY_CURRENT_USER\Software\Classes`:
/// an extension key naming a ProgId, and the ProgId's `shell\open\command`
/// holding the command line. Both are per-user, which is the point -- the
/// machine-wide equivalent under HKEY_LOCAL_MACHINE needs administrator
/// rights, so an API that used it would be one most applications could not
/// call and every one of them would have to ship an installer for.
///
/// The registry script the build writes beside the binary says the same
/// thing; this is the application saying it for itself, for the user running
/// it, without anybody having to run the script.
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import 'windows_capabilities.dart';

typedef _RegCreateKeyExN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32,
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>);
typedef _RegCreateKeyExD = int Function(int, Pointer<Utf16>, int, Pointer<Utf16>,
    int, int, Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>);
typedef _RegSetValueExN = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32);
typedef _RegSetValueExD = int Function(
    int, Pointer<Utf16>, int, int, Pointer<Uint8>, int);
typedef _RegQueryValueExN = Int32 Function(IntPtr, Pointer<Utf16>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _RegQueryValueExD = int Function(int, Pointer<Utf16>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _RegOpenKeyExN = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _RegOpenKeyExD = int Function(
    int, Pointer<Utf16>, int, int, Pointer<IntPtr>);
typedef _RegCloseKeyN = Int32 Function(IntPtr);
typedef _RegCloseKeyD = int Function(int);
typedef _RegDeleteTreeN = Int32 Function(IntPtr, Pointer<Utf16>);
typedef _RegDeleteTreeD = int Function(int, Pointer<Utf16>);
typedef _ShChangeNotifyN = Void Function(Int32, Uint32, Pointer<Void>, Pointer<Void>);
typedef _ShChangeNotifyD = void Function(int, int, Pointer<Void>, Pointer<Void>);

/// `HKEY_CURRENT_USER`.
const int _hkcu = 0x80000001;
const int _keyRead = 0x20019;
const int _keyWrite = 0x20006;
const int _regSz = 1;
const int _errorSuccess = 0;

/// `SHCNE_ASSOCCHANGED` with `SHCNF_IDLIST`: tell Explorer the associations
/// changed, or the desktop goes on offering the old handler until it is
/// restarted.
const int _shcneAssocChanged = 0x08000000;
const int _shcnfIdList = 0x0;

class DVWindowsAssociations {
  const DVWindowsAssociations._();

  static DynamicLibrary? _advapi32;
  static DynamicLibrary? _shell32;

  static const Set<String> implemented = <String>{
    'associations.register',
    'associations.unregister',
    'associations.handlerFor',
  };

  static void register(
    void Function(String, Object? Function(Object?)) bind, {
    required DynamicLibrary advapi32,
    required DynamicLibrary shell32,
  }) {
    _advapi32 = advapi32;
    _shell32 = shell32;
    bind('associations.register', (Object? arguments) => _apply(arguments, add: true));
    bind('associations.unregister', (Object? arguments) => _apply(arguments, add: false));
    bind('associations.handlerFor', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return handlerFor('${map['extension'] ?? ''}');
    });
  }

  /// The ProgId this application uses for [mimeType].
  static String progIdFor(String mimeType) => dvWindowsProgIdFor(mimeType);

  /// What the shell runs for a document: this executable, with the file.
  static String get _command => '"${Platform.resolvedExecutable}" "%1"';

  static bool _apply(Object? arguments, {required bool add}) {
    if (_advapi32 == null) return false;
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final List<Object?> types = map['types'] is List ? map['types']! as List<Object?> : const <Object?>[];
    final List<Object?> schemes = map['schemes'] is List ? map['schemes']! as List<Object?> : const <Object?>[];

    bool ok = true;
    for (final Object? raw in types) {
      if (raw is! Map) continue;
      final String mimeType = '${raw['mimeType'] ?? ''}';
      if (mimeType.isEmpty) continue;
      final String progId = progIdFor(mimeType);
      final List<Object?> extensions =
          raw['extensions'] is List ? raw['extensions']! as List<Object?> : const <Object?>[];
      if (add) {
        ok = _write('Software\\Classes\\$progId', null, '${raw['description'] ?? mimeType}') && ok;
        ok = _write('Software\\Classes\\$progId\\shell\\open\\command', null, _command) && ok;
        for (final Object? extension in extensions) {
          ok = _write('Software\\Classes\\.$extension', null, progId) && ok;
        }
      } else {
        for (final Object? extension in extensions) {
          // Only if it is still ours. Another application may have taken the
          // extension since, and deleting its key would break it while
          // uninstalling us.
          if (_read('Software\\Classes\\.$extension', null) == progId) {
            _delete('Software\\Classes\\.$extension');
          }
        }
        _delete('Software\\Classes\\$progId');
      }
    }
    for (final Object? raw in schemes) {
      final String scheme = '$raw';
      if (scheme.isEmpty) continue;
      if (add) {
        ok = _write('Software\\Classes\\$scheme', null, 'URL:$scheme') && ok;
        // The empty value is the flag: its presence is what makes the key a
        // URL protocol, and its contents are never read.
        ok = _write('Software\\Classes\\$scheme', 'URL Protocol', '') && ok;
        ok = _write('Software\\Classes\\$scheme\\shell\\open\\command', null, _command) && ok;
      } else {
        _delete('Software\\Classes\\$scheme');
      }
    }

    _notifyShell();
    return ok;
  }

  /// Which ProgId opens [extension] for this user, or null when nothing
  /// does.
  ///
  /// The ProgId is what Windows names a handler by; the command behind it is
  /// under the ProgId's own key.
  static String? handlerFor(String extension) {
    if (extension.isEmpty) return null;
    final String? own = _read('Software\\Classes\\.$extension', null);
    if (own != null && own.isNotEmpty) return own;
    // What the user chose in "Open with", which wins over the class key
    // whenever it is set -- so an answer that ignored it would say this
    // application opens a file the desktop opens with something else.
    final String? chosen = _read(
        'Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\'
        '.$extension\\UserChoice',
        'ProgId');
    return chosen != null && chosen.isNotEmpty ? chosen : null;
  }

  static bool _write(String path, String? name, String value) {
    final Pointer<Utf16> subKey = path.toNativeUtf16();
    final Pointer<IntPtr> handle = calloc<IntPtr>();
    final Pointer<Uint32> disposition = calloc<Uint32>();
    try {
      final int created = _advapi32!
          .lookupFunction<_RegCreateKeyExN, _RegCreateKeyExD>('RegCreateKeyExW')(
        _hkcu, subKey, 0, nullptr, 0, _keyWrite, nullptr, handle, disposition,
      );
      if (created != _errorSuccess) return false;
      final Pointer<Utf16> data = value.toNativeUtf16();
      final Pointer<Utf16> valueName = name == null ? nullptr : name.toNativeUtf16();
      try {
        // Bytes, including the terminator: RegSetValueExW is given a length
        // in bytes, and a string written without its null is read back with
        // whatever follows it in the registry.
        final int bytes = (value.length + 1) * 2;
        final int set = _advapi32!
            .lookupFunction<_RegSetValueExN, _RegSetValueExD>('RegSetValueExW')(
          handle.value, valueName, 0, _regSz, data.cast<Uint8>(), bytes,
        );
        return set == _errorSuccess;
      } finally {
        calloc.free(data);
        if (valueName != nullptr) calloc.free(valueName);
        _close(handle.value);
      }
    } finally {
      calloc.free(subKey);
      calloc.free(handle);
      calloc.free(disposition);
    }
  }

  static String? _read(String path, String? name) {
    final Pointer<Utf16> subKey = path.toNativeUtf16();
    final Pointer<IntPtr> handle = calloc<IntPtr>();
    try {
      final int opened = _advapi32!
          .lookupFunction<_RegOpenKeyExN, _RegOpenKeyExD>('RegOpenKeyExW')(
        _hkcu, subKey, 0, _keyRead, handle,
      );
      if (opened != _errorSuccess) return null;
      final Pointer<Utf16> valueName = name == null ? nullptr : name.toNativeUtf16();
      final Pointer<Uint32> size = calloc<Uint32>();
      try {
        final _RegQueryValueExD query = _advapi32!
            .lookupFunction<_RegQueryValueExN, _RegQueryValueExD>('RegQueryValueExW');
        // Asked twice: once for the length, once for the value. A fixed
        // buffer would truncate a long command line into something that
        // looks like a different handler.
        if (query(handle.value, valueName, nullptr, nullptr, nullptr, size) !=
            _errorSuccess) {
          return null;
        }
        if (size.value == 0) return '';
        final Pointer<Uint8> buffer = calloc<Uint8>(size.value + 2);
        try {
          if (query(handle.value, valueName, nullptr, nullptr, buffer, size) !=
              _errorSuccess) {
            return null;
          }
          return buffer.cast<Utf16>().toDartString();
        } finally {
          calloc.free(buffer);
        }
      } finally {
        if (valueName != nullptr) calloc.free(valueName);
        calloc.free(size);
        _close(handle.value);
      }
    } finally {
      calloc.free(subKey);
      calloc.free(handle);
    }
  }

  static void _delete(String path) {
    final Pointer<Utf16> subKey = path.toNativeUtf16();
    try {
      _advapi32!.lookupFunction<_RegDeleteTreeN, _RegDeleteTreeD>('RegDeleteTreeW')(
        _hkcu, subKey,
      );
    } finally {
      calloc.free(subKey);
    }
  }

  static void _close(int handle) => _advapi32!
      .lookupFunction<_RegCloseKeyN, _RegCloseKeyD>('RegCloseKey')(handle);

  static void _notifyShell() {
    final DynamicLibrary? shell32 = _shell32;
    if (shell32 == null) return;
    shell32.lookupFunction<_ShChangeNotifyN, _ShChangeNotifyD>('SHChangeNotify')(
      _shcneAssocChanged, _shcnfIdList, nullptr, nullptr,
    );
  }
}
