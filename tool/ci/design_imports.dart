/// Where Flutter's deprecated design libraries may still be named.
///
/// Flutter 3.50 deprecates `package:flutter/material.dart` and
/// `package:flutter/cupertino.dart` for the `material_ui` and `cupertino_ui`
/// packages. Those are copies of the libraries, not re-exports, so a file on
/// the old import builds a second Material library whose `Theme`, `Material`
/// and `MaterialApp` the application's never see. Every tracked Dart file is
/// read, strings included, because a generator template that writes the old
/// import is a string to the analyzer and reaches every generated project.
/// Comment lines are prose and are not read.
///
/// Imports only `dart:` libraries, so `dart tool/ci/design_imports_check.dart`
/// runs without resolving the root package.
library;

import 'dart:io';

/// The files that have to spell the old libraries, and why.
const Map<String, String> dvDesignImportAllowed = <String, String>{
  'tool/ci/design_imports.dart': 'this file, which names what it forbids',
  'test/unit/design_imports_test.dart': "this check's own test",
  'packages/dartvel_cli/lib/src/upgrade/design_imports.dart':
      '`dartvel upgrade --project` finds the old imports in an application '
          'to move it',
  'packages/dartvel_cli/test/design_imports_test.dart':
      'the fixtures of the application the upgrade moves',
  'packages/dartvel_cli/test/project_upgrade_test.dart':
      'the fixtures of the application the upgrade moves',
  'packages/dartvel_cli/test/scaffold_version_test.dart':
      'asserts the scaffold and generated client never write them',
};

final RegExp _old = RegExp(r'package:flutter/(?:material|cupertino)\.dart');

bool _isComment(String line) {
  final String trimmed = line.trimLeft();
  return trimmed.startsWith('//') || trimmed.startsWith('*');
}

/// One line per place in [sources] (path to text) that names an old library.
List<String> dvDesignImportProblems(Map<String, String> sources) {
  final List<String> problems = <String>[];
  final List<String> paths = sources.keys.toList()..sort();
  for (final String path in paths) {
    if (dvDesignImportAllowed.containsKey(path)) continue;
    final List<String> lines = sources[path]!.split('\n');
    for (int i = 0; i < lines.length; i += 1) {
      final String line = lines[i];
      if (_isComment(line)) continue;
      final RegExpMatch? match = _old.firstMatch(line);
      if (match == null) continue;
      final String replacement = match.group(0)!.contains('material')
          ? 'package:material_ui/material_ui.dart'
          : 'package:cupertino_ui/cupertino_ui.dart';
      problems.add('$path:${i + 1} names ${match.group(0)}; use $replacement');
    }
  }
  return problems;
}

/// Every Dart file git tracks in this repository, by path.
Map<String, String> dvTrackedDartSources({String? root}) {
  final ProcessResult top = Process.runSync(
    'git',
    <String>['rev-parse', '--show-toplevel'],
    workingDirectory: root,
    runInShell: Platform.isWindows,
  );
  final String base = '${top.stdout}'.trim();
  final ProcessResult relative = Process.runSync(
    'git',
    <String>['ls-files', '--full-name', '--', '*.dart'],
    workingDirectory: base,
    runInShell: Platform.isWindows,
  );
  if (relative.exitCode != 0) {
    throw StateError('git ls-files failed: ${relative.stderr}');
  }
  final Map<String, String> out = <String, String>{};
  for (final String path in '${relative.stdout}'.split('\n')) {
    if (path.trim().isEmpty) continue;
    final File file = File('$base/$path');
    if (!file.existsSync()) continue;
    out[path] = file.readAsStringSync();
  }
  return out;
}
