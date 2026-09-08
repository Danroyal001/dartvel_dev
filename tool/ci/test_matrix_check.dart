/// Fails when a package's suite is not run, or a job runs nothing.
///
/// Two failures, both of which have already happened here and both of which
/// look like success:
///
///   * A package gains a `test/` directory and nobody adds it to the matrix.
///     Every job passes, the run is green, and the suite has never run.
///   * A package is renamed and the matrix is not. The job's working directory
///     does not exist, so bash cannot start -- which reads as an
///     infrastructure fault rather than a stale name, and `dartvel_dev` sat
///     that way until somebody looked.
///
/// The workflow's own comments record both. A rule nothing checks drifts back,
/// which is the reason this file exists rather than a third comment.
///
/// The paths are arguments so the checker can be pointed at a copy with a line
/// taken out of it, which is how its two refusals were watched rather than
/// assumed. Defaults are the real ones.
library;

import 'dart:io';

void main(List<String> arguments) {
  final String workflowPath =
      arguments.isNotEmpty ? arguments[0] : '.github/workflows/tests.yml';
  final String packagesRoot = arguments.length > 1 ? arguments[1] : 'packages';

  final File workflow = File(workflowPath);
  if (!workflow.existsSync()) {
    stderr.writeln('test-matrix: $workflowPath is not there');
    exit(1);
  }

  final Set<String> declared = _matrixPackages(workflow.readAsStringSync());
  if (declared.isEmpty) {
    // The parser stopped matching rather than the matrix emptying. A check
    // that passes because it read nothing is the thing this file is for.
    stderr.writeln('test-matrix: no matrix packages were found at all, so '
        'this check is reading nothing. Fix the parser here rather than '
        'assuming the workflow lost its matrix.');
    exit(1);
  }

  final Directory packages = Directory(packagesRoot);
  if (!packages.existsSync()) {
    stderr.writeln('test-matrix: $packagesRoot is not there');
    exit(1);
  }

  final List<String> problems = <String>[];

  final Set<String> withSuites = <String>{};
  for (final FileSystemEntity entity in packages.listSync()) {
    if (entity is! Directory) continue;
    final String name = entity.path.split(Platform.pathSeparator).last;
    if (!_hasTests(Directory('${entity.path}/test'))) continue;
    withSuites.add(name);
    if (!declared.contains(name)) {
      problems.add('$name has a suite and no job runs it.');
    }
  }

  for (final String name in declared) {
    if (!Directory('$packagesRoot/$name').existsSync()) {
      problems.add('the matrix runs "$name", which is not a package here.');
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('test-matrix: ${problems.length} problem(s)');
    for (final String problem in problems) {
      stderr.writeln('  - $problem');
    }
    stderr.writeln('');
    stderr.writeln('A suite nobody runs and a job that cannot start both '
        'leave the run green. Add the package to the matrix in '
        '$workflowPath, or take the stale name out of it.');
    exit(1);
  }

  stdout.writeln('test-matrix: ${withSuites.length} packages with suites, '
      'every one of them run by a job, and every job a package that is here.');
}

/// The `package:` values of the test matrix's `include:` entries.
Set<String> _matrixPackages(String yaml) => <String>{
      for (final RegExpMatch match
          in RegExp(r'-\s*\{\s*package:\s*([A-Za-z0-9_]+)').allMatches(yaml))
        match.group(1)!,
    };

/// Whether [directory] holds at least one test.
///
/// A `test/` with no test in it is not a suite, and refusing a package for
/// having an empty directory would be a rule about directories rather than
/// about what runs.
bool _hasTests(Directory directory) {
  if (!directory.existsSync()) return false;
  for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('_test.dart')) return true;
  }
  return false;
}
