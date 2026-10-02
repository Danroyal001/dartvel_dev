/// The build cache: a step whose every input is unchanged reuses what it
/// produced last time instead of running again.
///
/// Two steps of `dartvel build web` and `web-server` are slow enough to be
/// worth it: Flutter's own web build, and reading each route's semantics tree
/// in a browser, which for a site of sixty routes is ten minutes or more on a
/// loaded machine.
///
/// The rule this keeps is that a cached result is never stale. A key is a
/// SHA-256 over the *contents* of every input that can change the output, so
/// one changed byte anywhere is a different key and a fresh build. Hashing
/// file names would reuse a build after an edit; hashing modification times
/// would rebuild after a checkout that changed nothing.
///
/// An entry is a directory under `.dartvel/cache/<stage>/<key>/` holding the
/// files and a `manifest.json` written last, listing each file with its size
/// and hash. An entry without a manifest, or whose files do not match it, is
/// a build that was interrupted or a disk that was tampered with: it is
/// deleted and the step runs. Entries beyond [DVBuildCache.keepPerStage] are
/// pruned oldest first, and so is anything over [DVBuildCache.maxBytes].
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Bumped when the semantics capture changes what it writes, so captures
/// from an older capture are never reused.
const int dvSemanticsCaptureVersion = 1;

/// Where the cache lives inside a project.
const String dvBuildCacheDirectory = '.dartvel/cache';

/// A content hash that can be fed paths, files, directories and text in a
/// fixed order, so the same inputs always give the same key.
class DVContentHash {
  final List<int> _parts = <int>[];

  void addText(String label, String value) {
    _parts
      ..addAll(utf8.encode('$label\u0000'))
      ..addAll(utf8.encode(value))
      ..add(0);
  }

  /// A file's contents under its project-relative name. A missing file is
  /// recorded as missing: deleting an input changes the key too.
  void addFile(String label, File file) {
    _parts.addAll(utf8.encode('file\u0000$label\u0000'));
    if (file.existsSync()) {
      _parts.addAll(sha256.convert(file.readAsBytesSync()).bytes);
    } else {
      _parts.addAll(utf8.encode('<missing>'));
    }
    _parts.add(0);
  }

  /// Every file under [directory], in sorted order, named relative to
  /// [relativeTo]. A missing directory is recorded as missing.
  void addDirectory(String label, Directory directory, {required String relativeTo, bool Function(String relative)? skip}) {
    if (!directory.existsSync()) {
      addText('dir:$label', '<missing>');
      return;
    }
    final List<File> files = <File>[
      for (final FileSystemEntity entity in directory.listSync(recursive: true, followLinks: false))
        if (entity is File) entity,
    ]..sort((File a, File b) => a.path.compareTo(b.path));
    for (final File file in files) {
      final String relative = p.relative(file.path, from: relativeTo).replaceAll(r'\', '/');
      if (skip != null && skip(relative)) continue;
      addFile(relative, file);
    }
  }

  String get digest => sha256.convert(_parts).toString();
}

/// The key of a Flutter web build in [projectRoot]: its sources, assets and
/// configuration, every package it depends on by path, the Flutter and
/// Dartvel versions, and the arguments the build is run with.
String dvWebBuildKey({
  required String projectRoot,
  required List<String> flutterArguments,
  required String platform,
  required String profile,
  required String dartvelVersion,
  required String flutterVersion,
}) {
  final DVContentHash hash = DVContentHash()
    ..addText('stage', 'flutter-web')
    ..addText('platform', platform)
    ..addText('profile', profile)
    ..addText('dartvel', dartvelVersion)
    ..addText('flutter', flutterVersion)
    ..addText('arguments', flutterArguments.join('\u0001'));
  for (final String name in <String>['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'build.yaml', 'dartvel.yaml', 'l10n.yaml']) {
    hash.addFile(name, File(p.join(projectRoot, name)));
  }
  // lib/ holds the generated client too, so generation is covered by it.
  hash.addDirectory('lib', Directory(p.join(projectRoot, 'lib')), relativeTo: projectRoot);
  hash.addDirectory('web', Directory(p.join(projectRoot, 'web')), relativeTo: projectRoot);
  for (final String asset in dvDeclaredAssetPaths(projectRoot)) {
    final String path = p.join(projectRoot, asset);
    if (FileSystemEntity.isDirectorySync(path)) {
      hash.addDirectory('asset:$asset', Directory(path), relativeTo: projectRoot);
    } else {
      hash.addFile('asset:$asset', File(path));
    }
  }
  // A package depended on by path is source, not a version: its lock entry
  // does not change when its code does. Hosted packages are pinned by the
  // lockfile above.
  for (final ({String name, String root}) package in dvPathDependencies(projectRoot)) {
    hash.addDirectory('package:${package.name}', Directory(p.join(package.root, 'lib')), relativeTo: package.root);
    hash.addFile('package:${package.name}/pubspec.yaml', File(p.join(package.root, 'pubspec.yaml')));
  }
  return hash.digest;
}

/// The asset paths `flutter: assets:` declares in [projectRoot]'s pubspec, as
/// written there (a directory ends in `/`). Read line by line: the pubspec
/// is YAML, but this list is the only part needed and its shape is fixed.
List<String> dvDeclaredAssetPaths(String projectRoot) {
  final File pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const <String>[];
  final List<String> assets = <String>[];
  bool inFlutter = false;
  bool inAssets = false;
  int assetsIndent = -1;
  for (final String line in pubspec.readAsLinesSync()) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final int indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      inFlutter = line.startsWith('flutter:');
      inAssets = false;
      continue;
    }
    if (inFlutter && line.trim() == 'assets:') {
      inAssets = true;
      assetsIndent = indent;
      continue;
    }
    if (inAssets) {
      if (indent <= assetsIndent) {
        inAssets = false;
        continue;
      }
      final String trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        final String value = trimmed.substring(2).trim();
        // `- path: x` (the map form) or `- x`.
        final String path = value.startsWith('path:') ? value.substring(5).trim() : value;
        assets.add(path.replaceAll(RegExp(r'''^['"]|['"]$'''), ''));
      }
    }
  }
  return assets;
}

