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

    test('the DVSecrets() constructor form is a read too', () {
      // Module trust already counted it. A secret read through the
      // constructor was a way around the declaration check.
      expect(
        dvExtractSecretUses("final k = const DVSecrets().get('CTOR_KEY');\n"
            "final j = DV . Secrets . maybeGet('SPACED_KEY');\n"),
        <String>{'CTOR_KEY', 'SPACED_KEY'},
      );
    });

    test('an interpolated name is skipped rather than guessed at', () {
      expect(dvExtractSecretUses(r"DV.Secrets.get('KEY_$env')"), isEmpty);
    });
  });

  group('a string literal does not hide a read', () {
    // The analysis used to strip `//` and `/*` without knowing where a string
    // began or ended, so a URL earlier on the line erased the rest of it and
    // a glob opened a comment that ran to the end of the file. The read after
    // it was never reported, and an undeclared secret passed the check.
    List<String> sites(String source) => <String>[
          for (final DVSecretUse use in dvFindSecretUses(source))
            '${use.line}:${use.name}',
        ];

    test('a URL in a single-quoted string', () {
      expect(
        sites("final u = 'https://api.example.com'; "
            "final k = DV.Secrets.get('STRIPE_KEY');"),
        <String>['1:STRIPE_KEY'],
      );
    });

    test('a URL in a double-quoted string', () {
      expect(
        sites('final u = "https://api.example.com"; '
            "final k = DV.Secrets.get('DOUBLE_KEY');"),
        <String>['1:DOUBLE_KEY'],
      );
    });

    test('a /* in a string, with the read on the same line', () {
      expect(
        sites("final g = 'lib/*.dart'; final k = DV.Secrets.get('GLOB_KEY');"),
        <String>['1:GLOB_KEY'],
      );
    });

    test('a /* in a string, with the read on a later line', () {
      expect(
        sites("final g = 'lib/*.dart';\n"
            '\n'
            "final k = DV.Secrets.get('GLOB_NEXT_KEY');\n"),
        <String>['3:GLOB_NEXT_KEY'],
      );
    });

    test('a raw string, including one that ends in a backslash', () {
      expect(
        sites(r"final r = r'https://example.com\'; "
            r"final k = DV.Secrets.get('RAW_KEY');"),
        <String>['1:RAW_KEY'],
      );
    });

    test('a raw string with /* and the read on a later line', () {
      expect(
        sites("final r = r'C:\\dir\\/*';\n"
            "final k = DV.Secrets.get('RAW_NEXT_KEY');\n"),
        <String>['2:RAW_NEXT_KEY'],
      );
    });

    test('a triple-quoted string over several lines', () {
      expect(
        sites("final doc = '''\n"
            "it's every lib/*.dart file, not a comment\n"
            "''';\n"
            "final k = DV.Secrets.get('TRIPLE_KEY');\n"),
        <String>['4:TRIPLE_KEY'],
      );
    });

    test('a triple-quoted string closing on the line of the read', () {
      expect(
        sites('final doc = """\n'
            'see "the docs"\n'
            'at https://example.com """; '
            'final k = DV.Secrets.get(\'TRIPLE_SAME_KEY\');\n'),
        <String>['3:TRIPLE_SAME_KEY'],
      );
    });

    test('an interpolation holding quotes and //', () {
      expect(
        sites(r"final m = 'a ${x ?? '//'} b'; "
            r"final k = DV.Secrets.get('INTERP_KEY');"),
        <String>['1:INTERP_KEY'],
      );
    });

    test('an interpolation holding /*, with the read on a later line', () {
      expect(
        sites("final m = \"\${map['/*']}\";\n"
            "final k = DV.Secrets.get('INTERP_NEXT_KEY');\n"),
        <String>['2:INTERP_NEXT_KEY'],
      );
    });

    test('an escaped quote before //', () {
      expect(
        sites(r"final e = 'it\'s // not a comment'; "
            r"final k = DV.Secrets.get('ESCAPED_KEY');"),
        <String>['1:ESCAPED_KEY'],
      );
    });

    test('an escaped double quote before /*', () {
      expect(
        sites(r'final e = "say \"/*\""; '
            "final k = DV.Secrets.get('ESCAPED_DOUBLE_KEY');\n"
            "final j = DV.Secrets.get('ESCAPED_NEXT_KEY');\n"),
        <String>['1:ESCAPED_DOUBLE_KEY', '2:ESCAPED_NEXT_KEY'],
      );
    });

    test('the line counts a block comment that spans lines', () {
      expect(
        sites("/*\n * notes\n */\nfinal k = DV.Secrets.get('AFTER_BLOCK');\n"),
        <String>['4:AFTER_BLOCK'],
      );
    });

    test('an undeclared read behind a URL is DV-SECRETS-002 on its line', () {
      final List<DVSecretFinding> findings = dvAnalyseSecrets(
        declared: dvParseSecretDeclarations(_pubspec),
        clientFiles: const <String, String>{},
        backendFiles: <String, String>{
          'lib/backend/pay.dart': "import 'x.dart';\n"
              "final u = 'https://api.paystack.co'; "
              "final k = DV.Secrets.get('UNDECLARED_KEY');\n",
        },
      );

      expect(findings, hasLength(1));
      expect(findings.single.code, 'DV-SECRETS-002');
      expect(findings.single.secret, 'UNDECLARED_KEY');
      expect(findings.single.line, 2);
      expect(findings.single.toString(), contains('lib/backend/pay.dart:2'));
    });

    test('a secret name in a block comment is not a read', () {
      expect(sites("/* DV.Secrets.get('BLOCK_COMMENT') */"), isEmpty);
    });

    test('a read inside a nested block comment is not a read', () {
      // Block comments nest in Dart, so the first */ does not end this one.
      expect(
        sites("/* outer /* inner */ DV.Secrets.get('NESTED_COMMENT') */"),
        isEmpty,
      );
    });

    test('a read spelled inside a plain string is not a read', () {
      expect(sites("final s = \"DV.Secrets.get('IN_A_STRING')\";"), isEmpty);
    });

    test('a read spelled inside a triple-quoted template is not a read', () {
      expect(
        sites("final t = '''\nfinal k = DV.Secrets.get('IN_TEMPLATE');\n''';"),
        isEmpty,
      );
    });

    test('a secret name in a string that no call reads is not a read', () {
      expect(sites("final s = 'STRIPE_KEY'; // STRIPE_KEY"), isEmpty);
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

  group('DV-SECRETS-003, what the prefix alone would ship', () {
    // The generator compiles every PUBLIC_-prefixed variable it finds in the
    // env files into env.g.dart, and that is the whole of the decision. So a
    // name somebody typed with the prefix -- copied from another project,
    // guessed at, or written before anyone thought about it -- reaches every
    // visitor with nothing having reviewed it. The declaration is described
    // as where the client opt-in is justified; this is what makes that true
    // rather than aspirational.
    test('a PUBLIC_ variable no declaration mentions is refused', () {
      final List<DVSecretFinding> findings = dvAnalysePublicEnvironment(
        declared: dvParseSecretDeclarations(_pubspec),
        file: '.env',
        contents: 'PUBLIC_ADMIN_TOKEN=at_9f2c4ab7\n',
      );

      expect(findings, hasLength(1));
      expect(findings.single.code, 'DV-SECRETS-003');
      expect(findings.single.file, '.env');
      expect(findings.single.message, contains('PUBLIC_ADMIN_TOKEN'));
      expect(findings.single.message, contains('dartvel.secrets'));
    });

    test('a declared client secret passes', () {
      expect(
        dvAnalysePublicEnvironment(
          declared: dvParseSecretDeclarations(_pubspec),
          file: '.env',
          contents: 'PUBLIC_STRIPE_KEY=pk_live_abc\n',
        ),
        isEmpty,
      );
    });

    test('a variable without the prefix is not reported', () {
      // It never reaches env.g.dart, so it never leaves the server. Flagging
      // it would turn a security diagnostic into a tidiness one, and those
      // get switched off together.
      expect(
        dvAnalysePublicEnvironment(
          declared: dvParseSecretDeclarations(_pubspec),
          file: '.env',
          contents: 'SOME_UNDECLARED_THING=value\n'
              'PAYSTACK_SECRET=sk_live_abc\n',
        ),
        isEmpty,
      );
    });

    test('the value never appears in the finding', () {
      // A diagnostic that prints the secret to persuade you it found one has
      // put it in the build log, where CI keeps it for everybody.
      final DVSecretFinding finding = dvAnalysePublicEnvironment(
        declared: dvParseSecretDeclarations(_pubspec),
        file: '.env.local',
        contents: 'PUBLIC_ADMIN_TOKEN=at_9f2c4ab7\n',
      ).single;

      expect(finding.toString(), isNot(contains('at_9f2c4ab7')));
      expect(finding.file, '.env.local');
    });

    test('comments and the export form are read the way the runtime reads them',
        () {
      // One parser, or the check and the generator disagree about what the
      // file even says.
      final List<DVSecretFinding> findings = dvAnalysePublicEnvironment(
        declared: dvParseSecretDeclarations(_pubspec),
        file: '.env',
        contents: '# PUBLIC_NOT_REAL=commented out\n'
            'export PUBLIC_SNEAKY=value_here\n',
      );

      expect(findings.map((DVSecretFinding f) => f.secret),
          <String>['PUBLIC_SNEAKY']);
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
