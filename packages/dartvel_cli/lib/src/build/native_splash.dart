/// The splash every platform shows before a Dartvel application's first
/// frame.
///
/// Every target shows something between the process starting and the first
/// frame, and the files `flutter create` writes make every one of them white:
/// Android's launch theme draws `@android:color/white`, iOS's launch
/// storyboard is white, macOS's view is black, and the web is a blank page for
/// as long as main.dart.js takes to arrive -- which on a phone is seconds. An
/// application with a dark page opens on a white flash everywhere, and one
/// with a light page opens on a black window on a Mac.
///
/// Configured under `dartvel.splash`, and useful with nothing configured: the
/// colour falls back to `dartvel.pwa.backgroundColor`, which is what the
/// application already says its page is, and the image to the project's icon.
///
/// It writes only what it owns. A platform file is replaced when it is still
/// Flutter's template or carries Dartvel's marker; one somebody designed by
/// hand is left alone unless `dartvel.splash.overwrite` says otherwise,
/// because replacing a launch screen without being asked would be a worse bug
/// than the white one.
library dartvel_cli.build.native_splash;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'pwa_icons.dart';

/// The light colour when a project declares none anywhere.
const String dvSplashDefaultColor = '#FFFFFF';

/// The dark colour when a project declares none anywhere: Material's dark
/// surface, so a phone in dark mode does not open on a white page.
const String dvSplashDefaultDarkColor = '#121212';

/// What a project's splash is.
class DVSplash {
  DVSplash({
    this.enabled = true,
    required this.color,
    required this.darkColor,
    this.image,
    this.darkImage,
    this.android12Image,
    this.imageWidth,
    this.imageIsIcon = false,
    this.overwrite = false,
    this.problems = const <String>[],
  });

  /// From the `dartvel:` section of a pubspec, with files resolved against
  /// [root].
  ///
  /// The light colour is `splash.color`, then `pwa.backgroundColor`, then
  /// [dvSplashDefaultColor]. The dark one is `splash.darkColor`, then the
  /// light one if the project declared one, then [dvSplashDefaultDarkColor]:
  /// a declared colour is a decision, and swapping it for a default dark in
  /// dark mode would contradict it.
  factory DVSplash.fromConfig(Map<Object?, Object?> dartvel,
      {required String root}) {
    final Object? rawSplash = dartvel['splash'];
    final Map<Object?, Object?> splash =
        rawSplash is Map ? rawSplash : const <Object?, Object?>{};
    final Object? rawPwa = dartvel['pwa'];
    final Map<Object?, Object?> pwa =
        rawPwa is Map ? rawPwa : const <Object?, Object?>{};
    final List<String> problems = <String>[];

    String? colour(Object? value, String key) {
      if (value == null) return null;
      final String? hex = dvSplashHex('$value');
      if (hex == null) {
        problems.add('dartvel.$key is "$value", which is not a #RRGGBB or '
            '#RGB colour, so it was not used.');
      }
      return hex;
    }

    File? file(Object? value, String key) {
      if (value is! String || value.trim().isEmpty) return null;
      final File found = File(p.join(root, value.trim()));
      if (!found.existsSync()) {
        problems.add('dartvel.$key names ${value.trim()}, which does not '
            'exist, so the splash has no image.');
        return null;
      }
      return found;
    }

    final String? light =
        colour(splash['color'], 'splash.color') ??
            colour(pwa['backgroundColor'], 'pwa.backgroundColor');
    final String? dark = colour(splash['darkColor'], 'splash.darkColor');

    File? image = file(splash['image'], 'splash.image');
    bool isIcon = false;
    if (splash['image'] == null) {
      try {
        image = dvPwaIconSource(root, pwa);
        isIcon = image != null;
      } on DVPngError {
        // A PWA icon that is named and missing is the icon step's error to
        // report, and it does; the splash simply goes without.
      }
    }

    final Object? width = splash['imageWidth'];
    return DVSplash(
      enabled: splash['enabled'] != false,
      color: light ?? dvSplashDefaultColor,
      darkColor: dark ?? light ?? dvSplashDefaultDarkColor,
      image: image,
      darkImage: file(splash['darkImage'], 'splash.darkImage'),
      android12Image: file(splash['android12Image'], 'splash.android12Image'),
      imageWidth: width is num ? width.toDouble() : null,
      imageIsIcon: isIcon,
      overwrite: splash['overwrite'] == true,
      problems: problems,
    );
  }

