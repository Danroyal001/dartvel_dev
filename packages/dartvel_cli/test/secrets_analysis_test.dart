// DV-SECRETS-001, and the declaration it is checked against.
//
// A secret compiled into a client bundle ships to every visitor. Because
// Dartvel compiles both ends from one project it can make that a build error
// rather than a code-review habit -- no stack assembled from separate
// frontend and backend repositories can.
//
// The declaration is what makes the rest possible: an enumerable set is what
// deploy validates, what rotation iterates and what the diagnostic is checked
// against. A typo in a secret name is otherwise a runtime failure in
// production.
import 'package:dartvel_cli/src/secrets/secrets_analysis.dart';
import 'package:test/test.dart';

const String _pubspec = '''
name: shop
dartvel:
  secrets:
    PAYSTACK_SECRET:
      scope: backend
      required: [production, staging]
    PUBLIC_STRIPE_KEY:
      scope: client
      required: [production]
    OPENAI_API_KEY:
      scope: backend
      required: []
''';

void main() {
  group('the declaration', () {
    test('it reads names, scopes and required environments', () {
      final Map<String, DVSecretDeclaration> declared =
          dvParseSecretDeclarations(_pubspec);

      expect(declared.keys,
          containsAll(<String>['PAYSTACK_SECRET', 'PUBLIC_STRIPE_KEY']));
      expect(declared['PAYSTACK_SECRET']!.scope, DVSecretScope.backend);
      expect(declared['PUBLIC_STRIPE_KEY']!.scope, DVSecretScope.client);
      expect(declared['PAYSTACK_SECRET']!.required,
          <String>{'production', 'staging'});
      expect(declared['OPENAI_API_KEY']!.required, isEmpty);
    });

    test('scope defaults to backend when omitted', () {
      // Backend-scoped by default is the whole posture: a secret nobody
      // thought about must not be the one that ships.
      final Map<String, DVSecretDeclaration> declared =
          dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    SOME_KEY:
      required: []
''');
      expect(declared['SOME_KEY']!.scope, DVSecretScope.backend);
    });

    test('a client secret without the PUBLIC_ prefix is refused', () {
      // One client opt-in, not two. The prefix is the marker in the
      // environment and in env.g.dart; the declaration is where it is
      // justified. Allowing them to disagree means the generated bundle and
      // the declaration say different things.
      final List<String> problems = dvValidateDeclarations(
        dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    STRIPE_KEY:
      scope: client
'''),
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('STRIPE_KEY'));
      expect(problems.single, contains('PUBLIC_'));
    });

    test('a backend secret carrying the PUBLIC_ prefix is refused', () {
      // The leak this closes. Nothing generating env.g.dart reads the
      // declaration -- the router builder runs under build_runner and only
      // ever sees the .env file -- so the prefix alone decides what is
      // compiled into the bundle. A name declared backend-scoped and spelled
      // PUBLIC_ therefore ships to every visitor while the pubspec says it
      // never leaves the server, and no diagnostic fires because the value
      // travels through the generated constant rather than a DV.Secrets call
      // the analysis can see.
      final List<String> problems = dvValidateDeclarations(
        dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    PUBLIC_PAYSTACK_SECRET:
      scope: backend
'''),
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('PUBLIC_PAYSTACK_SECRET'));
      expect(problems.single, contains('env.g.dart'));
    });

    test('an undeclared scope on a PUBLIC_ name is refused too', () {
      // scope: backend is the default, so omitting it is the same claim
      // written with fewer words, and it must fail the same way.
      final List<String> problems = dvValidateDeclarations(
        dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    PUBLIC_TOKEN:
      required: [production]
'''),
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('PUBLIC_TOKEN'));
    });

    test('a correctly prefixed client secret passes', () {
      expect(dvValidateDeclarations(dvParseSecretDeclarations(_pubspec)),
          isEmpty);
    });

    test('a project with no secrets block is not an error', () {
      expect(dvParseSecretDeclarations('name: shop\n'), isEmpty);
    });
  });

  group('finding uses', () {
    test('every DV.Secrets accessor counts', () {
      final Set<String> used = dvExtractSecretUses('''
final a = DV.Secrets.get('ONE');
final b = DV.Secrets.maybeGet('TWO');
final c = DV.Secrets.getOr('THREE', 'x');
final d = DV.Secrets.has('FOUR');
''');
      expect(used, <String>{'ONE', 'TWO', 'THREE', 'FOUR'});
    });

    test('a name in a comment is not a use', () {
      // The false positive that makes a diagnostic get switched off.
      expect(
        dvExtractSecretUses("// DV.Secrets.get('OLD_KEY');"),
        isEmpty,
      );
    });

    test('an interpolated name is skipped rather than guessed at', () {
      expect(dvExtractSecretUses(r"DV.Secrets.get('KEY_$env')"), isEmpty);
    });
  });

  group('DV-SECRETS-001', () {
    test('a backend secret reached from a page is an error', () {
      final List<DVSecretFinding> findings = dvAnalyseSecrets(
        declared: dvParseSecretDeclarations(_pubspec),
        clientFiles: <String, String>{
          'lib/pages/checkout.dart': "DV.Secrets.get('PAYSTACK_SECRET');",
        },
      );

      expect(findings, hasLength(1));
      expect(findings.single.code, 'DV-SECRETS-001');
      expect(findings.single.secret, 'PAYSTACK_SECRET');
      expect(findings.single.file, 'lib/pages/checkout.dart');
    });

    test('a client-scoped secret from a page is fine', () {
      expect(
        dvAnalyseSecrets(
          declared: dvParseSecretDeclarations(_pubspec),
          clientFiles: <String, String>{
            'lib/pages/pay.dart': "DV.Secrets.get('PUBLIC_STRIPE_KEY');",
          },
        ),
        isEmpty,
      );
    });

    test('an undeclared name is an error naming the pubspec key to add', () {
      // A typo in a secret name is otherwise a runtime failure in production.
      final List<DVSecretFinding> findings = dvAnalyseSecrets(
        declared: dvParseSecretDeclarations(_pubspec),
        clientFiles: <String, String>{
          'lib/pages/x.dart': "DV.Secrets.get('PAYSTACK_SECERT');",
        },
      );

      expect(findings.single.code, 'DV-SECRETS-002');
      expect(findings.single.message, contains('dartvel.secrets'));
      expect(findings.single.message, contains('PAYSTACK_SECERT'));
    });

    test('the finding says what to do about it', () {
      // A diagnostic that names a rule and not a remedy gets suppressed.
      final DVSecretFinding finding = dvAnalyseSecrets(
        declared: dvParseSecretDeclarations(_pubspec),
        clientFiles: <String, String>{
          'lib/pages/checkout.dart': "DV.Secrets.get('PAYSTACK_SECRET');",
        },
      ).single;

      expect(finding.message, contains('backend function'));
    });
  });

  group('DV-SECRETS-002 in backend code', () {
    test('a typo in a backend file is an error, not a production surprise', () {
      // The spec makes an undeclared name a build error precisely because a
      // typo is otherwise a runtime failure in production. The analysis only
      // ever read client files, so the place secrets are actually used was
      // the one place a misspelling went unnoticed.
      final List<DVSecretFinding> findings = dvAnalyseSecrets(
        declared: dvParseSecretDeclarations(_pubspec),
        clientFiles: const <String, String>{},
        backendFiles: <String, String>{
          'lib/backend/pay.dart': "DV.Secrets.get('PAYSTAK_SECRET');",
        },
      );

      expect(findings, hasLength(1));
      expect(findings.single.code, 'DV-SECRETS-002');
      expect(findings.single.file, 'lib/backend/pay.dart');
      expect(findings.single.message, contains('PAYSTAK_SECRET'));
      expect(findings.single.message, contains('pubspec.yaml'));
    });

    test('a declared backend secret in a backend file is exactly right', () {
      // The whole point of backend scope. Reporting DV-SECRETS-001 here
      // would make the diagnostic fire on correct code, and a diagnostic
      // that fires on correct code gets suppressed project-wide.
      expect(
        dvAnalyseSecrets(
          declared: dvParseSecretDeclarations(_pubspec),
          clientFiles: const <String, String>{},
          backendFiles: <String, String>{
            'lib/backend/pay.dart': "DV.Secrets.get('PAYSTACK_SECRET');",
          },
        ),
        isEmpty,
      );
    });

    test('a client secret read on the backend is fine too', () {
      expect(
        dvAnalyseSecrets(
          declared: dvParseSecretDeclarations(_pubspec),
          clientFiles: const <String, String>{},
          backendFiles: <String, String>{
            'lib/backend/pay.dart': "DV.Secrets.get('PUBLIC_STRIPE_KEY');",
          },
        ),
        isEmpty,
      );
    });
  });

  group('deploy validation', () {
    test('a secret required for the target that does not resolve is fatal', () {
      final List<String> problems = dvValidateEnvironment(
        declared: dvParseSecretDeclarations(_pubspec),
        environment: 'production',
        resolved: <String>{'PUBLIC_STRIPE_KEY'},
      );

      expect(problems, hasLength(1));
      expect(problems.single, contains('PAYSTACK_SECRET'));
      expect(problems.single, contains('production'));
    });

    test('a secret not required for this environment is not fatal', () {
      expect(
        dvValidateEnvironment(
          declared: dvParseSecretDeclarations(_pubspec),
          environment: 'development',
          resolved: const <String>{},
        ),
        isEmpty,
      );
    });

    test('everything resolved is silent', () {
      expect(
        dvValidateEnvironment(
          declared: dvParseSecretDeclarations(_pubspec),
          environment: 'staging',
          resolved: <String>{'PAYSTACK_SECRET'},
        ),
        isEmpty,
      );
    });
  });
}
