/// The brand a web build carries, so no Dartvel site ships Flutter's.
///
/// Flutter's web template is a project skeleton: its favicon and icons are
/// Flutter's logo, its manifest and page title are the package name, its
/// description is "A new Flutter project." and its colour is Flutter blue.
/// Every one of those reached production on Dartvel sites, because the build
/// generated the four manifest icons and nothing else: the tab icon stayed
/// Flutter's, and a project with no icon at all kept every template file.
///
/// This resolves one brand from `dartvel.pwa`, then `dartvel.seo`, then the
/// splash, and the build writes it everywhere the template had a placeholder.
/// A project with no icon gets a plain monogram of its own name rather than
/// someone else's logo, with a warning to set a real one.
library dartvel_cli.build.web_branding;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pwa_icons.dart';

/// The md5 of every icon Flutter's web template ships: favicon.png,
/// Icon-192, Icon-512 and the two maskable icons. A file with one of these
/// sums in a project's web/ folder is template output nobody replaced.
const List<String> dvFlutterTemplateIconMd5s = <String>[
  '5dcef449791fa27946b3d35ad8803796', // favicon.png
  'ac9a721a12bbc803b44f645561ecb1e1', // icons/Icon-192.png
  '96e752610906ba2a93c65f8abe1645f1', // icons/Icon-512.png
  'c457ef57daa1d16f64b27b786ec2ea3c', // icons/Icon-maskable-192.png
  '301a7604d45b3e739efc881eb04896ea', // icons/Icon-maskable-512.png
];

/// Whether [bytes] is one of Flutter's template icons.
bool dvIsFlutterTemplateIcon(List<int> bytes) =>
    dvFlutterTemplateIconMd5s.contains(md5.convert(bytes).toString());

/// Flutter's template colour, which no Dartvel output may carry.
const String _flutterBlue = '#0175C2';

/// What a web build names and colours itself with.
class DVWebBrand {
  const DVWebBrand({
    required this.name,
    required this.shortName,
    required this.description,
    required this.themeColor,
    required this.backgroundColor,
  });