  /// From the project's pubspec.yaml.
  ///
  /// A pubspec that will not parse gets the defaults: that is the build's own
  /// failure to report, and a splash is not the place to report it.
  static DVSplash of(String root) {
    Map<Object?, Object?> dartvel = const <Object?, Object?>{};
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      try {
        final Object? document = loadYaml(pubspec.readAsStringSync());
        final Object? section = document is Map ? document['dartvel'] : null;
        if (section is Map) dartvel = section;
      } on Object {
        // Defaults, as above.
      }
    }
    return DVSplash.fromConfig(dartvel, root: root);
  }

  final bool enabled;

  /// `#RRGGBB`, upper case.
  final String color;
  final String darkColor;

  final File? image;
  final File? darkImage;

  /// The icon Android 12 and later draw in the middle of their own splash.
  /// Without one they draw the launcher icon, which is usually right.
  final File? android12Image;

  /// How wide the image is drawn, in logical pixels. Null reads the image as
  /// 4x, the way an xxxhdpi drawable is read, or draws the icon at 96.
  final double? imageWidth;

  /// Whether [image] is the project's icon standing in for one nobody named.
  final bool imageIsIcon;

  /// Replace platform files that are neither Flutter's template nor
  /// Dartvel's.
  final bool overwrite;

  /// What was declared and could not be used.
  final List<String> problems;
}

/// What a writer did.
class DVSplashResult {
  /// Files written, relative to the project root.
  final List<String> written = <String>[];

  /// What was left alone, and why, in a sentence each.
  final List<String> skipped = <String>[];
}

/// [value] as `#RRGGBB`, or null when it is not a colour.
String? dvSplashHex(String value) {
  final Match? m =
      RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(value.trim());
  if (m == null) return null;
  String hex = m.group(1)!;
  if (hex.length == 3) hex = hex.split('').map((String c) => '$c$c').join();
  return '#${hex.toUpperCase()}';
}

(int, int, int) _rgb(String hex) {
  final int v = int.parse(hex.substring(1), radix: 16);
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

/// The width the image is drawn at, in logical pixels.
int dvSplashLogicalWidth(DVSplash splash, DVRgbaImage source) {
  final double width =
      splash.imageWidth ?? (splash.imageIsIcon ? 96 : source.width / 4);
  return math.max(1, width.round());
}

int _heightFor(int width, DVRgbaImage source) =>
    math.max(1, (width * source.height / source.width).round());

/// [source] at [width] pixels wide, never wider than it is.
DVRgbaImage _scaled(DVRgbaImage source, int width) {
  final int w = math.min(width, source.width);
  return dvResizeRgba(source, w, _heightFor(w, source));
}

// ---------------------------------------------------------------------------
// Writing only what changed

bool _put(File file, String contents) {
  if (file.existsSync() && file.readAsStringSync() == contents) return false;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return true;
}

bool _putBytes(File file, Uint8List bytes) {
  if (file.existsSync()) {
    final Uint8List have = file.readAsBytesSync();
    if (have.length == bytes.length) {
      var same = true;
      for (var i = 0; i < have.length; i++) {
        if (have[i] != bytes[i]) {
          same = false;
          break;
        }
      }
      if (same) return false;
    }
  }
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return true;
}

void _record(DVSplashResult result, String root, File file, bool changed) {
  if (changed) result.written.add(p.relative(file.path, from: root));
}

DVRgbaImage? _decode(File file, DVSplashResult result) {
  try {
    return dvPngDecode(file.readAsBytesSync());
  } on DVPngError catch (error) {
    result.skipped.add('${file.path} could not be read as a splash image: '
        '${error.message}');
    return null;
  }
}

/// Compared with whitespace removed, so a template re-indented by an editor
/// still counts as the template.
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), '');

const String _marker = 'dartvel:splash';

String _ownedBy(String what) =>
    '$what is not Flutter\'s template and was not written by Dartvel, so it '
    'was left alone. Set dartvel.splash.overwrite: true to replace it.';

// ---------------------------------------------------------------------------
// Web

const String _headOpen = '<!-- dartvel:splash -->';
const String _headClose = '<!-- /dartvel:splash -->';
const String _bodyOpen = '<!-- dartvel:splash-body -->';
const String _bodyClose = '<!-- /dartvel:splash-body -->';

