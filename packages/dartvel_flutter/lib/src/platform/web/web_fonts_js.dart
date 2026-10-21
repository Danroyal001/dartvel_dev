/// `fonts.faces` and `fonts.read` through the Local Font Access API.
///
/// `window.queryLocalFonts()` is Chromium only (Chrome and Edge 103+), behind
/// the `local-fonts` permission, and the first call needs a user gesture to
/// show the prompt. So both names are registered only where the method
/// exists, and every other browser leaves them unregistered: then
/// `DV.Platform.fonts` answers an empty list with the reason, rather than an
/// empty list that reads as a machine with no fonts.
///
/// A person who declines, or a call with no gesture behind it while the
/// permission is still unasked, is not an error either: the answer is no
/// faces and the browser's own words as the reason.
///
/// A page can draw only the fonts it has been given, so this is also where
/// loading matters most: `fonts.read` hands a face's bytes (`FontData.blob()`)
/// to `DV.Platform.fonts.load`, which gives them to the engine.
library dartvel_flutter.platform.web.fonts;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../font_file.dart';
import 'web_interop.dart';

class DVWebFonts {
  const DVWebFonts._();

  static const Set<String> implemented = <String>{'fonts.faces', 'fonts.read'};

  /// Whether this browser has `window.queryLocalFonts`.
  static bool get available => dvJsMethod(globalContext, 'queryLocalFonts') != null;

  /// The FontData objects of the last listing, by PostScript name, so a read
  /// is of a face that was listed rather than a second permission prompt.
  static final Map<String, JSObject> _listed = <String, JSObject>{};

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('fonts.faces', (Object? _) => faces());
    register('fonts.read', (Object? arguments) => read(arguments));
  }

  /// Every face the browser will show this page, as `fonts.faces` answers.
  static Future<Map<String, Object?>> faces() async {
    final JSAny? result;
    try {
      result = await dvJsCall(globalContext, 'queryLocalFonts');
    } on Object catch (error) {
      return <String, Object?>{
        'faces': const <Object?>[],
        'reason': 'The browser did not let this page see the installed fonts: '
            '${dvJsReason(error).replaceFirst(RegExp(r'\.+$'), '')}. It asks once, from a click or a key press.',
      };
    }
    if (result == null || !result.isA<JSArray<JSObject>>()) {
      return <String, Object?>{'faces': const <Object?>[], 'reason': 'queryLocalFonts answered with no list.'};
    }
    _listed.clear();
    final List<Map<String, Object?>> faces = <Map<String, Object?>>[];
    for (final JSObject font in (result as JSArray<JSObject>).toDart) {
      final String? family = dvJsString(font, 'family');
      final String? postscript = dvJsString(font, 'postscriptName');
      if (family == null || family.isEmpty || postscript == null) continue;
      final String style = dvJsString(font, 'style') ?? 'Regular';
      _listed[postscript] = font;
      faces.add(<String, Object?>{
        'family': family,
        'style': style,
        'weight': dvFontWeightFromStyle(style),
        'italic': dvFontItalicFromStyle(style),
        'width': dvFontWidthFromStyle(style),
        'id': postscript,
      });
    }
    return <String, Object?>{'faces': faces};
  }

  /// `fonts.read`: the bytes of a listed face.
  static Future<Uint8List> read(Object? arguments) async {
    final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
    final Object? id = map['id'];
    final JSObject? font = id is String ? _listed[id] : null;
    if (font == null) {
      throw ArgumentError('fonts.read reads only a face fonts.faces listed, not $id.');
    }
    try {
      final JSObject blob = (await dvJsCall(font, 'blob'))! as JSObject;
      final JSAny? buffer = await dvJsCall(blob, 'arrayBuffer');
      return (buffer! as JSArrayBuffer).toDart.asUint8List();
    } on Object catch (error) {
      dvJsRefused('fonts.read', error);
    }
  }
}
