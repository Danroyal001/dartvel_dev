// Names the windowing contract says will never exist.
//
// The Multi-Window section closes this as a list: "No DVWindowManager, no
// DV.Windows, no DVWindowing -- not as a public type, not as a documented
// name, ever." A rule stated in prose comes back the first time someone needs
// a place to put something; a rule with a test does not.
//
// DVWindowManager is public API today: DV.Platform.Window returns it. The
// contract says anything beyond DV.Window and DVWindow is private, but Dart
// privacy is per *library*, so a private class in src/windowing/window.dart
// cannot be the return type of a member in dartvel_flutter.dart. The clause is
// not implementable as written, so the name is recorded as a named exception
// rather than quietly dropped -- and the rule still catches a new one.
import 'dart:io';

import 'package:dartvel_cli/src/analysis/banned_names.dart';
import 'package:test/test.dart';

void main() {
  test('the banned list is the one the spec names', () {
    expect(dvBannedPublicNames,
        containsAll(<String>['DVWindowManager', 'DVWindowing', 'DV.Windows']));
  });

  test('it finds a banned public declaration', () {
    // DVWindowing, not DVWindowManager: the latter is a recorded exception,
    // so using it here would assert that the exception works rather than that
    // the rule does.
    final List<DVBannedName> found = dvFindBannedNames(
      path: 'lib/x.dart',
      source: 'class DVWindowing {}\n',
    );
    expect(found, hasLength(1));
    expect(found.single.name, 'DVWindowing');
  });

  test('a private declaration is fine', () {
    // The contract bans the public name. What the implementation needs
    // privately is its own business.
    expect(
      dvFindBannedNames(path: 'lib/x.dart', source: 'class _DVWindowing {}'),
      isEmpty,
    );
  });

  test('a comment saying the name does not exist is not a use', () {
    // The spec's own "there is no DVWindowManager" sentence, and every doc
    // comment repeating it, must not trip the rule that enforces it.
    expect(
      dvFindBannedNames(
        path: 'lib/x.dart',
        source: '// There is no DVWindowing, and never will be.\n'
            'class Fine {}\n',
      ),
      isEmpty,
    );
  });

  test('a reference in a string is not a declaration', () {
    expect(
      dvFindBannedNames(
        path: 'lib/x.dart',
        source: "final help = 'DVWindowing was removed';",
      ),
      isEmpty,
    );
  });

  test('the one exception is recorded with its reason, not hidden', () {
    // A rule with a silent carve-out is a rule nobody can audit.
    expect(dvBannedNameExceptions.keys, <String>['DVWindowManager']);
    expect(dvBannedNameExceptions['DVWindowManager'], contains('privacy'));
  });

  test('an exception does not disable the rule for the others', () {
    expect(
      dvFindBannedNames(path: 'lib/x.dart', source: 'class DVWindowing {}'),
      hasLength(1),
    );
  });

  test('the framework packages carry no unrecorded banned name', () {
    final List<DVBannedName> found = <DVBannedName>[];
    for (final String package in <String>[
      'dartvel_core',
      'dartvel_flutter',
      'dartvel_shelf',
    ]) {
      final Directory lib = Directory('../$package/lib');
      if (!lib.existsSync()) continue;
      for (final FileSystemEntity e
          in lib.listSync(recursive: true, followLinks: false)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        found.addAll(
          dvFindBannedNames(path: e.path, source: e.readAsStringSync()),
        );
      }
    }

    expect(
      found.map((DVBannedName b) => '${b.name} in ${b.path}').toList(),
      isEmpty,
      reason: 'the windowing contract names these as never-existing',
    );
  });
}