/// [html] without a splash, as it was before [dvWebSplashApply].
String dvWebSplashRemove(String html) => html
    .replaceAll(
        RegExp('${RegExp.escape(_headOpen)}.*?${RegExp.escape(_headClose)}\n',
            dotAll: true),
        '')
    .replaceAll(
        RegExp('\n${RegExp.escape(_bodyOpen)}.*?${RegExp.escape(_bodyClose)}',
            dotAll: true),
        '');

/// [html] with the splash in it.
///
/// The colour is a stylesheet in the head, so it paints in the first frame
/// the browser draws with nothing fetched. The element goes first in the
/// body, before anything else, because the engine appends `<flutter-view>`
/// to the end of the body: positioned after the splash, the application
/// covers it the moment it paints. The first-frame listener then removes it,
/// but nothing depends on that script being allowed to run -- a
/// Content-Security-Policy without 'unsafe-inline' leaves the splash
/// underneath an application that has painted over it.
///
/// Hidden without scripting. A prerendered page's content is a noscript
/// block, and with scripting off the first frame never comes: a splash left
/// in place would cover the only content that page has.
String dvWebSplashApply(
  String html,
  DVSplash splash, {
  String? imageUrl,
  String? darkImageUrl,
  int? imageWidth,
}) {
  final String clean = dvWebSplashRemove(html);
  final int head = clean.indexOf('</head>');
  final Match? body = RegExp(r'<body[^>]*>').firstMatch(clean);
  // Not a page this can put a splash into. Unchanged beats inventing
  // structure around somebody's template.
  if (head < 0 || body == null || body.start < head) return clean;

  final StringBuffer style = StringBuffer()
    ..write('#dartvel-splash{position:fixed;top:0;right:0;bottom:0;left:0;'
        'display:flex;align-items:center;justify-content:center;'
        'background:${splash.color}}');
  if (imageUrl != null) {
    style.write('#dartvel-splash img{width:${imageWidth ?? 96}px;'
        'max-width:60vw;height:auto}');
  }
  if (splash.darkColor != splash.color) {
    style.write('@media (prefers-color-scheme:dark){'
        '#dartvel-splash{background:${splash.darkColor}}}');
  }

  final String headBlock = '$_headOpen\n'
      '<style id="dartvel-splash-style">$style</style>\n'
      '<noscript><style>#dartvel-splash{display:none}</style></noscript>\n'
      '$_headClose\n';

  final StringBuffer picture = StringBuffer();
  if (imageUrl != null) {
    picture.write('<picture>');
    if (darkImageUrl != null) {
      picture.write('<source srcset="$darkImageUrl" '
          'media="(prefers-color-scheme: dark)">');
    }
    picture.write('<img src="$imageUrl" alt=""></picture>');
  }
  final String bodyBlock = '\n$_bodyOpen\n'
      '<div id="dartvel-splash" aria-hidden="true">$picture</div>\n'
      '<script>addEventListener("flutter-first-frame",function(){'
      'var s=document.getElementById("dartvel-splash");if(s)s.remove();'
      'var t=document.getElementById("dartvel-splash-style");if(t)t.remove()'
      '},{once:true})</script>\n'
      '$_bodyClose';

  return '${clean.substring(0, head)}$headBlock'
      '${clean.substring(head, body.end)}$bodyBlock'
      '${clean.substring(body.end)}';
}

/// The splash into a built site's `index.html`, which every prerendered page
/// is then made from, with its images beside it.
DVSplashResult dvWriteWebSplash(Directory web, DVSplash splash) {
  final DVSplashResult result = DVSplashResult();
  final File index = File(p.join(web.path, 'index.html'));
  if (!splash.enabled || !index.existsSync()) return result;
  final String root = p.dirname(p.dirname(web.path));

  String? imageUrl;
  String? darkUrl;
  int? width;
  final DVRgbaImage? source =
      splash.image == null ? null : _decode(splash.image!, result);
  if (source != null) {
    width = dvSplashLogicalWidth(splash, source);
    // 3x: the densest screens a browser reports, and the file stays small.
    final File out = File(p.join(web.path, 'dartvel-splash.png'));
    _record(result, root, out,
        _putBytes(out, dvPngEncode(_scaled(source, width * 3))));
    imageUrl = 'dartvel-splash.png';

    final DVRgbaImage? dark =
        splash.darkImage == null ? null : _decode(splash.darkImage!, result);
    if (dark != null) {
      final File darkOut = File(p.join(web.path, 'dartvel-splash-dark.png'));
      _record(result, root, darkOut,
          _putBytes(darkOut, dvPngEncode(_scaled(dark, width * 3))));
      darkUrl = 'dartvel-splash-dark.png';
    }
  }

  final String before = index.readAsStringSync();
  final String after = dvWebSplashApply(before, splash,
      imageUrl: imageUrl, darkImageUrl: darkUrl, imageWidth: width);
  _record(result, root, index, _put(index, after));
  return result;
}

