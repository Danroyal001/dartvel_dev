// Evidence that nothing calls.
//
// tool/spec_status_check.dart holds a section's claim to the files it cites,
// and checks that they exist. Existing is a low bar, and three findings in
// one audit cleared it while doing nothing at all:
//
//   - @DVPage(policy:) had a guard builder, a runtime checker, and a unit
//     test for each. No caller. The index said the router called them.
//   - DVScheduler evaluates cron entries. Nothing instantiates it, and its
//     absent note says it runs them.
//   - The lifecycle setters are called only from their own tests, so four of
//     six signals never change.
//
// All three are one mistake: a correct implementation written in isolation,
// unit-tested against its own return value, recorded as shipped, never
// wired. A test asserting on the shape of a string returned by an uncalled
// function passes forever.
//
// So the question this asks is not "does the file exist" but "does anything
// outside a test call what it declares".
import 'package:test/test.dart';

import '../../tool/ci/evidence_reachable.dart';

void main() {
  group('what a source declares', () {
    test('classes, top-level functions and constants', () {
      const String source = '''
class DVAdminMount {}
String dvAdminMountProblem(String path) => '';
const String dvAdminDefaultPath = '/__studio';
enum DVAdminRequest { serve }
''';

      expect(
        dvPublicSymbols(source),
        containsAll(<String>[
          'DVAdminMount',
          'dvAdminMountProblem',
          'dvAdminDefaultPath',
          'DVAdminRequest',
        ]),
      );
    });

    test('private ones are not declarations anybody could call', () {
      // A file whose only public surface is private is unreachable by
      // definition and would fail this check forever.
      const String source = '''
class _Hidden {}
String _helper() => '';
''';

      expect(dvPublicSymbols(source), isEmpty);
    });

    test('a symbol inside a comment is not a declaration', () {
      // Doc comments in this repository quote the API constantly.
      const String source = '''
/// See [DVSomethingElse] and dvOtherThing.
// class DVCommentedOut {}
class DVReal {}
''';

      expect(dvPublicSymbols(source), <String>{'DVReal'});
    });
  });

  group('which evidence nothing reaches', () {
    test('a file whose symbols appear only in its own tests is unreachable',
        () {
      // The exact shape of the page policy bug: the builder, the checker and
      // two unit tests, and no caller anywhere else.
      final List<String> unreachable = dvUnreachableEvidence(
        symbolsByFile: <String, Set<String>>{
          'lib/src/generators/page_policy.dart': <String>{'dvPageGuardChain'},
        },
        referencesByLibFile: <String, Set<String>>{
          'lib/src/generators/client_generator.dart': <String>{'esc', 'guardRedirectFor'},
        },
      );

      expect(unreachable, <String>['lib/src/generators/page_policy.dart']);
    });

    test('a file something calls is reachable', () {
      expect(
        dvUnreachableEvidence(
          symbolsByFile: <String, Set<String>>{
            'lib/src/generators/page_policy.dart': <String>{'dvPageGuardChain'},
          },
          referencesByLibFile: <String, Set<String>>{
            'lib/src/generators/client_generator.dart': <String>{'dvPageGuardChain'},
          },
        ),
        isEmpty,
      );
    });

    test('a file referencing itself does not count as reached', () {
      // page_policy.dart calls its own dvPagePolicyGuard from
      // dvPageGuardChain. That is not a caller.
      expect(
        dvUnreachableEvidence(
          symbolsByFile: <String, Set<String>>{
            'lib/a.dart': <String>{'dvThing'},
          },
          referencesByLibFile: <String, Set<String>>{
            'lib/a.dart': <String>{'dvThing'},
          },
        ),
        <String>['lib/a.dart'],
      );
    });

    test('one referenced symbol is enough', () {
      // A file declaring six things of which one is called is wired. This
      // check is for files nothing reaches at all, not for dead members.
      expect(
        dvUnreachableEvidence(
          symbolsByFile: <String, Set<String>>{
            'lib/a.dart': <String>{'dvUsed', 'dvUnused', 'DVAlsoUnused'},
          },
          referencesByLibFile: <String, Set<String>>{
            'lib/b.dart': <String>{'dvUsed'},
          },
        ),
        isEmpty,
      );
    });

    test('a file declaring nothing public is not reported', () {
      // Nothing to call, so nothing to be unreachable. Reporting it would be
      // noise that teaches people to ignore the check.
      expect(
        dvUnreachableEvidence(
          symbolsByFile: <String, Set<String>>{'lib/a.dart': <String>{}},
          referencesByLibFile: <String, Set<String>>{},
        ),
        isEmpty,
      );
    });
  });
}