/// The packages [projectRoot] resolves to a directory on disk outside any
/// package cache or SDK: path dependencies, whose source is part of the build.
List<({String name, String root})> dvPathDependencies(String projectRoot) {
  final File config = File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return const <({String name, String root})>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return const <({String name, String root})>[];
  }
  final Object? packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! List) return const <({String name, String root})>[];
  final List<({String name, String root})> found = <({String name, String root})>[];
  for (final Object? package in packages) {
    if (package is! Map) continue;
    final Object? name = package['name'];
    final Object? rootUri = package['rootUri'];
    if (name is! String || rootUri is! String) continue;
    final Uri uri = Uri.parse(rootUri);
    final String root = uri.isAbsolute
        ? (uri.scheme == 'file' ? uri.toFilePath() : '')
        : p.normalize(p.join(projectRoot, '.dart_tool', uri.toFilePath()));
    if (root.isEmpty) continue;
    final String normalized = root.replaceAll(r'\', '/');
    if (normalized.contains('/.pub-cache/') || normalized.contains('/Pub/Cache/') ||
        normalized.contains('/flutter/packages/') || normalized.contains('/bin/cache/') ||
        p.equals(p.normalize(root), p.normalize(projectRoot))) {
      continue;
    }
    found.add((name: name, root: root));
  }
  return found;
}

/// A hash of every file in [directory], for keying what is derived from it.
String dvDirectoryHash(Directory directory) {
  final DVContentHash hash = DVContentHash()
    ..addDirectory('', directory, relativeTo: directory.path);
  return hash.digest;
}

/// The cache in one project.
class DVBuildCache {
  DVBuildCache(
    this.projectRoot, {
    this.enabled = true,
    this.keepPerStage = 3,
    this.maxBytes = 2 * 1024 * 1024 * 1024,
  });

  final String projectRoot;

  /// False with `--no-cache`: nothing is read, and nothing is written.
  final bool enabled;

  /// How many entries each stage keeps; older ones are pruned.
  final int keepPerStage;

  /// The most the whole cache may hold; the oldest entries go first.
  final int maxBytes;

  Directory _entry(String stage, String key) =>
      Directory(p.join(projectRoot, dvBuildCacheDirectory, stage, key));

  /// Puts the files of entry [key] of [stage] into [target], replacing what
  /// is there, and returns true; false (and [target] untouched) when there is
  /// no valid entry.
  bool restore(String stage, String key, Directory target) {
    if (!enabled) return false;
    final Directory entry = _entry(stage, key);
    final Map<String, ({int size, String hash})>? manifest = _validManifest(entry);
    if (manifest == null) return false;
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    for (final String relative in manifest.keys) {
      final File source = File(p.join(entry.path, 'files', relative));
      final File destination = File(p.join(target.path, relative));
      destination.parent.createSync(recursive: true);
      source.copySync(destination.path);
    }
    // Touched, so pruning keeps what is in use.
    File(p.join(entry.path, 'manifest.json')).setLastModifiedSync(DateTime.now());
    return true;
  }