// ---------------------------------------------------------------------------
// Android

const List<(String, double)> _densities = <(String, double)>[
  ('mdpi', 1),
  ('hdpi', 1.5),
  ('xhdpi', 2),
  ('xxhdpi', 3),
  ('xxxhdpi', 4),
];

const String _androidImage = 'dartvel_splash_image';
const String _android12Icon = 'dartvel_splash_android12';

// Flutter's two launch backgrounds: API 21+ uses the theme colour, the older
// one plain white. Either, untouched, is the template.
const List<String> _androidTemplates = <String>[
  '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!-- Modify this file to customize your launch splash screen -->\n'
      '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <item android:drawable="@android:color/white" />\n'
      '\n'
      '    <!-- You can insert your own image assets here -->\n'
      '    <!-- <item>\n'
      '        <bitmap\n'
      '            android:gravity="center"\n'
      '            android:src="@mipmap/launch_image" />\n'
      '    </item> -->\n'
      '</layer-list>\n',
  '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!-- Modify this file to customize your launch splash screen -->\n'
      '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <item android:drawable="?android:colorBackground" />\n'
      '\n'
      '    <!-- You can insert your own image assets here -->\n'
      '    <!-- <item>\n'
      '        <bitmap\n'
      '            android:gravity="center"\n'
      '            android:src="@mipmap/launch_image" />\n'
      '    </item> -->\n'
      '</layer-list>\n',
];

const String _androidHeader = '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- $_marker: written by dartvel build from dartvel.splash in\n'
    '     pubspec.yaml, and rewritten by every build. To design this file by\n'
    '     hand, delete this comment and Dartvel will leave it alone. -->\n';

String _androidColours(String colour) => '$_androidHeader'
    '<resources>\n'
    '    <color name="dartvel_splash_background">$colour</color>\n'
    '</resources>\n';

String _androidLaunchBackground({required bool image}) => '$_androidHeader'
    '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <item android:drawable="@color/dartvel_splash_background" />\n'
    '${image ? '    <item>\n'
        '        <bitmap\n'
        '            android:gravity="center"\n'
        '            android:src="@drawable/$_androidImage" />\n'
        '    </item>\n' : ''}'
    '</layer-list>\n';

String _android12Styles({required String parent, required bool icon}) =>
    '$_androidHeader'
    '<resources>\n'
    '    <!-- From API 31 the system draws its own splash and ignores a\n'
    '         layer-list window background, so it is told the colour here. -->\n'
    '    <style name="LaunchTheme" parent="$parent">\n'
    '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
    '        <item name="android:windowSplashScreenBackground">@color/dartvel_splash_background</item>\n'
    '${icon ? '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/$_android12Icon</item>\n' : ''}'
    '    </style>\n'
    '</resources>\n';

/// Whether the base `LaunchTheme` is still only Flutter's: one item, the
/// window background. An API 31 override replaces the whole style on those
/// devices, so one the project added items to must not be shadowed -- and
/// one that does not exist at all must not be created only for API 31,
/// which would crash every older phone looking for it.
bool _plainLaunchTheme(Directory res) {
  final File styles = File(p.join(res.path, 'values', 'styles.xml'));
  if (!styles.existsSync()) return false;
  final Match? theme = RegExp(
          r'<style\s+name="LaunchTheme"[^>]*>(.*?)</style>',
          dotAll: true)
      .firstMatch(styles.readAsStringSync());
  if (theme == null) return false;
  final Iterable<Match> items =
      RegExp(r'<item\s+name="([^"]+)"').allMatches(theme.group(1)!);
  return items.length == 1 &&
      items.single.group(1) == 'android:windowBackground';
}

