/// The installed fonts on Linux, from fontconfig, over dart:ffi.
///
/// fontconfig is what every Linux desktop, and Flutter's own Linux engine,
/// uses to find fonts, so the list here is the list the rest of the desktop
/// sees: `fc-list` with the same pattern prints the same families. Needs no
/// display, so a headless eLinux panel lists its fonts too.
library dartvel_flutter.platform.linux.fonts;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import '../font_files_io.dart';

final class _FcFontSet extends Struct {
  @Int32()
  external int nfont;
  @Int32()
  external int sfont;
  external Pointer<Pointer<Void>> fonts;
}

typedef _VoidPtrN = Pointer<Void> Function();
typedef _InitN = Int32 Function();
typedef _InitD = int Function();
typedef _AddN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _AddD = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _ListN = Pointer<_FcFontSet> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _GetStringN = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Pointer<Utf8>>);
typedef _GetStringD = int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Pointer<Utf8>>);
typedef _GetIntN = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Int32>);
typedef _GetIntD = int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Int32>);
typedef _DestroyN = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);
typedef _DestroySetN = Void Function(Pointer<_FcFontSet>);
typedef _DestroySetD = void Function(Pointer<_FcFontSet>);
typedef _WeightN = Int32 Function(Int32);
typedef _WeightD = int Function(int);

class DVLinuxFonts {
  const DVLinuxFonts._();

  /// Registers `fonts.faces` and `fonts.read`. False, registering nothing,
  /// where libfontconfig cannot be opened.
  static bool register() {
    final DynamicLibrary? library = _open();
    if (library == null) return false;
    DVNativeBridge.register('fonts.faces', (Object? _) => <String, Object?>{'faces': faces(library)});
    DVNativeBridge.register('fonts.read', DVFontFiles.read);
    return true;
  }

  static DynamicLibrary? _open() {
    for (final String name in <String>['libfontconfig.so.1', 'libfontconfig.so']) {
      try {
        return DynamicLibrary.open(name);
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  /// Every scalable (TrueType or OpenType) face fontconfig knows, as
  /// `fonts.faces` entries.
  ///
  /// Bitmap and Type 1 faces are left out: neither is a font the engine's
  /// FontLoader takes, and a family that lists and then cannot be loaded is
  /// worse than one that is not listed. A variable font's named instances are
  /// left out too, since loading its file gives the default instance only.
  static List<Map<String, Object?>> faces([DynamicLibrary? library]) {
    final DynamicLibrary fc = library ?? _open()!;
    final _InitD init = fc.lookupFunction<_InitN, _InitD>('FcInit');
    final Pointer<Void> Function() patternCreate = fc.lookupFunction<_VoidPtrN, _VoidPtrN>('FcPatternCreate');
    final Pointer<Void> Function() objectSetCreate = fc.lookupFunction<_VoidPtrN, _VoidPtrN>('FcObjectSetCreate');
    final _AddD objectSetAdd = fc.lookupFunction<_AddN, _AddD>('FcObjectSetAdd');
    final Pointer<_FcFontSet> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>) fontList =
        fc.lookupFunction<_ListN, _ListN>('FcFontList');
    final _GetStringD getString = fc.lookupFunction<_GetStringN, _GetStringD>('FcPatternGetString');
    final _GetIntD getInt = fc.lookupFunction<_GetIntN, _GetIntD>('FcPatternGetInteger');
    final _DestroyD patternDestroy = fc.lookupFunction<_DestroyN, _DestroyD>('FcPatternDestroy');
    final _DestroyD objectSetDestroy = fc.lookupFunction<_DestroyN, _DestroyD>('FcObjectSetDestroy');
    final _DestroySetD fontSetDestroy = fc.lookupFunction<_DestroySetN, _DestroySetD>('FcFontSetDestroy');
    _WeightD? toOpenType;
    try {
      toOpenType = fc.lookupFunction<_WeightN, _WeightD>('FcWeightToOpenType');
    } on ArgumentError {
      toOpenType = null; // fontconfig before 2.11.91
    }

    if (init() == 0) return const <Map<String, Object?>>[];
    final Map<String, Pointer<Utf8>> names = <String, Pointer<Utf8>>{
      for (final String object in <String>['family', 'style', 'file', 'weight', 'slant', 'width', 'index', 'fontformat'])
        object: object.toNativeUtf8(),
    };
    final Pointer<Void> pattern = patternCreate();
    final Pointer<Void> objects = objectSetCreate();
    final Pointer<Pointer<Utf8>> text = calloc<Pointer<Utf8>>();
    final Pointer<Int32> number = calloc<Int32>();
    final List<Map<String, Object?>> faces = <Map<String, Object?>>[];
    try {
      for (final Pointer<Utf8> object in names.values) {
        objectSetAdd(objects, object);
      }
      final Pointer<_FcFontSet> set = fontList(nullptr, pattern, objects);
      if (set == nullptr) return faces;
      try {
        final int count = set.ref.nfont;
        String? stringOf(Pointer<Void> font, String object) =>
            getString(font, names[object]!, 0, text) == 0 ? text.value.toDartString() : null;
        int? intOf(Pointer<Void> font, String object) =>
            getInt(font, names[object]!, 0, number) == 0 ? number.value : null;

        for (int i = 0; i < count; i++) {
          final Pointer<Void> font = set.ref.fonts[i];
          final String? family = stringOf(font, 'family');
          final String? file = stringOf(font, 'file');
          final String format = stringOf(font, 'fontformat') ?? '';
          if (family == null || file == null) continue;
          if (format != 'TrueType' && format != 'CFF') continue;
          final int index = intOf(font, 'index') ?? 0;
          if (index >> 16 != 0) continue; // a variable font's named instance
          final int? weight = intOf(font, 'weight');
          final int slant = intOf(font, 'slant') ?? 0;
          faces.add(<String, Object?>{
            'family': family,
            'style': stringOf(font, 'style') ?? 'Regular',
            'weight': weight == null ? 400 : (toOpenType?.call(weight) ?? _openTypeWeight(weight)),
            'italic': slant != 0,
            'width': _widthClass(intOf(font, 'width') ?? 100),
            'path': file,
            'index': index,
          });
        }
      } finally {
        fontSetDestroy(set);
      }
    } finally {
      objectSetDestroy(objects);
      patternDestroy(pattern);
      calloc.free(text);
      calloc.free(number);
      for (final Pointer<Utf8> object in names.values) {
        calloc.free(object);
      }
    }
    DVFontFiles.remember(<String>[for (final Map<String, Object?> face in faces) face['path']! as String]);
    return faces;
  }

  /// fontconfig's weight scale (80 regular, 200 bold) on OpenType's (400,
  /// 700), for a fontconfig too old to say itself.
  static int _openTypeWeight(int weight) => switch (weight) {
        <= 0 => 100,
        <= 40 => 200,
        <= 50 => 300,
        <= 80 => 400,
        <= 100 => 500,
        <= 180 => 600,
        <= 200 => 700,
        <= 205 => 800,
        _ => 900,
      };

  /// fontconfig's width (100 normal, 75 condensed) as the OpenType width
  /// class (5 normal, 3 condensed).
  static int _widthClass(int width) => switch (width) {
        <= 56 => 1,
        <= 68 => 2,
        <= 81 => 3,
        <= 93 => 4,
        <= 106 => 5,
        <= 119 => 6,
        <= 137 => 7,
        <= 175 => 8,
        _ => 9,
      };
}
