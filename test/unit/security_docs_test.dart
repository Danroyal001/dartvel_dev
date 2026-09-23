// The security documents cite the tree, and the tree moves.
//
// SECURITY.md, the secure-development policy, the compliance plan and the
// skill all name files: this is where the password hasher lives, this is the
// filter deciding what reaches a browser, this is the middleware that puts
// headers on a response. That is what makes them usable and it is also how
// they rot — a file is renamed, and a policy that was accurate becomes a
// policy that sends the next reader somewhere that does not exist.
//
// So the citations are checked, the way the spec status index is.
import 'package:test/test.dart';

import '../../tool/ci/security_docs.dart';

void main() {
  group('what a document cites', () {
    test('a backticked path under a known root', () {
      expect(
        dvCitedPaths('Passwords live in '
            '`packages/dartvel_core/lib/src/auth/password.dart`.'),
        <String>['packages/dartvel_core/lib/src/auth/password.dart'],
      );
    });

    test('a directory, named with its trailing slash', () {
      expect(dvCitedPaths('See `packages/dartvel_core/lib/src/auth/`.'),
          <String>['packages/dartvel_core/lib/src/auth/']);
    });

    test('a name that is not a path', () {
      // `DVFieldCipher`, `Sec-GPC`, `HttpOnly` -- most of what the documents
      // put in backticks is an identifier, not a file.
      expect(dvCitedPaths('`DVFieldCipher` and `Sec-GPC` and `HttpOnly`'),
          isEmpty);
    });

    test('a fragment of a path with no root', () {
      // The skill writes `auth/password.dart` as shorthand. There is no
      // single directory that resolves against, so it is not a citation.
      expect(dvCitedPaths('Passwords go through `auth/password.dart`.'),
          isEmpty);
    });

    test('a link to another document, resolved from the one citing it', () {
      expect(
        dvCitedPaths('See [the plan](compliance-plan.md).',
            from: 'docs/security/secure-development.md'),
        <String>['docs/security/compliance-plan.md'],
      );
      expect(
        dvCitedPaths('See [reporting](../../SECURITY.md).',
            from: 'docs/security/compliance-plan.md'),
        <String>['SECURITY.md'],
      );
    });

    test('a link somewhere else entirely', () {
      expect(
          dvCitedPaths('[the law](https://oag.ca.gov/privacy/ccpa)',
              from: 'docs/security/compliance-plan.md'),
          isEmpty);
    });

    test('an anchor into the same document', () {
      expect(dvCitedPaths('[below](#sd-1-no-new-cryptography)',
          from: 'docs/security/secure-development.md'), isEmpty);
    });

    test('a path inside a fenced block is a command, not a citation', () {
      // The skill's "checks to run" block names the checker by the command
      // that runs it. Running it is what proves that one exists.
      const String markdown = '''
Run it:

```
dart tool/ci/security_docs_check.dart
```
''';
      expect(dvCitedPaths(markdown), isEmpty);
    });

    test('the same path twice is one citation', () {
      expect(
        dvCitedPaths('`tool/ci/security_docs.dart` and again '
            '`tool/ci/security_docs.dart`'),
        <String>['tool/ci/security_docs.dart'],
      );
    });
  });

  group('the documents in this repository', () {
    test('every path they cite is there', () {
      // The check the workflow runs, run here too: a broken citation fails
      // at the commit that writes it rather than in a reader's afternoon.
      final List<String> missing = dvMissingCitations();
      expect(missing, isEmpty,
          reason: 'cited by a security document and not in the tree');
    });

    test('the documents themselves are all present', () {
      for (final String document in dvSecurityDocuments) {
        expect(dvExists(document), isTrue, reason: '$document is missing');
      }
    });
  });
}
