/// The name and icon a launcher shows, from `dartvel.pwa`, on every platform
/// `flutter build` targets.
///
/// `flutter create` labels the application with its package name
/// (`eating_today`) and gives it the Flutter logo, and nothing in a Dartvel
/// project changed either: the name and icon an application declares for the
/// web never reached the phone or the desktop. An application now says them
/// once, under `dartvel.pwa`, and every build writes them where the platform
/// reads them: Android's manifest and mipmaps, iOS's and macOS's Info.plist
/// and app icon set, the Windows window title, version resource and
/// `app_icon.ico`, and the Linux window title and desktop entry.
///
/// `shortName` is the launcher label when there is one, because a launcher
/// cuts a long name at about twelve characters; otherwise `name`. The icon is
/// the PWA's source image (`dartvel.pwa.icon`, then `assets/icon.png`, then
/// `web/icon.png`), resized for each launcher density.
///
/// With neither configured nothing is written, so a project that has not
/// said keeps exactly what it had.
library dartvel_cli.build.launcher_identity;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'pwa_icons.dart';

/// Launcher icon edge in pixels for each Android density bucket.
const Map<String, int> dvAndroidLauncherSizes = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Writes the configured launcher label and icon into the project's Android
/// folder, and returns the files it changed.
List<String> dvWriteAndroidLauncher(String root) {
  final Directory main = Directory(p.join(root, 'android', 'app', 'src', 'main'));
  if (!main.existsSync()) return const <String>[];
  final Map<Object?, Object?> pwa = _pwaSettings(root);
  final List<String> changed = <String>[];

  final String? label = _text(pwa['shortName']) ?? _text(pwa['name']);
  final File manifest = File(p.join(main.path, 'AndroidManifest.xml'));
  if (label != null && manifest.existsSync()) {
    final String before = manifest.readAsStringSync();
    final String after = dvAndroidManifestWithLabel(before, label);
    if (after != before) {
      manifest.writeAsStringSync(after);
      changed.add(p.relative(manifest.path, from: root));
    }
  }

  // Only an icon the project names or keeps in a known place; never a default.
  final File? source = dvPwaIconSource(root, pwa);
  if (source != null) {
    final DVRgbaImage art = dvPngDecode(source.readAsBytesSync());
    dvAndroidLauncherSizes.forEach((String density, int size) {
      final File icon = File(p.join(main.path, 'res', 'mipmap-$density', 'ic_launcher.png'));
      icon.parent.createSync(recursive: true);
      icon.writeAsBytesSync(dvPngEncode(dvResizeRgba(art, size, size)));
      changed.add(p.relative(icon.path, from: root));
    });
  }
  return changed;
}

/// [manifest] with the `<application>` element's `android:label` set to [label].
String dvAndroidManifestWithLabel(String manifest, String label) {
  final String escaped = label
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final RegExp application = RegExp(r'<application\b[^>]*>', dotAll: true);
  final Match? tag = application.firstMatch(manifest);
  if (tag == null) return manifest;
  final String opening = tag.group(0)!;
  final RegExp existing = RegExp(r'android:label="[^"]*"');
  final String updated = existing.hasMatch(opening)
      ? opening.replaceFirst(existing, 'android:label="$escaped"')
      : opening.replaceFirst('<application', '<application\n        android:label="$escaped"');
  return manifest.replaceRange(tag.start, tag.end, updated);
}

/// Writes the configured launcher name and icon for [platform] into the
/// project, and returns the files it changed. A platform with no native
/// folder, or a project that configured nothing, is left as it was.
List<String> dvWriteLauncherIdentity(String root, String platform) =>
    switch (platform) {
      'android' || 'fireos' => dvWriteAndroidLauncher(root),
      'ios' => _writeApple(root, 'ios'),
      'macos' => _writeApple(root, 'macos'),
      'windows' => _writeWindows(root),
      'linux' => _writeLinux(root),
      _ => const <String>[],
    };

/// The launcher label `dartvel.pwa` gives, or null.
String? dvLauncherLabel(String root) {
  final Map<Object?, Object?> pwa = _pwaSettings(root);
  return _text(pwa['shortName']) ?? _text(pwa['name']);
}

/// The decoded icon `dartvel.pwa` names (or keeps in a known place), or null.
DVRgbaImage? dvLauncherArt(String root) {
  final File? source = dvPwaIconSource(root, _pwaSettings(root));
  return source == null ? null : dvPngDecode(source.readAsBytesSync());
}

