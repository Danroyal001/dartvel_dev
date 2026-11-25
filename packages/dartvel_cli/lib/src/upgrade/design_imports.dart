/// Moving a project off `package:flutter/material.dart` and
/// `package:flutter/cupertino.dart`.
///
/// Flutter 3.50 deprecates both libraries for the `material_ui` and
/// `cupertino_ui` packages, and Dartvel 3.50 is built on those packages. They
/// are not re-exports: each is its own copy of the library, so
/// `material_ui`'s `Theme`, `Material` and `MaterialApp` are different classes
/// from `flutter/material`'s. A page that keeps importing the old library
/// builds against the old classes, and under the application's `material_ui`
/// app it finds no theme and no `Material` ancestor, which is a regression
/// that still compiles. So `dartvel upgrade --project` moves the imports with
/// the constraints, and nothing is left half on each.
///
/// The imports are rewritten by Flutter's own data-driven fix,
/// `dart fix --apply --code=migrate_design_widgets` (fix_material.yaml and
/// fix_cupertino.yaml in the SDK), which works on the resolved program and
/// keeps every `show`, `hide` and prefix. What this file adds is what the fix
/// does not: finding which projects need it, and the dependencies written
/// with the floor Dartvel was tested on rather than the `any` the fix writes.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../templates/project_templates.dart';

/// The diagnostic code of Flutter's fix for the two libraries.
const String dvDesignFixCode = 'migrate_design_widgets';

/// The command that rewrites the imports.
const List<String> dvDesignFixCommand = <String>[
  'dart',
  'fix',
  '--apply',
  '--code=$dvDesignFixCode',
];

/// A deprecated Flutter design library and the package that replaces it.
class DVDesignLibrary {
  const DVDesignLibrary({
    required this.deprecated,
    required this.package,
    required this.version,
  });

  /// The library Flutter deprecates, as it is imported.
  final String deprecated;

  /// The package that replaces it.
  final String package;

  /// The version Dartvel was tested with, the floor of the constraint written.
  final String version;

  /// The library that replaces [deprecated].
  String get replacement => 'package:$package/$package.dart';
}

/// The two libraries, material first.
const List<DVDesignLibrary> dvDesignLibraries = <DVDesignLibrary>[
  DVDesignLibrary(
    deprecated: 'package:flutter/material.dart',
    package: 'material_ui',
    version: dvMaterialUiVersion,
  ),
  DVDesignLibrary(
    deprecated: 'package:flutter/cupertino.dart',
    package: 'cupertino_ui',
    version: dvCupertinoUiVersion,
  ),
];

/// An import or export directive of a deprecated design library, at the start
/// of a line. A template that writes one inside a string is a string to the
/// fix too, so it is reported here and left for its author.
final RegExp _directive = RegExp(
  r'''^[ \t]*(?:import|export)[ \t]+['"](package:flutter/(?:material|cupertino)\.dart)['"]''',
  multiLine: true,
);

/// Directories never read: tool caches, dependency installs and build output.
const Set<String> _skipped = <String>{
  '.dart_tool',
  '.git',
  'build',
  'node_modules',
  '.symlinks',
  'ios',
  'android',
  'macos',
  'linux',
  'windows',
};

