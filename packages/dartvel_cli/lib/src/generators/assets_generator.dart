/// `DVAsset`: the files a project bundles, as an enum rather than strings.
///
/// A path in a string is checked by nothing. A renamed file, a typo, or an
/// asset never listed in `pubspec.yaml` all pass every build and fail on a
/// device as a blank box. The generator reads what the project bundles and
/// writes one value per file, named after it and carrying its kind, so
/// `DVBox.image(DVAsset.logoSmall)` is a compile error the day the file is
/// renamed.
library dartvel_cli.generators.assets;

import 'dart:io';

import 'package:path/path.dart' as p;

/// What a bundled file is, from its extension.
///
/// The framework declares the same names in `DVAssetKind`; this is the
/// generator's side of it.
const Map<String, String> dvAssetKinds = <String, String>{
  'png': 'image',
  'jpg': 'image',
  'jpeg': 'image',
  'gif': 'image',
  'webp': 'image',
  'bmp': 'image',
  'svg': 'image',
  'mp4': 'video',
  'mov': 'video',
  'webm': 'video',
  'mkv': 'video',
  'm4v': 'video',
  'mp3': 'audio',
  'wav': 'audio',
  'aac': 'audio',
  'ogg': 'audio',
  'flac': 'audio',
  'ttf': 'font',
  'otf': 'font',
  'woff': 'font',
  'woff2': 'font',
  'glb': 'model3d',
  'gltf': 'model3d',
  'usdz': 'model3d',
};

/// One bundled file: where it is, what it is, and what it is called in Dart.
class DVAssetEntry {
  DVAssetEntry({required this.path, required this.kind, required this.name});

  /// The path as `pubspec.yaml` bundles it, forward slashes on every host.
  final String path;

  /// `image`, `video`, `audio`, `font`, `model3d` or `data`.
  final String kind;

  /// The enum value's name.
  String name;
}