int _background(String root) {
  final Object? colour = _pwaSettings(root)['backgroundColor'];
  return colour is String ? dvHexToArgb(colour) : 0xFFFFFFFF;
}

/// [art] at [size], composited over [background] so nothing is transparent:
/// the App Store refuses an iOS icon with an alpha channel.
DVRgbaImage _opaque(DVRgbaImage art, int size, int background) {
  final DVRgbaImage scaled = dvResizeRgba(art, size, size);
  final int br = (background >> 16) & 0xFF;
  final int bg = (background >> 8) & 0xFF;
  final int bb = background & 0xFF;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final List<int> px = scaled.get(x, y);
      final double alpha = px[3] / 255;
      scaled.set(x, y,
          r: (px[0] * alpha + br * (1 - alpha)).round(),
          g: (px[1] * alpha + bg * (1 - alpha)).round(),
          b: (px[2] * alpha + bb * (1 - alpha)).round());
    }
  }
  return scaled;
}

String _xmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// [plist] with [key]'s string value set to [value], added to the top
/// dictionary when the key is not there.
String dvPlistWithString(String plist, String key, String value) {
  final String escaped = _xmlText(value);
  final RegExp existing = RegExp(
      '(<key>${RegExp.escape(key)}</key>\\s*<string>)[^<]*(</string>)');
  if (existing.hasMatch(plist)) {
    return plist.replaceFirstMapped(
        existing, (Match m) => '${m.group(1)}$escaped${m.group(2)}');
  }
  final int dict = plist.indexOf('<dict>');
  if (dict < 0) return plist;
  final int at = dict + '<dict>'.length;
  return '${plist.substring(0, at)}\n\t<key>$key</key>\n\t<string>$escaped</string>'
      '${plist.substring(at)}';
}

List<String> _writeApple(String root, String platform) {
  final Directory runner = Directory(p.join(root, platform, 'Runner'));
  if (!runner.existsSync()) return const <String>[];
  final List<String> changed = <String>[];
  final String? label = dvLauncherLabel(root);
  final File plist = File(p.join(runner.path, 'Info.plist'));
  if (label != null && plist.existsSync()) {
    final String before = plist.readAsStringSync();
    String after = dvPlistWithString(before, 'CFBundleDisplayName', label);
    // macOS names the menu bar and the Dock after CFBundleName.
    if (platform == 'macos') after = dvPlistWithString(after, 'CFBundleName', label);
    if (after != before) {
      plist.writeAsStringSync(after);
      changed.add(p.relative(plist.path, from: root));
    }
  }
  final DVRgbaImage? art = dvLauncherArt(root);
  final File contents = File(p.join(runner.path, 'Assets.xcassets',
      'AppIcon.appiconset', 'Contents.json'));
  if (art != null && contents.existsSync()) {
    final int background = _background(root);
    final Object? decoded = jsonDecode(contents.readAsStringSync());
    final Object? images = decoded is Map ? decoded['images'] : null;
    for (final Object? image in images is List ? images : const <Object?>[]) {
      if (image is! Map) continue;
      final Object? name = image['filename'];
      final double? points = double.tryParse('${image['size']}'.split('x').first);
      final int scale = int.tryParse('${image['scale'] ?? '1x'}'.replaceAll('x', '')) ?? 1;
      if (name is! String || points == null) continue;
      final int size = (points * scale).round();
      final File icon = File(p.join(contents.parent.path, name));
      icon.writeAsBytesSync(platform == 'ios'
          ? dvPngEncode(_opaque(art, size, background), alpha: false)
          : dvPngEncode(dvResizeRgba(art, size, size)));
      changed.add(p.relative(icon.path, from: root));
    }
  }
  return changed;
}

/// [label] as a C++ wide string literal's contents: anything outside ASCII as
/// a universal character name, so the source compiles in any code page.
String _cppWide(String label) => label.runes.map((int rune) {
      if (rune == 0x5C) return r'\\';
      if (rune == 0x22) return r'\"';
      if (rune >= 0x20 && rune < 0x7F) return String.fromCharCode(rune);
      return rune > 0xFFFF
          ? '\\U${rune.toRadixString(16).padLeft(8, '0')}'
          : '\\u${rune.toRadixString(16).padLeft(4, '0')}';
    }).join();