/// Each Dart file under [root] that imports or exports a deprecated design
/// library, relative to [root] with `/` separators, mapped to the libraries
/// it names. A nested package (one with its own pubspec.yaml) is its own
/// project and is not read.
Map<String, Set<String>> dvFindDesignImports(String root) {
  final Map<String, Set<String>> found = <String, Set<String>>{};
  void walk(Directory dir, {required bool top}) {
    if (!top && File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false)
        ..sort((FileSystemEntity a, FileSystemEntity b) =>
            a.path.compareTo(b.path));
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entry in entries) {
      final String name = p.basename(entry.path);
      if (entry is Directory) {
        if (_skipped.contains(name)) continue;
        walk(entry, top: false);
      } else if (entry is File && name.endsWith('.dart')) {
        final String text;
        try {
          text = entry.readAsStringSync();
        } on FileSystemException {
          continue;
        }
        final Set<String> libraries = <String>{
          for (final RegExpMatch m in _directive.allMatches(text)) m.group(1)!,
        };
        if (libraries.isEmpty) continue;
        found[p.relative(entry.path, from: root).replaceAll(r'\', '/')] =
            libraries;
      }
    }
  }

  final Directory dir = Directory(root);
  if (dir.existsSync()) walk(dir, top: true);
  return found;
}

/// The dependencies [pubspecText] needs for its project to build on
/// `material_ui`/`cupertino_ui`, given the deprecated libraries its sources
/// [imported].
///
/// `material_ui` for a Flutter project that depends on dartvel_flutter even
/// when its own code imports neither library, because the client Dartvel
/// generates into it does. `cupertino_ui` only when a source imports
/// `flutter/cupertino.dart`. Nothing for a project that is not a Flutter
/// project.
List<DVDesignLibrary> dvDesignDependenciesNeeded(
  String pubspecText,
  Set<String> imported,
) {
  final Object? doc;
  try {
    doc = loadYaml(pubspecText);
  } on Object {
    return const <DVDesignLibrary>[];
  }
  if (doc is! YamlMap) return const <DVDesignLibrary>[];
  final Object? deps = doc['dependencies'];
  final Object? dev = doc['dev_dependencies'];
  bool declares(String name) =>
      (deps is YamlMap && deps.containsKey(name)) ||
      (dev is YamlMap && dev.containsKey(name));
  final Object? flutter = deps is YamlMap ? deps['flutter'] : null;
  final bool isFlutter = flutter is YamlMap && flutter['sdk'] == 'flutter';
  if (!isFlutter) return const <DVDesignLibrary>[];
  return <DVDesignLibrary>[
    for (final DVDesignLibrary library in dvDesignLibraries)
      if (!declares(library.package) &&
          (imported.contains(library.deprecated) ||
              (library.package == 'material_ui' &&
                  declares('dartvel_flutter'))))
        library,
  ];
}

/// [pubspecText] with [libraries] added to `dependencies`, each as
/// `name: ^version`, right after the `flutter: sdk: flutter` entry, and
/// every other line exactly as written.
String dvAddDesignDependencies(
  String pubspecText,
  List<DVDesignLibrary> libraries,
) {
  if (libraries.isEmpty) return pubspecText;
  final List<String> lines = pubspecText.split('\n');
  final int section = lines.indexWhere(
    (String line) => RegExp(r'^dependencies:\s*(#.*)?$').hasMatch(line),
  );
  final List<String> added = <String>[
    for (final DVDesignLibrary library in libraries)
      '  ${library.package}: ^${library.version}',
  ];
  if (section < 0) {
    return '${pubspecText.trimRight()}\n\ndependencies:\n${added.join('\n')}\n';
  }
  // After `flutter:` and its nested `sdk: flutter`, when the section has one;
  // otherwise at the top of the section.
  int insertAt = section + 1;
  for (int i = section + 1; i < lines.length; i += 1) {
    final String line = lines[i];
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    if (RegExp(r'^  flutter:\s*(#.*)?$').hasMatch(line)) {
      int j = i + 1;
      while (j < lines.length && lines[j].startsWith('    ')) {
        j += 1;
      }
      insertAt = j;
      break;
    }
  }
  lines.insertAll(insertAt, added);
  return lines.join('\n');
}

/// Runs [dvDesignFixCommand] in [directory]: null when it ran, otherwise what
/// went wrong.
typedef DVDesignFix = Future<String?> Function(String directory);

/// The real [DVDesignFix].
Future<String?> dvRunDesignFix(String directory) async {
  final ProcessResult result;
  try {
    result = await Process.run(
      dvDesignFixCommand.first,
      dvDesignFixCommand.sublist(1),
      workingDirectory: directory,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (e) {
    return '`${dvDesignFixCommand.join(' ')}` could not be run: ${e.message}';
  }
  if (result.exitCode == 0) return null;
  final String said = '${result.stderr}'.trim().isEmpty
      ? '${result.stdout}'
      : '${result.stderr}';
  return '`${dvDesignFixCommand.join(' ')}` failed:\n$said';
}