void _deleteNamed(Directory res, String name, DVSplashResult result,
    String root) {
  for (final FileSystemEntity dir in res.listSync()) {
    if (dir is! Directory || !p.basename(dir.path).startsWith('drawable')) {
      continue;
    }
    final File stale = File(p.join(dir.path, '$name.png'));
    if (stale.existsSync()) {
      stale.deleteSync();
      result.written.add(p.relative(stale.path, from: root));
    }
  }
}

/// The launch theme, its Android 12 counterpart and their images.
DVSplashResult dvWriteAndroidSplash(String root, DVSplash splash) {
  final DVSplashResult result = DVSplashResult();
  final Directory res =
      Directory(p.join(root, 'android', 'app', 'src', 'main', 'res'));
  if (!splash.enabled || !res.existsSync()) return result;

  // Named, so the drawable says which and the resource system picks: the
  // values-night one in dark mode.
  for (final (String dir, String colour) in <(String, String)>[
    ('values', splash.color),
    ('values-night', splash.darkColor),
  ]) {
    final File file = File(p.join(res.path, dir, 'dartvel_splash.xml'));
    _record(result, root, file, _put(file, _androidColours(colour)));
  }

  bool image = false;
  final DVRgbaImage? source =
      splash.image == null ? null : _decode(splash.image!, result);
  if (source != null) {
    final int width = dvSplashLogicalWidth(splash, source);
    final DVRgbaImage? dark =
        splash.darkImage == null ? null : _decode(splash.darkImage!, result);
    for (final (String bucket, double scale) in _densities) {
      final int pixels = (width * scale).round();
      final File out =
          File(p.join(res.path, 'drawable-$bucket', '$_androidImage.png'));
      _record(result, root, out,
          _putBytes(out, dvPngEncode(_scaled(source, pixels))));
      if (dark != null) {
        final File darkOut = File(
            p.join(res.path, 'drawable-night-$bucket', '$_androidImage.png'));
        _record(result, root, darkOut,
            _putBytes(darkOut, dvPngEncode(_scaled(dark, pixels))));
      }
    }
    image = true;
  } else {
    _deleteNamed(res, _androidImage, result, root);
  }

  bool icon = false;
  final DVRgbaImage? a12 = splash.android12Image == null
      ? null
      : _decode(splash.android12Image!, result);
  if (a12 != null) {
    for (final (String bucket, double scale) in _densities) {
      final File out =
          File(p.join(res.path, 'drawable-$bucket', '$_android12Icon.png'));
      _record(result, root, out,
          _putBytes(out, dvPngEncode(_android12Canvas(a12, scale))));
    }
    icon = true;
  } else {
    _deleteNamed(res, _android12Icon, result, root);
  }

  final Set<String> templates = _androidTemplates.map(_squash).toSet();
  for (final String dir in <String>['drawable', 'drawable-v21']) {
    final File file = File(p.join(res.path, dir, 'launch_background.xml'));
    // Not created: a project without one has a launch theme of its own
    // shape, and the base drawable is enough where the v21 one is absent.
    if (!file.existsSync()) continue;
    final String have = file.readAsStringSync();
    if (!templates.contains(_squash(have)) &&
        !have.contains(_marker) &&
        !splash.overwrite) {
      result.skipped.add(_ownedBy('$dir/launch_background.xml'));
      continue;
    }
    _record(result, root, file,
        _put(file, _androidLaunchBackground(image: image)));
  }

  if (!_plainLaunchTheme(res)) {
    result.skipped.add('values/styles.xml has a LaunchTheme with more in it '
        'than Flutter\'s, or none, so no Android 12 splash was written: an '
        'API 31 LaunchTheme would replace that one on Android 12 and later.');
    return result;
  }
  for (final (String dir, String parent) in <(String, String)>[
    ('values-v31', '@android:style/Theme.Light.NoTitleBar'),
    ('values-night-v31', '@android:style/Theme.Black.NoTitleBar'),
  ]) {
    final File file = File(p.join(res.path, dir, 'styles.xml'));
    if (file.existsSync() &&
        !file.readAsStringSync().contains(_marker) &&
        !splash.overwrite) {
      result.skipped.add(_ownedBy('$dir/styles.xml'));
      continue;
    }
    _record(result, root, file,
        _put(file, _android12Styles(parent: parent, icon: icon)));
  }
  return result;
}

