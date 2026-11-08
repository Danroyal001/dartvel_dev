import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Where a project keeps a kind of source file: the `dartvel:` key in
/// `pubspec.yaml` that names it, and the default when it is not set.
///
/// Project Structure: each key takes one directory, a glob, or a list of
/// either. A plain entry is a directory and everything under it; an entry
/// with a glob character is a pattern, matching directories unless it ends
/// in `.dart`, in which case it matches the files themselves. A project
/// whose models live in `lib/data` and in each feature's own folder writes
///
/// ```yaml
/// dartvel:
///   modelsDir:
///     - lib/data
///     - lib/features/*/models
/// ```
List<String> dvSourceEntries(String root, String key, String fallback) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return <String>[fallback];
  final Object? yaml;
  try {
    yaml = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    return <String>[fallback];
  }
  // A Dart config file (`dartvel: dartvel_config.dart`) sets no paths: the
  // defaults apply, as they do in DartvelConfig.load.
  final Object? dartvel = yaml is YamlMap ? yaml['dartvel'] : null;
  final Object? value = dartvel is YamlMap ? dartvel[key] : null;
  final List<String> entries = <String>[
    if (value is String) value,
    if (value is YamlList)
      for (final Object? entry in value)
        if (entry is String) entry,
  ].map(_normalise).where((String e) => e.isNotEmpty).toList();
  return entries.isEmpty ? <String>[fallback] : entries;
}

/// Every Dart file the entries for [key] name, once each, sorted by path so
/// that generated output does not depend on the order a filesystem lists.
List<File> dvSourceFiles(String root, String key, String fallback) {
  final Map<String, File> found = <String, File>{};
  for (final String entry in dvSourceEntries(root, key, fallback)) {
    final String pattern = !_isGlob(entry)
        ? '$entry/**.dart'
        : entry.endsWith('.dart')
            ? entry
            : '$entry/**.dart';
    if (!_isGlob(entry) && !Directory(p.join(root, entry)).existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in Glob(pattern).listFileSystemSync(
      const LocalFileSystem(),
      root: root,
      followLinks: false,
    )) {
      if (entity is File) found[p.normalize(entity.path)] = File(entity.path);
    }
  }
  final List<File> files = found.values.toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

/// The directory a new file of this kind is written to: the first plain
/// directory among the entries, since a glob names no single place.
String dvSourceWriteDirectory(String root, String key, String fallback) {
  for (final String entry in dvSourceEntries(root, key, fallback)) {
    if (!_isGlob(entry)) return entry;
  }
  return fallback;
}

/// The data-model sources: `modelsDir`, `lib/models` by default.
List<File> dvModelSourceFiles(String root) =>
    dvSourceFiles(root, 'modelsDir', 'lib/models');

/// Where `dartvel generate model` writes a new data model.
String dvModelWriteDirectory(String root) =>
    dvSourceWriteDirectory(root, 'modelsDir', 'lib/models');

// Always '/': a glob separator is not a host path separator, and a backslash
// is glob's escape character.
String _normalise(String entry) {
  String e = entry.trim().replaceAll(r'\', '/');
  while (e.startsWith('./')) {
    e = e.substring(2);
  }
  while (e.endsWith('/')) {
    e = e.substring(0, e.length - 1);
  }
  return e;
}

bool _isGlob(String entry) => entry.contains(RegExp(r'[*?\[{]'));