  /// Copies every file of [source] into entry [key] of [stage]. The manifest
  /// is written last, so an entry interrupted half way has none and is never
  /// read.
  void store(String stage, String key, Directory source) {
    if (!enabled || !source.existsSync()) return;
    final Directory entry = _entry(stage, key);
    final Directory staging = Directory('${entry.path}.partial-$pid');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    final Map<String, Object?> files = <String, Object?>{};
    for (final FileSystemEntity entity in source.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String relative = p.relative(entity.path, from: source.path).replaceAll(r'\', '/');
      final File copy = File(p.join(staging.path, 'files', relative));
      copy.parent.createSync(recursive: true);
      entity.copySync(copy.path);
      final List<int> bytes = copy.readAsBytesSync();
      files[relative] = <String, Object?>{'size': bytes.length, 'sha256': sha256.convert(bytes).toString()};
    }
    File(p.join(staging.path, 'manifest.json'))
        .writeAsStringSync(jsonEncode(<String, Object?>{'files': files}));
    if (entry.existsSync()) entry.deleteSync(recursive: true);
    entry.parent.createSync(recursive: true);
    staging.renameSync(entry.path);
    prune(stage);
  }

  /// Whether entry [key] of [stage] is there and valid.
  bool has(String stage, String key) => enabled && _validManifest(_entry(stage, key)) != null;

  /// The manifest of [entry] when every file it lists is there with the size
  /// and hash it records; otherwise null, and the entry is deleted.
  Map<String, ({int size, String hash})>? _validManifest(Directory entry) {
    final File manifestFile = File(p.join(entry.path, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      if (entry.existsSync()) entry.deleteSync(recursive: true);
      return null;
    }
    try {
      final Object? decoded = jsonDecode(manifestFile.readAsStringSync());
      final Object? files = decoded is Map ? decoded['files'] : null;
      if (files is! Map) throw const FormatException('no files');
      final Map<String, ({int size, String hash})> manifest = <String, ({int size, String hash})>{};
      for (final MapEntry<Object?, Object?> file in files.entries) {
        final Object? details = file.value;
        if (file.key is! String || details is! Map) throw const FormatException('bad entry');
        final File stored = File(p.join(entry.path, 'files', file.key! as String));
        if (!stored.existsSync()) throw const FormatException('missing file');
        final List<int> bytes = stored.readAsBytesSync();
        final String hash = sha256.convert(bytes).toString();
        if (bytes.length != details['size'] || hash != details['sha256']) {
          throw const FormatException('changed file');
        }
        manifest[file.key! as String] = (size: bytes.length, hash: hash);
      }
      return manifest;
    } on Object {
      entry.deleteSync(recursive: true);
      return null;
    }
  }

  /// Keeps the newest [keepPerStage] entries of [stage], then trims the whole
  /// cache to [maxBytes], oldest first.
  void prune(String stage) {
    final Directory stageDirectory = Directory(p.join(projectRoot, dvBuildCacheDirectory, stage));
    if (stageDirectory.existsSync()) {
      final List<Directory> entries = _entriesNewestFirst(stageDirectory);
      for (final Directory old in entries.skip(keepPerStage)) {
        old.deleteSync(recursive: true);
      }
    }
    final Directory all = Directory(p.join(projectRoot, dvBuildCacheDirectory));
    if (!all.existsSync()) return;
    final List<Directory> everything = <Directory>[
      for (final FileSystemEntity stageEntity in all.listSync())
        if (stageEntity is Directory) ..._entriesNewestFirst(stageEntity),
    ]..sort((Directory a, Directory b) => _touched(b).compareTo(_touched(a)));
    // The newest entry stays even when it alone is over the cap: it is the
    // one the next build will ask for.
    int total = 0;
    for (final (int index, Directory entry) in everything.indexed) {
      total += _size(entry);
      if (index > 0 && total > maxBytes) entry.deleteSync(recursive: true);
    }
  }

  static List<Directory> _entriesNewestFirst(Directory stage) => <Directory>[
        for (final FileSystemEntity entity in stage.listSync())
          if (entity is Directory && !entity.path.contains('.partial-')) entity,
      ]..sort((Directory a, Directory b) => _touched(b).compareTo(_touched(a)));

  static DateTime _touched(Directory entry) {
    final File manifest = File(p.join(entry.path, 'manifest.json'));
    return manifest.existsSync() ? manifest.lastModifiedSync() : DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int _size(Directory entry) {
    int total = 0;
    for (final FileSystemEntity entity in entry.listSync(recursive: true, followLinks: false)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }
}
