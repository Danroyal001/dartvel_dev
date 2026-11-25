/// Fails when a tracked Dart file names `package:flutter/material.dart` or
/// `package:flutter/cupertino.dart`.
///
///     dart tool/ci/design_imports_check.dart
///
/// Dartvel builds on `material_ui` and `cupertino_ui`, which are copies of
/// those libraries rather than re-exports; the reasoning, and the files that
/// may still name them, are in `tool/ci/design_imports.dart`.
library;

import 'dart:io';

import 'design_imports.dart';

void main() {
  final List<String> problems = dvDesignImportProblems(dvTrackedDartSources());
  for (final String problem in problems) {
    stdout.writeln('::error::$problem');
  }
  if (problems.isEmpty) {
    stdout.writeln('design imports: nothing names flutter/material or '
        'flutter/cupertino');
    return;
  }
  stdout.writeln('${problems.length} place(s) name a deprecated Flutter design '
      'library.');
  exitCode = 1;
}
