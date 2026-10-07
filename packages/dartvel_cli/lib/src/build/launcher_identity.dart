/// The name and icon an Android launcher shows, from `dartvel.pwa`.
///
/// `flutter create` labels the application with its package name
/// (`eating_today`) and gives it the Flutter logo, and nothing in a Dartvel
/// project changed either: the name and icon an application declares for the
/// web never reached the phone. An application now says them once, under
/// `dartvel.pwa`, and every build writes them where Android reads them.
///
/// `shortName` is the launcher label when there is one, because a launcher
/// cuts a long name at about twelve characters; otherwise `name`. The icon is
/// the PWA's source image (`dartvel.pwa.icon`, then `web/icon.png`, then
/// `assets/icon.png`), resized for each launcher density.
///
/// With neither configured nothing is written, so a project that has not
/// said keeps exactly what it had.
library dartvel_cli.build.launcher_identity;

import 'dart:io';

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
