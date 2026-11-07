/// The fonts a Flutter web page downloads, made as small as they can be
/// without changing what the page draws.
///
/// Flutter web fetches every font FontManifest.json lists, and the engine
/// waits for all of them before its first frame, so font bytes sit directly
/// on the path to a visible app. Measured on sigmadev.digital (a Dartvel
/// 0.13.21 web-server site, first visit from a phone): 1.3 MB of fonts out of
/// 3.8 MB, all of it TrueType --
///
/// * four static Inter weights beside the variable Inter that draws every
///   weight. The engine sets the `wght` axis from each TextStyle's
///   FontWeight, in CanvasKit and in skwasm alike, so the variable file
///   alone draws all four;
/// * every font whole, Cyrillic, Greek and Vietnamese included, on a site
///   whose every word is English;
/// * Roboto from fonts.gstatic.com, which the engine fetches whenever the
///   manifest has no family called Roboto -- a third-party request on every
///   first visit, and a font the page may never draw.
///
/// So the build, for `web` and `web-server` alike:
///
/// 1. serves a family of static faces from a variable font of the same design
///    when that font covers every one of them (same family name, weights
///    inside its axis, same slope, every character);
/// 2. drops a family that no compiled code and no data asset names;
/// 3. subsets each text font to Latin, the common punctuation and symbols,
///    and every character the project's own sources and content contain
///    (`dartvel.web.fonts.characters` adds more). A character typed by a
///    reader that the subset lacks is still drawn: the engine's font
///    fallback fetches a Noto face for it, as it does for emoji and CJK;
/// 4. writes each one as WOFF2 under a content-hashed name, which a server
///    sends as immutable;
/// 5. adds Roboto from the Flutter SDK's own copy, subset and compressed the
///    same way, so the engine finds it in the manifest and asks Google for
///    nothing.
///
/// The originals stay where Flutter put them, because `rootBundle` can still
/// load one by its asset key; only the manifest the engine reads changes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

import 'woff2.dart';

/// One font file in a FontManifest family.
final class DVManifestFont {
  DVManifestFont({required this.asset, this.weight, this.style});

  /// The asset key; the file is at `assets/<asset>` under the web root.
  final String asset;
  final int? weight;
  final String? style;

  Map<String, Object?> toJson() => <String, Object?>{
        if (weight != null) 'weight': weight,
        if (style != null) 'style': style,
        'asset': asset,
      };
}

/// One family in FontManifest.json.
final class DVManifestFamily {
  DVManifestFamily(this.family, this.fonts);

  final String family;
  final List<DVManifestFont> fonts;

  Map<String, Object?> toJson() => <String, Object?>{
        'family': family,
        'fonts': <Object?>[for (final DVManifestFont f in fonts) f.toJson()],
      };
}

/// FontManifest.json as families. Entries of the wrong shape are skipped.
List<DVManifestFamily> dvParseFontManifest(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! List) return <DVManifestFamily>[];
  return <DVManifestFamily>[
    for (final Object? entry in decoded)
      if (entry is Map && entry['family'] is String && entry['fonts'] is List)
        DVManifestFamily(entry['family']! as String, <DVManifestFont>[
          for (final Object? font in entry['fonts']! as List)
            if (font is Map && font['asset'] is String)
              DVManifestFont(
                asset: font['asset']! as String,
                weight: font['weight'] is num ? (font['weight']! as num).toInt() : null,
                style: font['style'] is String ? font['style']! as String : null,
              ),
        ]),
  ];
}

/// [manifest] as FontManifest.json.
String dvEncodeFontManifest(List<DVManifestFamily> manifest) =>
    jsonEncode(<Object?>[for (final DVManifestFamily f in manifest) f.toJson()]);

