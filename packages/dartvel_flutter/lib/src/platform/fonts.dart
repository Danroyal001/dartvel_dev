// The fonts installed on the machine, and using one in Flutter text.
//
// Behind `DV.Platform.fonts`. The platform lists its faces through the
// `fonts.faces` binding -- fontconfig on Linux, the registry's font list on
// Windows, CoreText on macOS, /system/fonts on Android, the Local Font Access
// API in a browser that has it -- and hands a face's bytes over through
// `fonts.read`. Everything else is here, once, for every target: grouping
// faces into families, saying why a list is empty, and loading a family into
// the engine with FontLoader so a `TextStyle(fontFamily: ...)` renders in it.
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../dartvel_flutter.dart' show DVNativeBridge;

/// One installed face of a family: Bold, Light Italic, Condensed.
@immutable
class DVSystemFontFace {
  const DVSystemFontFace({
    required this.family,
    required this.style,
    this.weight = FontWeight.w400,
    this.italic = false,
    this.width = 5,
    this.path,
    this.id,
    this.index = 0,
  });

  /// The family the face belongs to, as the font names it.
  final String family;

  /// The face's own name within the family: "Bold", "Condensed Oblique".
  final String style;

  final FontWeight weight;
  final bool italic;

  /// The width class, 1 to 9: 5 is normal, below it condensed, above it wide.
  final int width;

  /// The font file, where the platform has files. Null in a browser.
  final String? path;

  /// What the platform names the face by when it has no file (a browser's
  /// PostScript name).
  final String? id;

  /// The face's index in a font collection (`.ttc`); 0 otherwise.
  final int index;

  /// Decodes one entry of a `fonts.faces` answer. Null for an entry that names
  /// no family, which no `TextStyle` could ever ask for.
  static DVSystemFontFace? fromBinding(Object? raw) {
    if (raw is! Map) return null;
    final Object? family = raw['family'];
    if (family is! String || family.trim().isEmpty) return null;
    final Object? weight = raw['weight'];
    final Object? width = raw['width'];
    final Object? index = raw['index'];
    return DVSystemFontFace(
      family: family.trim(),
      style: raw['style'] is String ? (raw['style']! as String).trim() : 'Regular',
      weight: _weightFor(weight is num ? weight.toInt() : 400),
      italic: raw['italic'] == true,
      width: width is num && width >= 1 && width <= 9 ? width.toInt() : 5,
      path: raw['path'] is String ? raw['path']! as String : null,
      id: raw['id'] is String ? raw['id']! as String : null,
      index: index is num ? index.toInt() : 0,
    );
  }

  static FontWeight _weightFor(int weight) {
    final int nearest = ((weight.clamp(100, 900) / 100).round()) - 1;
    return FontWeight.values[nearest.clamp(0, FontWeight.values.length - 1)];
  }

  @override
  String toString() => 'DVSystemFontFace($family $style)';
}

/// The installed font families, by name, sorted.
///
/// A list like any other, plus [reason]: why it is empty, when it is. "This
/// machine has no fonts" and "this browser will not say" are different
/// answers, and an empty list alone cannot tell them apart.
class DVFontFamilies extends UnmodifiableListView<String> {
  DVFontFamilies(super.source, {this.reason});

  /// Why the platform listed nothing, or null when it listed what it has.
  final String? reason;
}

/// A family that cannot be loaded, and why.
class DVSystemFontUnavailable implements Exception {
  const DVSystemFontUnavailable(this.family, this.reason);

  final String family;
  final String reason;

  @override
  String toString() => 'DVSystemFontUnavailable: $family: $reason';
}

/// The fonts installed on the machine.
///
/// ```dart
/// final DVFontFamilies families = await DV.Platform.fonts.families();
/// if (families.isEmpty) showNote(families.reason!);
///
/// final String family = await DV.Platform.fonts.load('DejaVu Sans');
/// DVText('Amazing grace').fontFamily(family);
/// ```
class DVSystemFonts {
  const DVSystemFonts();

  static final Set<String> _loaded = <String>{};
  static final Map<String, Future<String>> _loading = <String, Future<String>>{};

  /// Every installed family, once each, sorted without regard to case.
  ///
  /// Never throws. Where the platform cannot list its fonts the list is empty
  /// and [DVFontFamilies.reason] says why: a browser without the Local Font
  /// Access API, a person who declined it, a platform not built yet.
  Future<DVFontFamilies> families() async {
    final ({List<DVSystemFontFace> faces, String? reason}) listing = await _list();
    final Map<String, String> byKey = <String, String>{};
    for (final DVSystemFontFace face in listing.faces) {
      byKey.putIfAbsent(face.family.toLowerCase(), () => face.family);
    }
    final List<String> names = byKey.values.toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return DVFontFamilies(names, reason: names.isEmpty ? listing.reason ?? _emptyReason : null);
  }

  /// Every installed face, or those of [family] (matched without regard to
  /// case), in the order the platform lists them. Empty where
  /// [families] would be, for the same reason.
  Future<List<DVSystemFontFace>> faces({String? family}) async {
    final List<DVSystemFontFace> all = (await _list()).faces;
    if (family == null) return all;
    final String key = family.toLowerCase();
    return <DVSystemFontFace>[
      for (final DVSystemFontFace face in all)
        if (face.family.toLowerCase() == key) face,
    ];
  }