/// Android 12's icon: a 288dp canvas, transparent, with the artwork inside
/// the middle 192dp -- the circle the system crops the icon to.
DVRgbaImage _android12Canvas(DVRgbaImage art, double scale) {
  final int canvas = (288 * scale).round();
  final int inner = (192 * scale).round();
  final double fit = math.min(inner / art.width, inner / art.height);
  final int w = math.max(1, (art.width * fit).round());
  final int h = math.max(1, (art.height * fit).round());
  final DVRgbaImage scaled = dvResizeRgba(art, w, h);
  final DVRgbaImage out = DVRgbaImage(canvas, canvas);
  final int ox = (canvas - w) ~/ 2;
  final int oy = (canvas - h) ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final List<int> px = scaled.get(x, y);
      out.set(x + ox, y + oy, r: px[0], g: px[1], b: px[2], a: px[3]);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// iOS

const String _iosColour = 'DartvelSplashBackground';

String _iosComponents(String hex) {
  final (int r, int g, int b) = _rgb(hex);
  String c(int v) => '0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  return jsonEncode(<String, Object?>{
    'color-space': 'srgb',
    'components': <String, String>{
      'alpha': '1.000',
      'blue': c(b),
      'green': c(g),
      'red': c(r),
    },
  });
}

String _iosColourSet(DVSplash splash) {
  const JsonEncoder pretty = JsonEncoder.withIndent('  ');
  return '${pretty.convert(<String, Object?>{
        'colors': <Object?>[
          <String, Object?>{
            'color': jsonDecode(_iosComponents(splash.color)),
            'idiom': 'universal',
          },
          <String, Object?>{
            'appearances': <Object?>[
              <String, String>{'appearance': 'luminosity', 'value': 'dark'},
            ],
            'color': jsonDecode(_iosComponents(splash.darkColor)),
            'idiom': 'universal',
          },
        ],
        'info': <String, Object?>{'author': 'dartvel', 'version': 1},
      })}\n';
}

String _iosImageSet({required bool dark}) {
  const JsonEncoder pretty = JsonEncoder.withIndent('  ');
  final List<Object?> images = <Object?>[];
  for (final String scale in <String>['1x', '2x', '3x']) {
    final String suffix = scale == '1x' ? '' : '@$scale';
    images.add(<String, Object?>{
      'idiom': 'universal',
      'filename': 'LaunchImage$suffix.png',
      'scale': scale,
    });
    if (dark) {
      images.add(<String, Object?>{
        'appearances': <Object?>[
          <String, String>{'appearance': 'luminosity', 'value': 'dark'},
        ],
        'idiom': 'universal',
        'filename': 'LaunchImageDark$suffix.png',
        'scale': scale,
      });
    }
  }
  return '${pretty.convert(<String, Object?>{
        'images': images,
        'info': <String, Object?>{'version': 1, 'author': 'dartvel'},
      })}\n';
}

/// Whether the LaunchImage set is still Flutter's: Xcode's author line and
/// nothing in it but the 1x1 transparent placeholders.
bool _placeholderImageSet(Directory set) {
  final File contents = File(p.join(set.path, 'Contents.json'));
  if (contents.existsSync() &&
      !contents.readAsStringSync().contains('"xcode"')) {
    return false;
  }
  for (final FileSystemEntity entity in set.listSync()) {
    if (entity is! File || !entity.path.endsWith('.png')) continue;
    try {
      final DVRgbaImage image = dvPngDecode(entity.readAsBytesSync());
      if (image.width > 1 || image.height > 1) return false;
    } on DVPngError {
      return false;
    }
  }
  return true;
}

String _ib(int v) => (v / 255).toStringAsFixed(3);

