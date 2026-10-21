/// The installed fonts on Windows: the registry's font list, over dart:ffi.
///
/// `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` (every user) and
/// the same key under HKCU (fonts a user installed for themselves, Windows 10
/// 1809 and later) name each installed font's file; that list is what GDI and
/// DirectWrite load at startup. Read with advapi32's RegEnumValueW, and each
/// file's faces read from the file's own tables (font_file.dart), because a
/// value name like "Arial Bold (TrueType)" is a display string, not a family.
///
/// DirectWrite's IDWriteFontCollection gives families too, but through COM
/// vtables and with no file path without a further loader interface; the
/// registry gives the paths `fonts.read` needs in one call. Written and
/// unit-tested off Windows (the path rules); not yet run on a Windows machine.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../font_files_io.dart';

typedef _OpenN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _OpenD = int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>);
typedef _EnumN = Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _EnumD = int Function(int, int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);

const int _hkcu = 0x80000001;
const int _hklm = 0x80000002;
const int _keyRead = 0x20019;
const int _regSz = 1;
const int _regExpandSz = 2;
const String _fontsKey = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts';

class DVWindowsFonts {
  const DVWindowsFonts._();

  static const Set<String> implemented = <String>{'fonts.faces', 'fonts.read'};

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    final DynamicLibrary? advapi32 = _open();
    bind('fonts.faces', (Object? _) => <String, Object?>{
          'faces': DVFontFiles.facesIn(fontFiles(advapi32)),
        });
    bind('fonts.read', DVFontFiles.read);
  }

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('advapi32.dll');
    } on ArgumentError {
      return null;
    }
  }

  /// The installed font files: the registry's lists, else the two fonts
  /// folders when the registry cannot be read.
  static List<String> fontFiles(DynamicLibrary? advapi32) {
    final String windows = Platform.environment['WINDIR'] ?? Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final String? local = Platform.environment['LOCALAPPDATA'];
    final String systemFonts = '$windows\\Fonts';
    final String? userFonts = local == null ? null : '$local\\Microsoft\\Windows\\Fonts';
    final List<String> listed = <String>[
      if (advapi32 != null) ...<String>[
        for (final String value in _values(advapi32, _hklm)) resolve(value, systemFonts),
        for (final String value in _values(advapi32, _hkcu)) resolve(value, userFonts ?? systemFonts),
      ],
    ];
    final List<String> files = listed.isNotEmpty
        ? listed
        : DVFontFiles.filesUnder(<String>[systemFonts, ?userFonts]);
    final Set<String> seen = <String>{};
    return <String>[
      for (final String file in files)
        if (_isScalable(file) && seen.add(file.toLowerCase())) file,
    ];
  }

  /// A registry font value as a path: absolute for a per-user font, a bare
  /// file name (in [folder]) for one installed for every user.
  static String resolve(String value, String folder) {
    final String trimmed = value.trim();
    final bool absolute = trimmed.startsWith(r'\\') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
    return absolute ? trimmed : '$folder\\$trimmed';
  }

  /// TrueType and OpenType files; the registry lists .fon bitmap fonts too,
  /// which FontLoader cannot take.
  static bool _isScalable(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc') || lower.endsWith('.otc');
  }

  static List<String> _values(DynamicLibrary advapi32, int root) {
    final _OpenD open = advapi32.lookupFunction<_OpenN, _OpenD>('RegOpenKeyExW');
    final _EnumD enumValue = advapi32.lookupFunction<_EnumN, _EnumD>('RegEnumValueW');
    final _CloseD close = advapi32.lookupFunction<_CloseN, _CloseD>('RegCloseKey');
    final Pointer<Utf16> key = _fontsKey.toNativeUtf16();
    final Pointer<IntPtr> handle = calloc<IntPtr>();
    const int nameCapacity = 16384;
    const int dataCapacity = 4096;
    final Pointer<Utf16> name = calloc<Uint16>(nameCapacity).cast<Utf16>();
    final Pointer<Uint8> data = calloc<Uint8>(dataCapacity);
    final Pointer<Uint32> nameLength = calloc<Uint32>();
    final Pointer<Uint32> dataLength = calloc<Uint32>();
    final Pointer<Uint32> type = calloc<Uint32>();
    final List<String> values = <String>[];
    try {
      if (open(root, key, 0, _keyRead, handle) != 0) return values;
      try {
        for (int index = 0;; index++) {
          nameLength.value = nameCapacity;
          dataLength.value = dataCapacity;
          final int result = enumValue(handle.value, index, name, nameLength, nullptr, type, data, dataLength);
          if (result == 259) break; // ERROR_NO_MORE_ITEMS
          if (result != 0) continue; // ERROR_MORE_DATA and the like: skip the one value
          if (type.value != _regSz && type.value != _regExpandSz) continue;
          final String text = data.cast<Utf16>().toDartString(length: dataLength.value ~/ 2);
          final String value = text.replaceAll('\u0000', '');
          if (value.isNotEmpty) values.add(value);
        }
      } finally {
        close(handle.value);
      }
    } finally {
      calloc.free(key);
      calloc.free(handle);
      calloc.free(name);
      calloc.free(data);
      calloc.free(nameLength);
      calloc.free(dataLength);
      calloc.free(type);
    }
    return values;
  }
}
