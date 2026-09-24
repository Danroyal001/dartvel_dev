/// What a local path is, read from what is in it.
///
/// Detection is a **proposal, not a verdict**: `dartvel add --dry-run` prints
/// what was detected and what would be generated, and `--target` and `--as`
/// override it. So this is allowed to be wrong, and is not allowed to be
/// quiet about being unsure: a directory matching nothing is `DV-MODULE-009`,
/// which names what it found, because "could not detect the source" tells
/// somebody nothing about what to do next.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// What a source is, in the terms *Module Sources* uses.
enum DVSourceKind {
  /// A Dartvel project: mounted directly, never wrapped.
  dartvel,

  /// A Dart package with no `dartvel:` section. It contributes nothing to
  /// the project graph, so it is an ordinary dependency rather than a module.
  dartPackage,

  /// Swift, Objective-C, a framework or an `.xcframework`.
  apple,

  /// Gradle, Maven, a `.jar` or an `.aar`.
  jvm,

  /// A crate.
  rust,

  /// C or C++ headers, or a CMake project.
  c,

  /// A WebAssembly artifact.
  wasm,

  /// An npm package, which is inspected rather than assumed: a package may be
  /// browser code, Node code, or both.
  npm,

  /// OpenAPI, GraphQL or gRPC. A source, never a binding.
  describedApi,

  /// Nothing here is recognised.
  unknown,

  /// There is nothing at the path.
  missing,
}

/// What [dvDetectSource] made of a path.
class DVDetectedSource {
  const DVDetectedSource({
    required this.kind,
    required this.mechanism,
    this.binding,
    this.code,
    this.reason,
  });

  final DVSourceKind kind;

  /// How a call would reach it, in one phrase, for the installation plan.
  final String mechanism;

  /// The binding kind a generated module would carry, or null when it needs
  /// none. Swift, Objective-C, C++ and Rust all cross the C ABI, so all of
  /// them are `DVFfiBinding`: kind, source language and target are three
  /// dimensions and this is only the first.
  final String? binding;

  /// The diagnostic, when there is one.
  final String? code;

  /// What was found, for a reader deciding what to do about it.
  final String? reason;

  /// Whether a module would be generated from this, or the source used as it
  /// stands.
  bool get generates => switch (kind) {
        DVSourceKind.dartvel => false,
        DVSourceKind.dartPackage => false,
        DVSourceKind.unknown => false,
        DVSourceKind.missing => false,
        _ => true,
      };
}

/// The first file that decides a directory, in the order the specification's
/// table reads. A Dartvel project is checked before everything else.
const Map<String, (DVSourceKind, String, String?)> _byName =
    <String, (DVSourceKind, String, String?)>{
  'package.swift': (DVSourceKind.apple, 'FFI over the C ABI', 'DVFfiBinding'),
  'build.gradle': (DVSourceKind.jvm, 'JNI', 'DVJniBinding'),
  'build.gradle.kts': (DVSourceKind.jvm, 'JNI', 'DVJniBinding'),
  'pom.xml': (DVSourceKind.jvm, 'JNI', 'DVJniBinding'),
  'cargo.toml': (
    DVSourceKind.rust,
    'FFI over the C ABI, or WASM by target',
    'DVFfiBinding',
  ),
  'cmakelists.txt': (DVSourceKind.c, 'FFI over the C ABI', 'DVFfiBinding'),
  'package.json': (
    DVSourceKind.npm,
    'inspected: a web binding, a Node binding, or both',
    'DVWebBinding',
  ),
  'schema.graphql': (
    DVSourceKind.describedApi,
    'typed Dart calls over DV.Http',
    null,
  ),
};

/// The same, by extension, for a directory named by what it holds.
const Map<String, (DVSourceKind, String, String?)> _byExtension =
    <String, (DVSourceKind, String, String?)>{
  '.framework': (DVSourceKind.apple, 'FFI over the C ABI', 'DVFfiBinding'),
  '.xcframework': (DVSourceKind.apple, 'FFI over the C ABI', 'DVFfiBinding'),
  '.jar': (DVSourceKind.jvm, 'JNI', 'DVJniBinding'),
  '.aar': (DVSourceKind.jvm, 'JNI', 'DVJniBinding'),
  '.rs': (
    DVSourceKind.rust,
    'FFI over the C ABI, or WASM by target',
    'DVFfiBinding',
  ),
  '.h': (DVSourceKind.c, 'FFI over the C ABI', 'DVFfiBinding'),
  '.hpp': (DVSourceKind.c, 'FFI over the C ABI', 'DVFfiBinding'),
  '.wasm': (DVSourceKind.wasm, 'a WebAssembly instance', 'DVWasmBinding'),
  '.proto': (DVSourceKind.describedApi, 'typed Dart calls over DV.Http', null),
};

/// What is at [path].
DVDetectedSource dvDetectSource(String path) {
  final Directory dir = Directory(path);
  if (!dir.existsSync()) {
    // Not DV-MODULE-009: nothing was inspected, so nothing can be named, and
    // telling somebody their SDK is unrecognised when they mistyped a path
    // sends them looking in the wrong place.
    return const DVDetectedSource(
      kind: DVSourceKind.missing,
      mechanism: 'nothing is there',
      reason: 'there is no directory at this path',
    );
  }

  final List<String> names = <String>[
    for (final FileSystemEntity entity in dir.listSync())
      p.basename(entity.path),
  ]..sort();

  // A Dartvel module may perfectly well hold a Cargo.toml for its own native
  // code, so this is asked first: reading that as a Rust source would wrap a
  // module that is already a module.
  if (names.contains('pubspec.yaml')) {
    final Object? doc = _yamlOf(File(p.join(path, 'pubspec.yaml')));
    if (doc is Map && doc['dartvel'] is Map) {
      return const DVDetectedSource(
        kind: DVSourceKind.dartvel,
        mechanism: 'used directly',
      );
    }
    return const DVDetectedSource(
      kind: DVSourceKind.dartPackage,
      mechanism: 'an ordinary Dart dependency, not a module',
      reason: 'its pubspec.yaml declares no dartvel: section, so it '
          'contributes nothing to the project graph. dart pub add it.',
    );
  }

  for (final String name in names) {
    final (DVSourceKind, String, String?)? byName = _byName[name.toLowerCase()];
    if (byName != null) return _found(byName);
    // openapi.json, openapi.yaml, openapi.yml.
    if (RegExp(r'^openapi\.(json|ya?ml)$').hasMatch(name.toLowerCase())) {
      return _found((
        DVSourceKind.describedApi,
        'typed Dart calls over DV.Http',
        null,
      ));
    }
    final (DVSourceKind, String, String?)? byExtension =
        _byExtension[p.extension(name).toLowerCase()];
    if (byExtension != null) return _found(byExtension);
  }

  return DVDetectedSource(
    kind: DVSourceKind.unknown,
    mechanism: 'nothing recognised',
    code: 'DV-MODULE-009',
    reason: names.isEmpty
        ? 'the directory is empty'
        : 'nothing here names a source Dartvel can read. It holds: '
            '${names.take(8).join(', ')}'
            '${names.length > 8 ? ', and ${names.length - 8} more' : ''}.',
  );
}

DVDetectedSource _found((DVSourceKind, String, String?) row) =>
    DVDetectedSource(kind: row.$1, mechanism: row.$2, binding: row.$3);

Object? _yamlOf(File file) {
  try {
    return loadYaml(file.readAsStringSync());
  } on Object {
    return null;
  }
}