String _design(String family) {
  String name = family.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  for (final String suffix in const <String>['variable', 'vf']) {
    if (name.endsWith(suffix) && name.length > suffix.length) {
      name = name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// The families of static faces a variable font in the same manifest draws
/// in full, each with the asset of that variable font.
///
/// A family qualifies only when every one of its faces is covered: the same
/// design (the fonts' own family names, with "Variable" or "VF" taken off),
/// its weight inside the variable font's `wght` axis, the same slope, and no
/// character the variable font lacks. Anything less and the static family is
/// kept, because the variable font would draw some of its text differently.
///
/// [required] narrows "every character" to the ones a page can show: the
/// app's own text and Latin ([dvFontCoreRanges]). A symbol only the static
/// faces have and nothing writes is drawn by the engine's fallback in either
/// case once the fonts are subset. Null requires every character.
Map<String, String> dvVariableReplacements(
  List<DVManifestFamily> manifest,
  Map<String, DVFontFacts> facts, {
  Set<int>? required,
}) {
  final List<(String, DVFontFacts)> variable = <(String, DVFontFacts)>[
    for (final DVManifestFamily family in manifest)
      for (final DVManifestFont font in family.fonts)
        if (facts[font.asset]?.weightAxis != null) (font.asset, facts[font.asset]!),
  ];
  final Map<String, String> out = <String, String>{};
  for (final DVManifestFamily family in manifest) {
    if (family.fonts.isEmpty) continue;
    final List<(DVManifestFont, DVFontFacts)> faces = <(DVManifestFont, DVFontFacts)>[];
    for (final DVManifestFont font in family.fonts) {
      final DVFontFacts? face = facts[font.asset];
      if (face == null || face.axes.isNotEmpty) {
        faces.clear();
        break;
      }
      faces.add((font, face));
    }
    if (faces.isEmpty) continue;
    for (final (String asset, DVFontFacts v) in variable) {
      final DVFontAxis axis = v.weightAxis!;
      final bool covers = faces.every(((DVManifestFont, DVFontFacts) face) {
        final (DVManifestFont font, DVFontFacts f) = face;
        final int declared = font.weight ?? 400;
        return _design(f.family) == _design(v.family) &&
            f.italic == v.italic &&
            (font.style == 'italic') == v.italic &&
            declared >= axis.min &&
            declared <= axis.max &&
            f.weight >= axis.min &&
            f.weight <= axis.max &&
            f.codepoints.every((int c) =>
                v.codepoints.contains(c) || (required != null && !required.contains(c)));
      });
      if (covers) {
        out[family.family] = asset;
        break;
      }
    }
  }
  return out;
}

/// The families in [manifest] that nothing in [code] (the compiled app:
/// main.dart.js and its parts, main.dart.mjs, main.dart.wasm) and nothing in
/// [texts] (data the app reads: JSON assets, Studio pages) names.
///
/// A name counts in JavaScript when it stands alone between non-identifier
/// characters, which is how a string literal and the tail of
/// `"packages/" + p + "/Manrope"` both look. Anywhere else -- a wasm module,
/// whose strings may be UTF-8 or UTF-16, or a data file -- any occurrence
/// counts, so a stray match keeps a font rather than dropping it. With no
/// compiled code to read, nothing is dropped. Roboto is never dropped: the
/// engine asks for it by name.
Set<String> dvUnusedFamilies(
  List<DVManifestFamily> manifest, {
  required List<Uint8List> code,
  required List<String> texts,
}) {
  if (code.isEmpty) return <String>{};
  final Set<String> out = <String>{};
  for (final DVManifestFamily family in manifest) {
    if (family.family == 'Roboto') continue;
    final String name = family.family.split('/').last;
    if (name.isEmpty) continue;
    final List<int> utf8Name = utf8.encode(name);
    final List<int> utf16Name = <int>[
      for (final int unit in name.codeUnits) ...<int>[unit & 0xFF, unit >> 8],
    ];
    bool named = texts.any((String text) => text.contains(name));
    for (final Uint8List file in code) {
      if (named) break;
      final bool javascript = !_isWasm(file);
      named = _contains(file, utf8Name, bounded: javascript) ||
          (!javascript && _contains(file, utf16Name, bounded: false));
    }
    if (!named) out.add(family.family);
  }
  return out;
}

bool _isWasm(Uint8List file) =>
    file.length >= 4 && file[0] == 0 && file[1] == 0x61 && file[2] == 0x73 && file[3] == 0x6d;

bool _identifier(int byte) =>
    (byte >= 0x30 && byte <= 0x39) ||
    (byte >= 0x41 && byte <= 0x5A) ||
    (byte >= 0x61 && byte <= 0x7A) ||
    byte == 0x5F ||
    byte == 0x24;

bool _contains(Uint8List haystack, List<int> needle, {required bool bounded}) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  final int first = needle[0];
  final int last = haystack.length - needle.length;
  outer:
  for (int i = 0; i <= last; i++) {
    if (haystack[i] != first) continue;
    for (int k = 1; k < needle.length; k++) {
      if (haystack[i + k] != needle[k]) continue outer;
    }
    if (bounded) {
      if (i > 0 && _identifier(haystack[i - 1])) continue;
      final int after = i + needle.length;
      if (after < haystack.length && _identifier(haystack[after])) continue;
    }
    return true;
  }
  return false;
}

/// Latin as people write it -- every European language written in it,
/// Yoruba, Igbo, Hausa, Ewe and Akan, Vietnamese -- with its combining marks,
/// punctuation and the currency signs in use (₦ among them).
///
/// A variable font may stand in for static faces only when it draws every one
/// of these the static faces draw, as well as everything the app's own text
/// contains.
const List<(int, int)> dvFontCoreRanges = <(int, int)>[
  (0x0020, 0x007E), // Basic Latin
  (0x00A0, 0x024F), // Latin-1 Supplement, Latin Extended-A and -B (ƙ ƴ)
  (0x0250, 0x0263), // ɐ-ɣ: Hausa ɓ ɗ, Ewe and Akan ɛ ɔ, schwa
  (0x0272, 0x0272), // ɲ
  (0x028B, 0x028B), // ʋ
  (0x0292, 0x0292), // ʒ
  (0x02B0, 0x02FF), // Spacing modifier letters (ˆ ˜ ʼ)
  (0x0300, 0x036F), // Combining diacritical marks
  (0x1E00, 0x1EFF), // Latin Extended Additional (ẹ ọ ṣ, Vietnamese)
  (0x2000, 0x206F), // General punctuation
  (0x20A0, 0x20BF), // Currency symbols
];

/// What every text font keeps: [dvFontCoreRanges], and the symbols that turn
/// up in interface text -- superscripts, ™ and №, fractions, arrows, the
/// mathematical operators (− ≤ ≈), shapes and dingbats (● ★ ✓).
///
/// Measured on Inter: the rest of the IPA block alone would add 37 KB to
/// every page, for characters a reader types far more rarely than the engine
/// can fetch a Noto face for them.
const List<(int, int)> dvFontBaseRanges = <(int, int)>[
  ...dvFontCoreRanges,
  (0x2070, 0x209F), // Superscripts and subscripts
  (0x20C0, 0x20CF), // Currency symbols, the newest
  (0x2100, 0x218F), // Letterlike symbols, number forms
  (0x2190, 0x22FF), // Arrows, mathematical operators
  (0x25A0, 0x27BF), // Geometric shapes, miscellaneous symbols, dingbats
  (0x2C60, 0x2C7F), // Latin Extended-C
  (0xA720, 0xA7FF), // Latin Extended-D
  (0xFB00, 0xFB06), // Latin ligatures
  (0xFEFF, 0xFEFF),
  (0xFFFD, 0xFFFD), // Replacement character
];

const Set<String> _textExtensions = <String>{
  '.dart', '.json', '.arb', '.md', '.txt', '.yaml', '.yml', '.html', '.htm',
  '.csv', '.xml', '.toml',
};

const Set<String> _skippedDirectories = <String>{
  'build', '.dart_tool', '.git', '.dartvel', 'node_modules', '.idea',
  '.vscode', 'android', 'ios', 'macos', 'linux', 'windows', '.symlinks',
};

/// Every character outside Basic Latin that the project's own sources,
/// content and copy contain: what the app can show without a reader typing
/// it.
Set<int> dvProjectCharacters(String root) {
  final Set<int> out = <int>{};
  void walk(Directory directory) {
    final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entity in entries) {
      final String name = p.basename(entity.path);
      if (entity is Directory) {
        if (!_skippedDirectories.contains(name)) walk(entity);
      } else if (entity is File &&
          _textExtensions.contains(p.extension(name).toLowerCase())) {
        try {
          if (entity.lengthSync() > 8 * 1024 * 1024) continue;
          final String text =
              utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
          for (final int rune in text.runes) {
            if (rune >= 0x80 && rune != 0xFFFD && !_unwanted(rune)) out.add(rune);
          }
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  walk(Directory(root));
  return out;
}

bool _privateUse(int rune) =>
    (rune >= 0xE000 && rune <= 0xF8FF) || (rune >= 0xF0000 && rune <= 0x10FFFD);

bool _unwanted(int rune) =>
    (rune >= 0x80 && rune < 0xA0) || // C1 controls
    (rune >= 0xD800 && rune <= 0xDFFF) ||
    (rune >= 0xE000 && rune <= 0xF8FF); // Private use: icon fonts, not text

/// The characters a text font is subset to.
Set<int> dvFontSubsetCharacters({
  required Set<int> project,
  Iterable<int> extra = const <int>[],
  List<(int, int)> base = dvFontBaseRanges,
}) =>
    <int>{
      for (final (int start, int end) in base)
        for (int c = start; c <= end; c++) c,
      ...project,
      ...extra,
    };

/// `dartvel.web.fonts.characters`: a list of characters to keep beyond the
/// default, each entry either literal text (`'ŋ€'`) or a range
/// (`'U+0400-04FF'`, `'U+0416'`).
Set<int> dvParseCharacters(Object? declared) {
  final Set<int> out = <int>{};
  final List<Object?> entries =
      declared is List ? declared : (declared is String ? <Object?>[declared] : const <Object?>[]);
  final RegExp range = RegExp(r'^U\+([0-9A-Fa-f]{1,6})(?:-([0-9A-Fa-f]{1,6}))?$');
  for (final Object? entry in entries) {
    if (entry is! String) continue;
    final RegExpMatch? m = range.firstMatch(entry.trim());
    if (m != null) {
      final int start = int.parse(m.group(1)!, radix: 16);
      final int end = int.parse(m.group(2) ?? m.group(1)!, radix: 16);
      for (int c = start; c <= end && c <= 0x10FFFF; c++) {
        out.add(c);
      }
    } else {
      out.addAll(entry.runes);
    }
  }
  return out;
}

/// The Flutter SDK's root, from `FLUTTER_ROOT` or `flutter --version
/// --machine`; null when neither names one.
String? dvFlutterRootSync() {
  final String? declared = Platform.environment['FLUTTER_ROOT'];
  if (declared != null && Directory(declared).existsSync()) return declared;
  try {
    final ProcessResult result = Process.runSync(
        'flutter', const <String>['--version', '--machine'],
        runInShell: true);
    final String out = '${result.stdout}';
    final Object? json = jsonDecode(out.substring(out.indexOf('{')));
    final Object? root = json is Map ? json['flutterRoot'] : null;
    return root is String && Directory(root).existsSync() ? root : null;
  } on Object {
    return null;
  }
}

/// Flutter's `font-subset` (HarfBuzz's subsetter, which `flutter build`
/// already runs to tree-shake icon fonts), or null when this SDK has none
/// for the host.
String? dvFontSubsetTool(String flutterRoot) {
  final String engine = p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'engine');
  final List<String> hosts = Platform.isWindows
      ? const <String>['windows-x64', 'windows-arm64']
      : Platform.isMacOS
          ? const <String>['darwin-x64', 'darwin-arm64']
          : const <String>['linux-x64', 'linux-arm64'];
  final String name = Platform.isWindows ? 'font-subset.exe' : 'font-subset';
  for (final String host in hosts) {
    final File tool = File(p.join(engine, host, name));
    if (tool.existsSync()) return tool.path;
  }
  return null;
}

/// The Roboto the Flutter SDK carries for its test and desktop runs: the
/// same face the web engine otherwise fetches from fonts.gstatic.com.
File? dvRobotoSource(String flutterRoot) {
  final File roboto = File(
      p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'Roboto-Regular.ttf'));
  return roboto.existsSync() ? roboto : null;
}

/// `dartvel.web.fonts`: `false` switches every step off; a map switches
/// steps off one by one.
final class DVWebFontsOptions {
  const DVWebFontsOptions({
    this.enabled = true,
    this.subset = true,
    this.dropUnused = true,
    this.useVariable = true,
    this.roboto = true,
    this.characters = const <int>{},
  });

  /// From pubspec's `dartvel.web.fonts`.
  factory DVWebFontsOptions.parse(Object? declared) {
    if (declared == false) return const DVWebFontsOptions(enabled: false);
    if (declared is! Map) return const DVWebFontsOptions();
    bool flag(String key) => declared[key] != false;
    return DVWebFontsOptions(
      enabled: flag('optimize'),
      subset: flag('subset'),
      dropUnused: flag('dropUnused'),
      useVariable: flag('useVariable'),
      roboto: flag('roboto'),
      characters: dvParseCharacters(declared['characters']),
    );
  }

  final bool enabled;
  final bool subset;
  final bool dropUnused;
  final bool useVariable;
  final bool roboto;
  final Set<int> characters;
}

/// What [dvOptimizeWebFonts] did, for the build log.
final class DVWebFontsReport {
  const DVWebFontsReport({
    required this.lines,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  final List<String> lines;

  /// What the manifest's fonts weighed on the wire before (brotli, which is
  /// how a Dartvel server sends a TrueType file).
  final int bytesBefore;

  /// And after.
  final int bytesAfter;
}

/// What the engine's own Roboto weighs: the WOFF2 Flutter 3.47's web engine
/// fetches from fonts.gstatic.com (`roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw`),
/// measured. Counted in a build's "before" when the build serves Roboto
/// itself, because that download is one the page no longer makes.
const int dvGstaticRobotoBytes = 63464;

/// Where the build writes the fonts it made, under the web root's assets.
const String dvWebFontsDirectory = 'dartvel/fonts';

/// Rewrites the web build in [web] (`build/web`) so its fonts are as small
/// as they can be; see the library comment for every step.
///
/// [characters] is what a text font keeps ([dvFontSubsetCharacters]).
/// [subsetTool] is Flutter's font-subset, [roboto] the SDK's Roboto, and
/// [brotli] an encoder at its highest quality; without one the fonts stay
/// TrueType, subset. [texts] are data files the app reads, which can name a
/// family the code does not. [required] is what a variable font must draw
/// to stand in for static faces ([dvVariableReplacements]). [cache] keeps
/// each result by what made it.
Future<DVWebFontsReport> dvOptimizeWebFonts({
  required Directory web,
  required Set<int> characters,
  DVWebFontsOptions options = const DVWebFontsOptions(),
  String? subsetTool,
  File? roboto,
  Uint8List Function(Uint8List)? brotli,
  List<String> texts = const <String>[],
  Set<int>? required,
  Directory? cache,
}) async {
  const DVWebFontsReport nothing =
      DVWebFontsReport(lines: <String>[], bytesBefore: 0, bytesAfter: 0);
  final File manifestFile = File(p.join(web.path, 'assets', 'FontManifest.json'));
  if (!options.enabled || !manifestFile.existsSync()) return nothing;
  final List<DVManifestFamily> manifest;
  try {
    manifest = dvParseFontManifest(manifestFile.readAsStringSync());
  } on FormatException {
    return nothing;
  }

  File fileOf(String asset) => File(p.join(web.path, 'assets', asset));
  final Map<String, Uint8List> bytes = <String, Uint8List>{};
  final Map<String, DVFontFacts> facts = <String, DVFontFacts>{};
  for (final DVManifestFamily family in manifest) {
    for (final DVManifestFont font in family.fonts) {
      final File file = fileOf(font.asset);
      if (bytes.containsKey(font.asset) || !file.existsSync()) continue;
      bytes[font.asset] = file.readAsBytesSync();
      try {
        facts[font.asset] = dvFontFacts(bytes[font.asset]!);
      } on FormatException {
        // A WOFF, a collection, something else: carried as it is.
      } on RangeError {
        // A table shorter than it says: carried as it is.
      }
    }
  }

  final List<String> lines = <String>[];
  final Map<String, String> replaced = options.useVariable
      ? dvVariableReplacements(manifest, facts, required: required)
      : const <String, String>{};
  final Set<String> unused = options.dropUnused
      ? dvUnusedFamilies(manifest,
          code: _compiledCode(web), texts: <String>[...texts, ..._dataTexts(web)])
      : const <String>{};

  final List<DVManifestFamily> planned = <DVManifestFamily>[
    for (final DVManifestFamily family in manifest)
      if (!unused.contains(family.family))
        replaced[family.family] == null
            ? family
            : DVManifestFamily(family.family,
                <DVManifestFont>[DVManifestFont(asset: replaced[family.family]!)]),
  ];
  for (final MapEntry<String, String> r in replaced.entries) {
    if (unused.contains(r.key)) continue;
    final List<DVManifestFont> statics =
        manifest.firstWhere((DVManifestFamily f) => f.family == r.key).fonts;
    final Set<int> drawn = facts[r.value]!.codepoints;
    final List<int> gap = <int>{
      for (final DVManifestFont font in statics)
        ...facts[font.asset]!.codepoints.where((int c) => !drawn.contains(c)),
    }.toList()
      ..sort();
    lines.add('  ${r.key}: drawn by ${p.basename(r.value)} (variable), '
        '${statics.length} static file${statics.length == 1 ? '' : 's'} no longer downloaded'
        '${gap.isEmpty ? '' : '; ${gap.length} character${gap.length == 1 ? '' : 's'} only '
            'the static files had, which nothing in the app writes, fall back to Noto '
            '(${gap.take(6).map((int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')}'
            '${gap.length > 6 ? ' ...' : ''})'}');
  }
  for (final String family in unused) {
    lines.add('  $family: named nowhere in the app, no longer downloaded');
  }

  // Roboto, from the SDK, when the engine would otherwise fetch it.
  const String robotoAsset = '$dvWebFontsDirectory/Roboto-Regular.ttf';
  if (options.roboto &&
      roboto != null &&
      !planned.any((DVManifestFamily f) => f.family == 'Roboto')) {
    try {
      final Uint8List source = roboto.readAsBytesSync();
      facts[robotoAsset] = dvFontFacts(source);
      bytes[robotoAsset] = source;
      planned.add(DVManifestFamily('Roboto', <DVManifestFont>[DVManifestFont(asset: robotoAsset)]));
      lines.add('  Roboto: served from this site, no longer fetched from fonts.gstatic.com');
    } on Object {
      // No Roboto we can read: the engine fetches its own, as before.
    }
  }

  final Directory out = Directory(p.join(web.path, 'assets', dvWebFontsDirectory));
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final String keepKey = sha256
      .convert(utf8.encode((characters.toList()..sort()).join(',')))
      .toString();
  final Map<String, String> written = <String, String>{};
  int subsetCount = 0;
  for (final DVManifestFamily family in planned) {
    for (final DVManifestFont font in family.fonts) {
      if (written.containsKey(font.asset)) continue;
      final Uint8List? source = bytes[font.asset];
      final DVFontFacts? face = facts[font.asset];
      if (source == null || face == null) continue;
      final ({Uint8List bytes, String extension, bool subset})? made = await _make(
        source,
        face,
        characters: options.subset ? characters : null,
        keepKey: keepKey,
        subsetTool: subsetTool,
        brotli: brotli,
        cache: cache,
      );
      if (made == null) continue;
      if (made.subset) subsetCount++;
      final String stem = p
          .basenameWithoutExtension(font.asset)
          .replaceAll(RegExp('[^A-Za-z0-9-]'), '-');
      final String name = '$stem.${_hashedName(made.bytes)}.${made.extension}';
      File(p.join(out.path, name)).writeAsBytesSync(made.bytes);
      written[font.asset] = '$dvWebFontsDirectory/$name';
    }
  }

  final List<DVManifestFamily> result = <DVManifestFamily>[
    for (final DVManifestFamily family in planned)
      DVManifestFamily(family.family, <DVManifestFont>[
        for (final DVManifestFont font in family.fonts)
          if (font.asset == robotoAsset && written[font.asset] == null)
            ...<DVManifestFont>[]
          else
            DVManifestFont(
                asset: written[font.asset] ?? font.asset,
                weight: font.weight,
                style: font.style),
      ]),
  ]..removeWhere((DVManifestFamily f) => f.fonts.isEmpty);
  manifestFile.writeAsStringSync(dvEncodeFontManifest(result));

  int wire(Uint8List data, String name) {
    if (name.endsWith('.woff2') || brotli == null) return data.length;
    try {
      return brotli(data).length;
    } on Object {
      return data.length;
    }
  }

  final Set<String> beforeAssets = <String>{
    for (final DVManifestFamily f in manifest)
      for (final DVManifestFont font in f.fonts) font.asset,
  };
  final Set<String> afterAssets = <String>{
    for (final DVManifestFamily f in result)
      for (final DVManifestFont font in f.fonts) font.asset,
  };
  int before = 0;
  for (final String asset in beforeAssets) {
    final Uint8List? data = bytes[asset];
    if (data != null) before += wire(data, asset);
  }
  // The Roboto the engine would have fetched from fonts.gstatic.com, when
  // this build now serves its own: a download the page no longer makes.
  final bool robotoServed = written.containsKey(robotoAsset);
  if (robotoServed) before += dvGstaticRobotoBytes;
  int after = 0;
  for (final String asset in afterAssets) {
    final File file = fileOf(asset);
    if (file.existsSync()) after += wire(file.readAsBytesSync(), asset);
  }
  final int beforeFiles = beforeAssets.length + (robotoServed ? 1 : 0);
  return DVWebFontsReport(
    lines: <String>[
      'fonts: ${_size(before)} -> ${_size(after)} on the wire, '
          '$beforeFiles file${beforeFiles == 1 ? '' : 's'} -> ${afterAssets.length}'
          '${brotli == null ? '' : ', as WOFF2'}'
          '${robotoServed ? ' (before counts the Roboto fonts.gstatic.com sent)' : ''}',
      ...lines,
      if (subsetCount > 0)
        '  $subsetCount font${subsetCount == 1 ? '' : 's'} subset to Latin, common '
            'symbols and the app\'s own text; anything else a reader types is '
            'drawn by the engine\'s Noto fallback',
    ],
    bytesBefore: before,
    bytesAfter: after,
  );
}

String _size(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

/// Sixteen hex digits of [bytes]' hash, with at least one digit and one
/// letter: what a server recognises as a content-hashed name.
String _hashedName(Uint8List bytes) {
  final String hash = sha256.convert(bytes).toString();
  for (int i = 0; i + 16 <= hash.length; i++) {
    final String window = hash.substring(i, i + 16);
    if (window.contains(RegExp('[0-9]')) && window.contains(RegExp('[a-f]'))) return window;
  }
  return '${hash.substring(0, 15)}a';
}

/// The compiled app in [web]: main.dart.js and its parts, the wasm module
/// and its loader.
List<Uint8List> _compiledCode(Directory web) {
  if (!web.existsSync()) return const <Uint8List>[];
  return <Uint8List>[
    for (final FileSystemEntity f in web.listSync())
      if (f is File && p.basename(f.path).startsWith('main.dart.') &&
          !p.basename(f.path).endsWith('.symbols') &&
          !p.basename(f.path).endsWith('.map'))
        f.readAsBytesSync(),
  ];
}

/// The data files under [web]'s assets that the app reads and that could
/// name a font: every JSON file but the manifests Flutter writes.
List<String> _dataTexts(Directory web) {
  final Directory assets = Directory(p.join(web.path, 'assets'));
  if (!assets.existsSync()) return const <String>[];
  return <String>[
    for (final FileSystemEntity f in assets.listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.json') &&
          !p.basename(f.path).startsWith('FontManifest') &&
          !p.basename(f.path).startsWith('AssetManifest'))
        utf8.decode(f.readAsBytesSync(), allowMalformed: true),
  ];
}

const String _makeVersion = 'dartvel-web-fonts-1';

/// One font, subset (when it is a text font and [characters] is given) and
/// compressed; null when neither step changes it.
Future<({Uint8List bytes, String extension, bool subset})?> _make(
  Uint8List source,
  DVFontFacts face, {
  required Set<int>? characters,
  required String keepKey,
  required String? subsetTool,
  required Uint8List Function(Uint8List)? brotli,
  required Directory? cache,
}) async {
  final bool text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
      .codeUnits
      .every(face.codepoints.contains);
  final bool wantSubset = text &&
      characters != null &&
      subsetTool != null &&
      !characters.containsAll(face.codepoints);
  if (!wantSubset && brotli == null) return null;

  final String key = sha256
      .convert(<int>[
        ...utf8.encode('$_makeVersion|${wantSubset ? keepKey : '-'}|${brotli != null}|'),
        ...sha256.convert(source).bytes,
      ])
      .toString();
  final String extension = brotli == null ? 'ttf' : 'woff2';
  final File? cached = cache == null ? null : File(p.join(cache.path, '$key.$extension'));
  final File? cachedFlag = cache == null ? null : File(p.join(cache.path, '$key.subset'));
  if (cached != null && cached.existsSync()) {
    return (bytes: cached.readAsBytesSync(), extension: extension, subset: cachedFlag!.existsSync());
  }

  Uint8List font = source;
  bool subset = false;
  if (wantSubset) {
    final Uint8List? smaller = await _subset(source, face, characters, subsetTool);
    if (smaller != null) {
      font = smaller;
      subset = true;
    }
  }
  if (brotli != null) {
    try {
      font = dvWoff2Encode(font, brotli: brotli);
    } on Object {
      if (!subset) return null;
    }
  }
  final String ext = font.length >= 4 && font[0] == 0x77 && font[1] == 0x4F ? 'woff2' : 'ttf';
  if (cache != null && ext == extension) {
    cache.createSync(recursive: true);
    File(p.join(cache.path, '$key.$extension')).writeAsBytesSync(font);
    if (subset) File(p.join(cache.path, '$key.subset')).writeAsStringSync('');
  }
  return (bytes: font, extension: ext, subset: subset);
}

/// [source] subset to [characters] with Flutter's font-subset, or null when
/// the result is not provably the same font for every kept character: it
/// must parse, keep every kept character the source drew, keep the weight
/// axis, and be smaller.
Future<Uint8List?> _subset(
    Uint8List source, DVFontFacts face, Set<int> characters, String tool) async {
  final Directory temp = Directory.systemTemp.createTempSync('dartvel_font_subset_');
  try {
    final File input = File(p.join(temp.path, 'in.ttf'))..writeAsBytesSync(source);
    final File output = File(p.join(temp.path, 'out.ttf'));
    final Process process = await Process.start(tool, <String>[output.path, input.path]);
    // An icon font keeps its icons in the Private Use Area, so a font that is
    // mostly icons keeps all of them whatever the set says: one that also
    // maps a few letters would otherwise come out with the letters and no
    // icons. A text font's private-use characters (Inter has 745) are
    // alternates its OpenType features reach without them, and go.
    final int privateUse = face.codepoints.where(_privateUse).length;
    final bool icons = privateUse * 2 > face.codepoints.length;
    final List<int> keep = <int>[
      for (final int c in face.codepoints)
        if (characters.contains(c) || (icons && _privateUse(c))) c,
    ]..sort();
    process.stdin.write('${keep.map((int c) => 'optional:$c').join(' ')}\n');
    await process.stdin.close();
    final Future<void> drained =
        Future.wait(<Future<void>>[process.stdout.drain<void>(), process.stderr.drain<void>()]);
    final int code = await process.exitCode;
    await drained;
    if (code != 0 || !output.existsSync()) return null;
    final Uint8List result = output.readAsBytesSync();
    final DVFontFacts after = dvFontFacts(result);
    if (!after.codepoints.containsAll(keep)) return null;
    if ((face.weightAxis == null) != (after.weightAxis == null)) return null;
    if (result.length >= source.length) return null;
    return result;
  } on Object {
    return null;
  } finally {
    temp.deleteSync(recursive: true);
  }
}