/// Flutter's launch storyboard, with the colour named rather than white.
///
/// A named colour from the asset catalog, because that is how a launch
/// screen follows dark mode: the storyboard names it and the catalog carries
/// both appearances.
String _iosStoryboard(DVSplash splash, String imageElement) {
  final (int r, int g, int b) = _rgb(splash.color);
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!-- $_marker: written by dartvel build from dartvel.splash in pubspec.yaml,
     and rewritten by every build. To design this file by hand, delete this
     comment and Dartvel will leave it alone. -->
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" systemVersion="16G29" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/>
        <capability name="Named colors" minToolsVersion="9.0"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <layoutGuides>
                        <viewControllerLayoutGuide type="top" id="Ydg-fD-yQy"/>
                        <viewControllerLayoutGuide type="bottom" id="xbc-2k-c8Z"/>
                    </layoutGuides>
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                            </imageView>
                        </subviews>
                        <color key="backgroundColor" name="$_iosColour"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="1a2-6s-vTC"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="4X2-HB-R7a"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        $imageElement
        <namedColor name="$_iosColour">
            <color red="${_ib(r)}" green="${_ib(g)}" blue="${_ib(b)}" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
        </namedColor>
    </resources>
</document>
''';
}

final RegExp _iosImageElement = RegExp(r'<image name="LaunchImage"[^>]*/>');

/// Flutter's storyboard as `flutter create` writes it, minus the image
/// element, whose size is the one line that legitimately varies.
final String _iosTemplate = _squash('''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" systemVersion="16G29" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <layoutGuides>
                        <viewControllerLayoutGuide type="top" id="Ydg-fD-yQy"/>
                        <viewControllerLayoutGuide type="bottom" id="xbc-2k-c8Z"/>
                    </layoutGuides>
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                            </imageView>
                        </subviews>
                        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="1a2-6s-vTC"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="4X2-HB-R7a"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
    </resources>
</document>
''');

/// The launch storyboard, the colour it names, and the LaunchImage set.
DVSplashResult dvWriteIosSplash(String root, DVSplash splash) {
  final DVSplashResult result = DVSplashResult();
  final Directory runner = Directory(p.join(root, 'ios', 'Runner'));
  if (!splash.enabled || !runner.existsSync()) return result;
  final Directory assets = Directory(p.join(runner.path, 'Assets.xcassets'));

  if (assets.existsSync()) {
    final File colourSet = File(
        p.join(assets.path, '$_iosColour.colorset', 'Contents.json'));
    _record(result, root, colourSet, _put(colourSet, _iosColourSet(splash)));
  }

  String? imageElement;
  final Directory set =
      Directory(p.join(assets.path, 'LaunchImage.imageset'));
  final DVRgbaImage? source =
      splash.image == null ? null : _decode(splash.image!, result);
  if (source != null && assets.existsSync()) {
    final File contents = File(p.join(set.path, 'Contents.json'));
    final bool ours = !set.existsSync() ||
        (contents.existsSync() &&
            contents.readAsStringSync().contains('"dartvel"')) ||
        _placeholderImageSet(set);
    if (!ours && !splash.overwrite) {
      result.skipped.add(_ownedBy('LaunchImage.imageset'));
    } else {
      final int width = dvSplashLogicalWidth(splash, source);
      final DVRgbaImage? dark = splash.darkImage == null
          ? null
          : _decode(splash.darkImage!, result);
      for (final int scale in <int>[1, 2, 3]) {
        final String suffix = scale == 1 ? '' : '@${scale}x';
        final File out = File(p.join(set.path, 'LaunchImage$suffix.png'));
        _record(result, root, out,
            _putBytes(out, dvPngEncode(_scaled(source, width * scale))));
        if (dark != null) {
          final File darkOut =
              File(p.join(set.path, 'LaunchImageDark$suffix.png'));
          _record(result, root, darkOut,
              _putBytes(darkOut, dvPngEncode(_scaled(dark, width * scale))));
        }
      }
      _record(result, root, contents,
          _put(contents, _iosImageSet(dark: dark != null)));
      imageElement = '<image name="LaunchImage" width="$width" '
          'height="${_heightFor(width, source)}"/>';
    }
  }

  final File storyboard =
      File(p.join(runner.path, 'Base.lproj', 'LaunchScreen.storyboard'));
  if (!storyboard.existsSync()) return result;
  final String have = storyboard.readAsStringSync();
  final bool template =
      _squash(have.replaceAll(_iosImageElement, '')) == _iosTemplate;
  if (!template && !have.contains(_marker) && !splash.overwrite) {
    result.skipped.add(_ownedBy('LaunchScreen.storyboard'));
    return result;
  }
  imageElement ??= _iosImageElement.firstMatch(have)?.group(0) ??
      '<image name="LaunchImage" width="1" height="1"/>';
  _record(result, root, storyboard,
      _put(storyboard, _iosStoryboard(splash, imageElement)));
  return result;
}

// ---------------------------------------------------------------------------
// Desktop

String _nsColor(String hex) {
  final (int r, int g, int b) = _rgb(hex);
  return 'NSColor(srgbRed: ${_ib(r)}, green: ${_ib(g)}, blue: ${_ib(b)}, '
      'alpha: 1)';
}

/// The macOS view's colour until its first frame.
///
/// The window is visible at launch, and FlutterView is black until the
/// engine draws -- so a light application opens on a black window. One line
/// after the view controller is made, marked so the next build replaces it.
DVSplashResult dvWriteMacosSplash(String root, DVSplash splash) {
  final DVSplashResult result = DVSplashResult();
  final File file =
      File(p.join(root, 'macos', 'Runner', 'MainFlutterWindow.swift'));
  if (!splash.enabled || !file.existsSync()) return result;

  final String have = file.readAsStringSync();
  final String clean = have.replaceAll(
      RegExp('^[^\\n]*// $_marker\\n', multiLine: true), '');
  final Match? anchor = RegExp(
          r'^([ \t]*)let flutterViewController = FlutterViewController\(\)[ \t]*\n',
          multiLine: true)
      .firstMatch(clean);
  if (anchor == null) {
    result.skipped.add('MainFlutterWindow.swift has no '
        '`let flutterViewController = FlutterViewController()` line, so its '
        'splash colour was not set. Set flutterViewController.backgroundColor '
        'there yourself.');
    return result;
  }
  final String colour = splash.darkColor == splash.color
      ? _nsColor(splash.color)
      : 'NSColor(name: nil) { \$0.bestMatch(from: [.darkAqua, .aqua]) == '
          '.darkAqua ? ${_nsColor(splash.darkColor)} : '
          '${_nsColor(splash.color)} }';
  final String line = '${anchor.group(1)}flutterViewController.backgroundColor'
      ' = $colour // $_marker\n';
  final String after =
      '${clean.substring(0, anchor.end)}$line${clean.substring(anchor.end)}';
  _record(result, root, file, _put(file, after));
  return result;
}

/// The Linux view's background.
///
/// The GTK runner shows its window on the first frame, so this is not a
/// blank window being painted; it is the colour behind the view while it
/// resizes, which Flutter's template sets to black. Light only: GTK has no
/// dependable way to read the desktop's dark preference from the runner.
DVSplashResult dvWriteLinuxSplash(String root, DVSplash splash) {
  final DVSplashResult result = DVSplashResult();
  final File file = File(p.join(root, 'linux', 'runner', 'my_application.cc'));
  if (!splash.enabled || !file.existsSync()) return result;

  final String have = file.readAsStringSync();
  final RegExp template = RegExp(
      r'gdk_rgba_parse\(&background_color, "#000000"\);[ \t]*$',
      multiLine: true);
  final RegExp marked = RegExp(
      'gdk_rgba_parse\\(&background_color, "[^"]*"\\);[ \\t]*// $_marker[ \\t]*\$',
      multiLine: true);
  final RegExp any = RegExp(
      r'gdk_rgba_parse\(&background_color, "[^"]*"\);[^\n]*$',
      multiLine: true);
  final RegExp? target = marked.hasMatch(have)
      ? marked
      : template.hasMatch(have)
          ? template
          : splash.overwrite && any.hasMatch(have)
              ? any
              : null;
  if (target == null) {
    if (any.hasMatch(have)) {
      result.skipped.add(_ownedBy('The background colour in my_application.cc'));
    }
    return result;
  }
  final String after = have.replaceFirst(target,
      'gdk_rgba_parse(&background_color, "${splash.color}");  // $_marker');
  _record(result, root, file, _put(file, after));
  return result;
}

/// The splash for [platform], before its build.
DVSplashResult dvWriteNativeSplash(
    String root, String platform, DVSplash splash) {
  switch (platform) {
    case 'android':
    case 'fireos':
      return dvWriteAndroidSplash(root, splash);
    case 'ios':
      return dvWriteIosSplash(root, splash);
    case 'macos':
      return dvWriteMacosSplash(root, splash);
    case 'linux':
      return dvWriteLinuxSplash(root, splash);
    case 'windows':
      return DVSplashResult()
        ..skipped.add('Windows needs no splash: its runner shows the window '
            'only once Flutter has drawn the first frame, so there is no '
            'blank window to paint.');
  }
  return DVSplashResult();
}
