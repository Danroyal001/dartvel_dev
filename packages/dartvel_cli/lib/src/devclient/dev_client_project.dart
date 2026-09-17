/// What a project's dev-client build needs from the native side.
///
/// The binding manifest is read from what Flutter resolved rather than from
/// anything declared by hand: `.flutter-plugins-dependencies` lists the native
/// plugins compiled for each platform, and `pubspec.lock` the dartvel_flutter
/// version whose FFI/JNI bindings and renderer the shell carries. The same
/// function produces the shell's manifest at build time and a bundle's at
/// serve time, so the two can only differ by what changed in between.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Targets a development build can be paired with.
const List<String> dvDevClientTargets = <String>[
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
];

/// Where `dartvel dev` reads the page documents it serves.
const String dvDevClientPagesDir = 'studio/pages';

/// Why a manifest could not be resolved.
class DVDevClientProjectException implements Exception {
  const DVDevClientProjectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The binding manifest of the project at [root] for [target].
///
/// Throws [DVDevClientProjectException] when the plugins were never resolved:
/// an empty manifest would load into any shell, including one missing every
/// plugin the project uses.
DVDevClientManifest dvProjectDevClientManifest(String root, String target) {
  final File resolved = File(p.join(root, '.flutter-plugins-dependencies'));
  if (!resolved.existsSync()) {
    throw const DVDevClientProjectException(
      'This project\'s plugins have not been resolved, so which native '
      'bindings it needs is unknown. Run `flutter pub get` first.',
    );
  }
  final Object? document;
  try {
    document = jsonDecode(resolved.readAsStringSync());
  } on FormatException {
    throw const DVDevClientProjectException(
      '.flutter-plugins-dependencies is not JSON. Run `flutter pub get` '
      'again.',
    );
  }
  final Object? plugins = document is Map ? document['plugins'] : null;
  final Object? forTarget = plugins is Map ? plugins[target] : null;
  final List<String> bindings = <String>[
    if (forTarget is List)
      for (final Object? plugin in forTarget)
        if (plugin is Map &&
            plugin['native_build'] != false &&
            plugin['dev_dependency'] != true &&
            plugin['name'] is String)
          'plugin:${plugin['name']}',
  ];
  final String? runtime = _lockedVersion(root, 'dartvel_flutter');
  if (runtime != null) bindings.add('dartvel_flutter@$runtime');
  return DVDevClientManifest(
    target: target,
    bindings: bindings.toSet().toList()..sort(),
  );
}

String? _lockedVersion(String root, String package) {
  final File lock = File(p.join(root, 'pubspec.lock'));
  if (!lock.existsSync()) return null;
  try {
    final Object? document = loadYaml(lock.readAsStringSync());
    final Object? packages = document is Map ? document['packages'] : null;
    final Object? entry = packages is Map ? packages[package] : null;
    final Object? version = entry is Map ? entry['version'] : null;
    return version == null ? null : '$version';
  } on Object {
    return null;
  }
}