  /// Whether [family] has been loaded into the engine by [load].
  bool isLoaded(String family) => _loaded.contains(family.toLowerCase());

  /// Loads an installed [family] into the engine and returns the name to use
  /// as `fontFamily`, spelled as the font spells it.
  ///
  /// One face per weight and slant, because that is all a `TextStyle` can ask
  /// for: where a family has a normal and a condensed face of the same weight,
  /// the normal one. Loading a family twice reads it once.
  ///
  /// On a desktop the engine can often find an installed family by name
  /// without this; loading makes it certain -- a font installed after the app
  /// started, a face fontconfig would substitute, and every browser, where the
  /// page can draw only the fonts it has been given.
  ///
  /// Throws [DVSystemFontUnavailable] when the family is not installed or
  /// the platform cannot hand its files over.
  Future<String> load(String family) {
    final String key = family.toLowerCase();
    return _loading.putIfAbsent(key, () async {
      try {
        return await _load(family);
      } catch (_) {
        // Forgotten so a later call tries again: the font may be installed
        // by then. The future removed is this one, already being awaited.
        // ignore: unawaited_futures
        _loading.remove(key);
        rethrow;
      }
    });
  }

  Future<String> _load(String family) async {
    final ({List<DVSystemFontFace> faces, String? reason}) listing = await _list();
    final String key = family.toLowerCase();
    final List<DVSystemFontFace> matching = <DVSystemFontFace>[
      for (final DVSystemFontFace face in listing.faces)
        if (face.family.toLowerCase() == key) face,
    ];
    if (matching.isEmpty) {
      throw DVSystemFontUnavailable(
        family,
        listing.faces.isEmpty
            ? listing.reason ?? _emptyReason
            : '$family is not installed on this machine.',
      );
    }
    final String name = matching.first.family;

    // One face per weight and slant; of several, the width nearest normal.
    final Map<(FontWeight, bool), DVSystemFontFace> chosen = <(FontWeight, bool), DVSystemFontFace>{};
    for (final DVSystemFontFace face in matching) {
      final (FontWeight, bool) slot = (face.weight, face.italic);
      final DVSystemFontFace? held = chosen[slot];
      if (held == null || (face.width - 5).abs() < (held.width - 5).abs()) chosen[slot] = face;
    }

    final FontLoader loader = FontLoader(name);
    final List<String> unread = <String>[];
    int added = 0;
    for (final DVSystemFontFace face in chosen.values) {
      Object? bytes;
      try {
        bytes = await DVNativeBridge.invoke<Object?>('fonts.read', <String, Object?>{
          'path': ?face.path,
          'id': ?face.id,
          'index': face.index,
        });
      } catch (error) {
        unread.add('${face.style}: $error');
        continue;
      }
      final Uint8List? data = switch (bytes) {
        final Uint8List list => list,
        final List<int> list => Uint8List.fromList(list),
        _ => null,
      };
      if (data == null || data.isEmpty) {
        unread.add('${face.style}: no bytes');
        continue;
      }
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(data)));
      added++;
    }
    if (added == 0) {
      throw DVSystemFontUnavailable(
        family,
        DVNativeBridge.isRegistered('fonts.read')
            ? 'None of $name\'s faces could be read (${unread.join('; ')}).'
            : 'This platform lists its fonts but cannot hand their files over.',
      );
    }
    await loader.load();
    _loaded.add(key);
    return name;
  }

  Future<({List<DVSystemFontFace> faces, String? reason})> _list() async {
    if (!DVNativeBridge.isRegistered('fonts.faces')) {
      return (faces: const <DVSystemFontFace>[], reason: _unboundReason());
    }
    final Object? raw;
    try {
      raw = await DVNativeBridge.invoke<Object?>('fonts.faces');
    } catch (error) {
      return (faces: const <DVSystemFontFace>[], reason: 'Listing the installed fonts failed: $error');
    }
    final Object? list = raw is Map ? raw['faces'] : raw;
    final String? reason = raw is Map && raw['reason'] is String ? raw['reason']! as String : null;
    final List<DVSystemFontFace> faces = <DVSystemFontFace>[
      if (list is List)
        for (final Object? entry in list) ?DVSystemFontFace.fromBinding(entry),
    ];
    return (faces: faces, reason: reason);
  }

  static const String _emptyReason =
      'The platform answered, and listed no installed fonts.';

  /// Why a platform with no `fonts.faces` binding has no list.
  static String _unboundReason() {
    if (kIsWeb) {
      return 'This browser has no Local Font Access API (window.queryLocalFonts, '
          'Chromium browsers only), so a page cannot see the fonts installed on '
          'the machine. Ship the fonts the app needs with it.';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iOS does not let an app read the fonts installed on '
          'the device; UIKit names the system families, and Dartvel does not bind '
          'that yet. Ship the fonts the app needs with it.',
      TargetPlatform.fuchsia => 'Fuchsia has no font list Dartvel can read.',
      _ => 'The platform bindings are not registered, so nothing has asked the '
          'system for its fonts. They are registered when the generated app starts.',
    };
  }

  /// Forgets what [load] loaded. For tests: the engine keeps the fonts.
  @visibleForTesting
  static void debugReset() {
    _loaded.clear();
    _loading.clear();
  }
}
