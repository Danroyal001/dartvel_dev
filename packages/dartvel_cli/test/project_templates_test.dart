import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:test/test.dart';

void main() {
  test('backend project templates emit strongly typed response maps', () {
    expect(ProjectTemplates.healthFunctionTemplate, isNot(contains('dynamic')));
    expect(ProjectTemplates.contactFormTemplate, isNot(contains('dynamic')));
    expect(ProjectTemplates.readmeTemplate('example'),
        isNot(contains('Map<String, dynamic>')));
  });

  // The scaffold's dependency constraints are what a new project resolves
  // against, and they were hand-written numbers that nothing kept in step with
  // the packages they name. When dartvel_core reached 0.2.1 on pub.dev the
  // template still said ^0.1.1 -- a version that was never published, so every
  // `dartvel create` outside this repository produced a project that could not
  // resolve at all.
  group('the scaffold resolves against what is published', () {
    /// The version each package actually declares, read rather than repeated.
    String declaredVersion(String package) {
      final pubspec = File(
          p.join(_repoRoot(), 'packages', package, 'pubspec.yaml'));
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec.readAsStringSync());
      return match!.group(1)!;
    }

    test('every dartvel constraint admits the version that package declares',
        () {
      final pubspec = ProjectTemplates.pubspecTemplate(name: 'probe', org: 'dev.dartvel');

      for (final String package in <String>[
        'dartvel_core',
        'dartvel_shelf',
        'dartvel_flutter',
        'dartvel_cli',
      ]) {
        final constraint = RegExp('$package: (\\^[0-9][^\\s]*)')
            .firstMatch(pubspec)
            ?.group(1);
        expect(constraint, isNotNull,
            reason: '$package has no hosted constraint in the template');

        final wanted = declaredVersion(package);
        final major = wanted.split('.').first;
        expect(constraint, startsWith('^$major.'),
            reason: '$package is published at $wanted and the template asks '
                'for $constraint, which cannot resolve to it');
      }
    });

    test('the SDK floor is the one every Dartvel package declares', () {
      // 3.4 was the old floor, and reasoning from a stale lower one is exactly
      // what recorded webOS as merely unproven when its Dart could not resolve
      // dependencies at all. A scaffold that admits 3.4 hands a user a project
      // that fails later, in a dependency, rather than at once.
      final pubspec = ProjectTemplates.pubspecTemplate(name: 'probe', org: 'dev.dartvel');

      expect(pubspec, contains('">=3.12.0 <4.0.0"'));
      expect(pubspec, isNot(contains('3.4.0')));
    });
  });
}

/// The repository root, found from the test's own location rather than the
/// working directory, which the suite changes.
String _repoRoot() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'packages', 'dartvel_cli', 'pubspec.yaml'))
      .existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not find the repository root');
    }
    dir = parent;
  }
  return dir.path;
}