/// [label] as a C string literal's contents, UTF-8 as octal escapes.
String _cString(String label) => utf8.encode(label).map((int byte) {
      if (byte == 0x5C) return r'\\';
      if (byte == 0x22) return r'\"';
      if (byte >= 0x20 && byte < 0x7F) return String.fromCharCode(byte);
      return '\\${byte.toRadixString(8).padLeft(3, '0')}';
    }).join();

/// The Windows icon sizes: the shell asks for 16 to 256.
const List<int> dvWindowsIconSizes = <int>[16, 24, 32, 48, 64, 128, 256];

/// An `.ico` holding [art] at each of [sizes], each image a PNG (which every
/// Windows since Vista reads).
Uint8List dvIcoEncode(DVRgbaImage art, {List<int> sizes = dvWindowsIconSizes}) {
  final List<Uint8List> pngs = <Uint8List>[
    for (final int size in sizes) dvPngEncode(dvResizeRgba(art, size, size)),
  ];
  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  out.add(header.buffer.asUint8List());
  int offset = 6 + 16 * sizes.length;
  for (var i = 0; i < sizes.length; i++) {
    final int edge = sizes[i] >= 256 ? 0 : sizes[i];
    final ByteData entry = ByteData(16)
      ..setUint8(0, edge)
      ..setUint8(1, edge)
      ..setUint8(2, 0)
      ..setUint8(3, 0)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, pngs[i].length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(entry.buffer.asUint8List());
    offset += pngs[i].length;
  }
  for (final Uint8List png in pngs) {
    out.add(png);
  }
  return out.toBytes();
}

List<String> _writeWindows(String root) {
  final Directory runner = Directory(p.join(root, 'windows', 'runner'));
  if (!runner.existsSync()) return const <String>[];
  final List<String> changed = <String>[];
  final String? label = dvLauncherLabel(root);
  if (label != null) {
    final File main = File(p.join(runner.path, 'main.cpp'));
    if (main.existsSync()) {
      final String before = main.readAsStringSync();
      final String after = before.replaceFirstMapped(
          RegExp(r'window\.Create\(L"(?:[^"\\]|\\.)*"'),
          (Match m) => 'window.Create(L"${_cppWide(label)}"');
      if (after != before) {
        main.writeAsStringSync(after);
        changed.add(p.relative(main.path, from: root));
      }
    }
    final File rc = File(p.join(runner.path, 'Runner.rc'));
    if (rc.existsSync()) {
      final String before = rc.readAsStringSync();
      // The version resource is read in the system code page: ASCII only,
      // and the name as given everywhere else.
      final String ascii = label.runes.every((int r) => r >= 0x20 && r < 0x7F)
          ? label.replaceAll('"', '""')
          : '';
      final String after = ascii.isEmpty
          ? before
          : before.replaceAllMapped(
              RegExp(r'(VALUE "(?:FileDescription|ProductName)", )"[^"]*"'),
              (Match m) => '${m.group(1)}"$ascii"');
      if (after != before) {
        rc.writeAsStringSync(after);
        changed.add(p.relative(rc.path, from: root));
      }
    }
  }
  final DVRgbaImage? art = dvLauncherArt(root);
  if (art != null) {
    final File ico = File(p.join(runner.path, 'resources', 'app_icon.ico'));
    ico.parent.createSync(recursive: true);
    ico.writeAsBytesSync(dvIcoEncode(art));
    changed.add(p.relative(ico.path, from: root));
  }
  return changed;
}

List<String> _writeLinux(String root) {
  final String? label = dvLauncherLabel(root);
  if (label == null) return const <String>[];
  final List<String> changed = <String>[];
  for (final String rel in <String>['runner/my_application.cc', 'my_application.cc']) {
    final File source = File(p.join(root, 'linux', rel));
    if (!source.existsSync()) continue;
    final String before = source.readAsStringSync();
    final String after = before.replaceAllMapped(
        RegExp(r'(gtk_(?:header_bar|window)_set_title\(\w+, )"(?:[^"\\]|\\.)*"'),
        (Match m) => '${m.group(1)}"${_cString(label)}"');
    if (after != before) {
      source.writeAsStringSync(after);
      changed.add(p.relative(source.path, from: root));
    }
  }
  return changed;
}

Map<Object?, Object?> _pwaSettings(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const <Object?, Object?>{};
  try {
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = document is Map ? document['dartvel'] : null;
    final Object? pwa = dartvel is Map ? dartvel['pwa'] : null;
    return pwa is Map ? pwa : const <Object?, Object?>{};
  } on Object {
    // An unparseable pubspec is the build's own failure to report.
    return const <Object?, Object?>{};
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