  final String name;
  final String shortName;
  final String description;
  final String themeColor;
  final String backgroundColor;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _colour(Object? value) {
  final String? text = _text(value);
  if (text == null || text.toUpperCase() == _flutterBlue) return null;
  return text;
}

/// The package name made readable: `danieleffiong_dv` -> `Danieleffiong Dv`.
String _readable(String packageName) => packageName
    .split(RegExp(r'[_\-\s]+'))
    .where((String word) => word.isNotEmpty)
    .map((String word) => word[0].toUpperCase() + word.substring(1))
    .join(' ');

/// The brand [dartvel] (the `dartvel:` block of pubspec.yaml) declares, with
/// [packageName] as the last resort for the name.
DVWebBrand dvWebBrand(Map<Object?, Object?> dartvel, String packageName) {
  Map<Object?, Object?> section(String key) {
    final Object? value = dartvel[key];
    return value is Map ? value : const <Object?, Object?>{};
  }

  final Map<Object?, Object?> pwa = section('pwa');
  final Map<Object?, Object?> seo = section('seo');
  final Map<Object?, Object?> splash = section('splash');
  final String name = _text(pwa['name']) ?? _text(seo['siteName']) ?? _readable(packageName);
  return DVWebBrand(
    name: name,
    shortName: _text(pwa['shortName']) ?? name,
    description: _text(pwa['description']) ?? _text(seo['description']) ?? name,
    themeColor: _colour(pwa['themeColor']) ?? _colour(seo['accent']) ?? '#000000',
    backgroundColor: _colour(pwa['backgroundColor']) ?? _colour(splash['color']) ?? '#FFFFFF',
  );
}

/// Writes [brand] into a page made from Flutter's template: the title, the
/// description and the iOS app title where they still hold template text, and
/// icon links pointing at the files the build generates. Text the project
/// wrote itself is left as it is.
String dvBrandIndexHtml(String html, DVWebBrand brand, {String? packageName}) {
  String out = html;
  String attr(String value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
  String body(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  // A template title is the package name; anything else was written on purpose.
  final RegExp title = RegExp(r'<title>([^<]*)</title>');
  final RegExpMatch? current = title.firstMatch(out);
  if (current != null) {
    final String text = current.group(1)!.trim();
    final bool template = text.isEmpty || RegExp(r'^[a-z0-9_]+$').hasMatch(text) || (packageName != null && text == packageName);
    if (template) out = out.replaceFirst(title, '<title>${body(brand.name)}</title>');
  }
  out = out.replaceAll(
    RegExp(r'<meta name="description" content="A new Flutter project\.?"\s*/?>'),
    '<meta name="description" content="${attr(brand.description)}">',
  );
  out = out.replaceAllMapped(
    RegExp(r'(<meta name="apple-mobile-web-app-title" content=")([^"]*)(")'),
    (Match m) => RegExp(r'^[a-z0-9_]+$').hasMatch(m[2]!) || m[2]!.isEmpty ? '${m[1]}${attr(brand.name)}${m[3]}' : m[0]!,
  );
  out = out.replaceAll('<link rel="apple-touch-icon" href="icons/Icon-192.png">', '<link rel="apple-touch-icon" href="apple-touch-icon.png">');
  if (!RegExp(r'<link[^>]+rel="apple-touch-icon"').hasMatch(out)) {
    out = out.replaceFirst('</head>', '  <link rel="apple-touch-icon" href="apple-touch-icon.png">\n</head>');
  }
  if (!RegExp(r'<link[^>]+rel="(shortcut )?icon"').hasMatch(out)) {
    out = out.replaceFirst('</head>', '  <link rel="icon" type="image/png" href="favicon.png"/>\n</head>');
  }
  return out;
}

/// The browser-tab and home-screen icons, from the project's icon art:
/// favicon.png (32), apple-touch-icon.png (180), and the four manifest icons.
/// Returns the paths written, relative to [into].
List<String> dvGenerateWebIcons({
  required DVRgbaImage source,
  required Directory into,
  int background = 0xFFFFFFFF,
}) {
  into.createSync(recursive: true);
  final Directory scratch = Directory.systemTemp.createTempSync('dv-icon');
  try {
    final File art = File('${scratch.path}/art.png')..writeAsBytesSync(dvPngEncode(source));
    final List<String> written = dvGeneratePwaIcons(source: art, into: into, background: background);
    File('${into.path}/favicon.png').writeAsBytesSync(dvPngEncode(dvResizeRgba(source, 32, 32)));
    // iOS draws the touch icon on its own rounded tile and shows transparency
    // as black, so it is composited over the background.
    File('${into.path}/apple-touch-icon.png').writeAsBytesSync(dvPngEncode(_over(dvResizeRgba(source, 180, 180), background)));
    return <String>['favicon.png', 'apple-touch-icon.png', ...written];
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

DVRgbaImage _over(DVRgbaImage image, int background) {
  final int br = (background >> 16) & 0xFF, bg = (background >> 8) & 0xFF, bb = background & 0xFF;
  final DVRgbaImage out = DVRgbaImage(image.width, image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final List<int> p = image.get(x, y);
      final double a = p[3] / 255;
      out.set(x, y, r: (p[0] * a + br * (1 - a)).round(), g: (p[1] * a + bg * (1 - a)).round(), b: (p[2] * a + bb * (1 - a)).round());
    }
  }
  return out;
}

/// One or two initials from [name]'s words: `Daniel Effiong` -> `DE`.
String dvMonogramLetters(String name) {
  final List<String> words = name
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((String word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'D';
  return words.take(2).map((String word) => word[0].toUpperCase()).join();
}

/// A plain icon for a project that has none: its initials, drawn in white or
/// near-black (whichever reads on [accent]) on a square of [accent].
DVRgbaImage dvMonogramIcon(String name, {required int accent, int size = 512}) {
  final int ar = (accent >> 16) & 0xFF, ag = (accent >> 8) & 0xFF, ab = accent & 0xFF;
  final DVRgbaImage image = DVRgbaImage(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.set(x, y, r: ar, g: ag, b: ab);
    }
  }
  final double luminance = (0.2126 * ar + 0.7152 * ag + 0.0722 * ab) / 255;
  final int ink = luminance > 0.55 ? 0x14 : 0xFF;
  final String letters = dvMonogramLetters(name);
  // 5x7 glyphs with one column between them, filling about 60% of the width.
  final int columns = letters.length * 5 + (letters.length - 1);
  final int cell = (size * 0.6 / columns).floor().clamp(1, size);
  final int glyphHeight = cell * 7;
  final int left = (size - columns * cell) ~/ 2;
  final int top = (size - glyphHeight) ~/ 2;
  for (var i = 0; i < letters.length; i++) {
    final List<String> rows = _glyphs[letters[i]] ?? _glyphs['?']!;
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 5; col++) {
        if (rows[row][col] != '#') continue;
        final int x0 = left + (i * 6 + col) * cell;
        final int y0 = top + row * cell;
        for (var y = y0; y < y0 + cell; y++) {
          for (var x = x0; x < x0 + cell; x++) {
            image.set(x, y, r: ink, g: ink, b: ink);
          }
        }
      }
    }
  }
  return image;
}

/// Writes a monogram PNG for [name] to [file] and returns it.
File dvWriteMonogram(File file, String name, {required int accent}) {
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(Uint8List.fromList(dvPngEncode(dvMonogramIcon(name, accent: accent))));
  return file;
}

const Map<String, List<String>> _glyphs = <String, List<String>>{
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'C': ['.####', '#....', '#....', '#....', '#....', '#....', '.####'],
  'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  'G': ['.####', '#....', '#....', '#.###', '#...#', '#...#', '.###.'],
  'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'I': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
  'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
  'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
  '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
};

/// Replaces Flutter template icons committed in a project's web/ folder with
/// the generated ones in [built] (the web build directory), so a stale
/// template file in source cannot be served by a host that reads web/.
List<String> dvTemplateIconsIn(Directory web) {
  if (!web.existsSync()) return const <String>[];
  final List<String> found = <String>[];
  for (final String rel in <String>['favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png', 'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png']) {
    final File file = File('${web.path}/$rel');
    if (file.existsSync() && dvIsFlutterTemplateIcon(file.readAsBytesSync())) found.add(rel);
  }
  return found;
}