/// The assets [root]'s `pubspec.yaml` bundles, in path order.
///
/// A folder listed there brings the files in it, which is what Flutter does;
/// a file listed brings itself. A path that does not exist is skipped rather
/// than named, since an enum value for a missing file is the thing this
/// generator exists to prevent.
List<DVAssetEntry> dvReadAssets(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return <DVAssetEntry>[];
  final List<String> declared = _declaredAssets(pubspec.readAsLinesSync());
  final List<String> files = <String>[];
  for (final String entry in declared) {
    final String full = p.join(root, entry);
    if (Directory(full).existsSync()) {
      for (final FileSystemEntity e in Directory(full).listSync()) {
        if (e is File) files.add(p.relative(e.path, from: root));
      }
    } else if (File(full).existsSync()) {
      files.add(entry);
    }
  }
  final List<String> paths = <String>{
    for (final String file in files) file.replaceAll(r'\', '/'),
  }.toList()
    ..sort();
  final List<DVAssetEntry> assets = <DVAssetEntry>[
    for (final String path in paths)
      DVAssetEntry(
        path: path,
        kind: dvAssetKinds[p.extension(path).replaceFirst('.', '').toLowerCase()] ??
            'data',
        name: dvAssetName(p.basenameWithoutExtension(path),
            kind: dvAssetKinds[
                    p.extension(path).replaceFirst('.', '').toLowerCase()] ??
                'data'),
      ),
  ];
  _resolveClashes(assets);
  return assets;
}

/// `logo-small` becomes `logoSmall`, `hero@2x` becomes `hero2x`, and
/// `marketing.mp4` becomes `marketingVideo`.
///
/// What a file is belongs in its name where the file name does not already
/// say it: an image is read as one from context, and a video, a sound, a
/// font or a model is not. A name that would start with a digit, or end up
/// empty, takes a leading `a`, since neither is a Dart identifier.
String dvAssetName(String base, {String kind = 'data'}) {
  final List<String> words = base
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'asset';
  final StringBuffer out = StringBuffer(words.first.toLowerCase());
  for (final String word in words.skip(1)) {
    out.write(word[0].toUpperCase());
    out.write(word.substring(1).toLowerCase());
  }
  String name = out.toString();
  const Map<String, String> says = <String, String>{
    'video': 'Video',
    'audio': 'Audio',
    'font': 'Font',
    'model3d': 'Model',
  };
  final String? suffix = says[kind];
  if (suffix != null && !name.toLowerCase().endsWith(suffix.toLowerCase())) {
    name = '$name$suffix';
  }
  return RegExp(r'^[0-9]').hasMatch(name) ? 'a$name' : name;
}

/// Two files of the same name take the folder they are in, so both keep a
/// name that says which is which.
void _resolveClashes(List<DVAssetEntry> assets) {
  final Map<String, List<DVAssetEntry>> byName = <String, List<DVAssetEntry>>{};
  for (final DVAssetEntry asset in assets) {
    byName.putIfAbsent(asset.name, () => <DVAssetEntry>[]).add(asset);
  }
  for (final MapEntry<String, List<DVAssetEntry>> group in byName.entries) {
    if (group.value.length < 2) continue;
    for (final DVAssetEntry asset in group.value) {
      final String folder = p.basename(p.dirname(asset.path));
      final String prefix = dvAssetName(folder);
      asset.name = prefix.isEmpty
          ? asset.name
          : '$prefix${asset.name[0].toUpperCase()}${asset.name.substring(1)}';
    }
  }
  // A second pass cannot invent uniqueness, so anything still shared gets a
  // number rather than a file that does not compile.
  final Set<String> taken = <String>{};
  for (final DVAssetEntry asset in assets) {
    String name = asset.name;
    int n = 2;
    while (!taken.add(name)) {
      name = '${asset.name}$n';
      n++;
    }
    asset.name = name;
  }
}

/// The `flutter: assets:` entries, read without a YAML parser: the file is
/// two levels of list under two known keys, and the CLI already reads the
/// rest of `pubspec.yaml` this way.
List<String> _declaredAssets(List<String> lines) {
  final List<String> declared = <String>[];
  bool inFlutter = false;
  bool inAssets = false;
  for (final String line in lines) {
    final String trimmed = line.trimRight();
    if (trimmed.isEmpty || trimmed.trimLeft().startsWith('#')) continue;
    final int indent = trimmed.length - trimmed.trimLeft().length;
    if (indent == 0) {
      inFlutter = trimmed.startsWith('flutter:');
      inAssets = false;
      continue;
    }
    if (!inFlutter) continue;
    final String body = trimmed.trimLeft();
    if (body.startsWith('assets:')) {
      inAssets = true;
      continue;
    }
    if (!body.startsWith('-')) {
      // Another key under flutter:, such as fonts:.
      if (indent <= 2) inAssets = false;
      continue;
    }
    if (!inAssets) continue;
    final String value = body.substring(1).trim().replaceAll(RegExp('^["\']|["\']\$'), '');
    if (value.isNotEmpty) declared.add(value);
  }
  return declared;
}

/// Writes `lib/dartvel_client/assets.g.dart`.
void dvGenerateAssets({required String root}) {
  final List<DVAssetEntry> assets = dvReadAssets(root);
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel routes -- do not edit.')
    ..writeln('//')
    ..writeln('// Every file this project bundles, from pubspec.yaml. Pass one')
    ..writeln('// where an image, a video or a model is asked for:')
    ..writeln('// DVBox.image(DVAsset.logoSmall). A renamed file is then a')
    ..writeln('// compile error rather than a blank box on a device.')
    ..writeln("import 'package:dartvel_flutter/dartvel_flutter.dart';")
    ..writeln()
    ..writeln('enum DVAsset implements DVAssetRef {');
  if (assets.isEmpty) {
    // An empty enum does not compile, and a project bundling nothing still
    // has to build.
    out.writeln("  /// This project bundles no assets yet.");
    out.writeln("  none('', DVAssetKind.data);");
  } else {
    for (int i = 0; i < assets.length; i++) {
      final DVAssetEntry asset = assets[i];
      out.writeln(
          "  ${asset.name}('${asset.path}', DVAssetKind.${asset.kind})${i == assets.length - 1 ? ';' : ','}");
    }
  }
  out
    ..writeln()
    ..writeln('  const DVAsset(this.path, this.kind);')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String path;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final DVAssetKind kind;')
    ..writeln('}');
  final File file = File(p.join(root, 'lib', 'dartvel_client', 'assets.g.dart'));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(out.toString());
}
