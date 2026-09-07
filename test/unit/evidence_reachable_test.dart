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

  group('what a package barrel exports', () {
    test('a directly exported file is reachable from the barrel', () {
      expect(
        dvExportedFiles(
          barrels: <String>['lib/dartvel.dart'],
          sourceByFile: <String, String>{
            'lib/dartvel.dart': "export 'src/queues/redis_queue.dart';",
            'lib/src/queues/redis_queue.dart': 'class DVRedisQueueAdapter {}',
          },
        ),
        contains('lib/src/queues/redis_queue.dart'),
      );
    });

    test('an export chain is followed', () {
      // tracing_middleware.dart is not named in dartvel.dart at all. It is
      // exported by observability.dart, which the barrel exports, so an
      // application can import it -- a check that only reads the barrel
      // would call it unreachable and be wrong.
      final Set<String> exported = dvExportedFiles(
        barrels: <String>['lib/dartvel.dart'],
        sourceByFile: <String, String>{
          'lib/dartvel.dart': "export 'src/observability/observability.dart';",
          'lib/src/observability/observability.dart':
              "export 'tracing_middleware.dart';",
          'lib/src/observability/tracing_middleware.dart': 'void dvTraced() {}',
        },
      );

      expect(exported, contains('lib/src/observability/tracing_middleware.dart'));
    });

    test('a conditional export names more than one file', () {
      // export 'a.dart' if (dart.library.io) 'b.dart'; is how this
      // repository ships anything that needs sockets: a stub for the web and
      // the real one for a VM. Reading only the first path calls the real
      // implementation unreachable, which is every database, cache, mail and
      // LDAP client in the package.
      final Set<String> exported = dvExportedFiles(
        barrels: <String>['lib/dartvel.dart'],
        sourceByFile: <String, String>{
          'lib/dartvel.dart': "export 'src/auth/ldap_unsupported.dart'\n"
              "    if (dart.library.io) 'src/auth/ldap.dart';",
          'lib/src/auth/ldap_unsupported.dart': 'class DVLdapClient {}',
          'lib/src/auth/ldap.dart': 'class DVLdapClient {}',
        },
      );

      expect(exported, contains('lib/src/auth/ldap_unsupported.dart'));
      expect(exported, contains('lib/src/auth/ldap.dart'));
    });

    test('every branch of a multi-way conditional export is followed', () {
      final Set<String> exported = dvExportedFiles(
        barrels: <String>['lib/dartvel.dart'],
        sourceByFile: <String, String>{
          'lib/dartvel.dart': "export 'stub.dart'"
              " if (dart.library.io) 'io.dart'"
              " if (dart.library.js_interop) 'web.dart';",
          'lib/stub.dart': '',
          'lib/io.dart': '',
          'lib/web.dart': '',
        },
      );

      expect(
        exported,
        containsAll(<String>['lib/stub.dart', 'lib/io.dart', 'lib/web.dart']),
      );
    });

    test('a show clause does not hide the path', () {
      expect(
        dvExportedFiles(
          barrels: <String>['lib/dartvel.dart'],
          sourceByFile: <String, String>{
            'lib/dartvel.dart':
                "export 'src/auth/saml.dart' show DVSaml, DVSamlResult;",
            'lib/src/auth/saml.dart': 'class DVSaml {}',
          },
        ),
        contains('lib/src/auth/saml.dart'),
      );
    });

    test('a package: export is somebody else\'s file', () {
      expect(
        dvExportedFiles(
          barrels: <String>['lib/dartvel.dart'],
          sourceByFile: <String, String>{
            'lib/dartvel.dart': "export 'package:meta/meta.dart';",
          },
        ),
        isEmpty,
      );
    });

    test('an export cycle terminates', () {
      // Not legal Dart to any purpose, but a check that hangs on it is worse
      // than one that ignores it.
      expect(
        dvExportedFiles(
          barrels: <String>['lib/a.dart'],
          sourceByFile: <String, String>{
            'lib/a.dart': "export 'b.dart';",
            'lib/b.dart': "export 'a.dart';",
          },
        ),
        containsAll(<String>['lib/a.dart', 'lib/b.dart']),
      );
    });
  });

  group('who is supposed to be the caller', () {
    test('an adapter the application constructs is not a broken wire', () {
      // DVRedisQueueAdapter is called by nothing in the framework and that
      // is correct: an application constructs it and hands it over. The
      // first version of this check failed the build on ten of these, which
      // is the noise that gets a check switched off.
      final DVEvidenceReach reach = dvEvidenceReach(
        symbolsByFile: <String, Set<String>>{
          'lib/src/queues/redis_queue.dart': <String>{'DVRedisQueueAdapter'},
        },
        referencesByLibFile: <String, Set<String>>{
          'lib/src/queues/queues.dart': <String>{'DVQueues'},
        },
        exportedFiles: <String>{'lib/src/queues/redis_queue.dart'},
      );

      expect(reach.unreachable, isEmpty);
      expect(reach.applicationOnly, <String>['lib/src/queues/redis_queue.dart']);
    });

    test('evidence no caller and no import can reach is unreachable', () {
      // The real finding: DVSqsQueueAdapter is cited as shipped, nothing in
      // the framework names it, and it is not exported from the barrel, so
      // an application cannot import it without reaching into src/.
      final DVEvidenceReach reach = dvEvidenceReach(
        symbolsByFile: <String, Set<String>>{
          'lib/src/queues/sqs_queue.dart': <String>{'DVSqsQueueAdapter'},
        },
        referencesByLibFile: <String, Set<String>>{
          'lib/src/queues/queues.dart': <String>{'DVQueues'},
        },
        exportedFiles: <String>{},
      );

      expect(reach.unreachable, <String>['lib/src/queues/sqs_queue.dart']);
      expect(reach.applicationOnly, isEmpty);
    });

    test('a file the framework calls is neither', () {
      final DVEvidenceReach reach = dvEvidenceReach(
        symbolsByFile: <String, Set<String>>{
          'lib/src/generators/page_policy.dart': <String>{'dvPageGuardChain'},
        },
        referencesByLibFile: <String, Set<String>>{
          'lib/src/generators/client_generator.dart': <String>{
            'dvPageGuardChain',
          },
        },
        exportedFiles: <String>{'lib/src/generators/page_policy.dart'},
      );

      expect(reach.unreachable, isEmpty);
      expect(reach.applicationOnly, isEmpty);
    });
  });
}
