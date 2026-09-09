// `dartvel deploy` refusing to ship an environment that is missing a secret.
//
// The spec states it as a guarantee: "dartvel deploy refuses to ship when a
// declared secret required for the target environment does not resolve.
// Checked against the declaration, so a secret forgotten in a new environment
// fails the deploy rather than the first request that needs it."
//
// dvValidateEnvironment existed and nothing called it, so the guarantee was
// prose. The first request that needed the value was still where it failed.
import 'dart:io' as io;

import 'package:dartvel_cli/src/secrets/secrets_analysis.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _pubspec = '''
name: shop
dartvel:
  secrets:
    PAYSTACK_SECRET:
      scope: backend
      required: [production, staging]
    OPTIONAL_KEY:
      scope: backend
      required: []
''';

Map<String, DVSecretDeclaration> get _declared =>
    dvParseSecretDeclarations(_pubspec);

void main() {
  test('a missing required secret stops the deploy, naming it', () {
    final List<String> problems = dvValidateEnvironment(
      declared: _declared,
      environment: 'production',
      resolved: const <String>{},
    );

    expect(problems, hasLength(1));
    expect(problems.single, contains('PAYSTACK_SECRET'));
    expect(problems.single, contains('production'));
  });

  test('the message says what to do, not only what is wrong', () {
    // A deploy that stops without saying how to proceed gets worked around
    // with a flag rather than fixed.
    final String problem = dvValidateEnvironment(
      declared: _declared,
      environment: 'production',
      resolved: const <String>{},
    ).single;

    expect(problem, anyOf(contains('Set it'), contains('remove')));
  });

  test('an environment the secret is not required in is allowed through', () {
    // Development is not production. Requiring everything everywhere is how a
    // check gets disabled.
    expect(
      dvValidateEnvironment(
        declared: _declared,
        environment: 'development',
        resolved: const <String>{},
      ),
      isEmpty,
    );
  });

  test('an optional secret is never required anywhere', () {
    expect(
      dvValidateEnvironment(
        declared: _declared,
        environment: 'production',
        resolved: <String>{'PAYSTACK_SECRET'},
      ),
      isEmpty,
    );
  });

  test('problems are ordered, so two runs read the same', () {
    final Map<String, DVSecretDeclaration> many = dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    ZED:
      required: [production]
    ALPHA:
      required: [production]
    MID:
      required: [production]
''');

    final List<String> problems = dvValidateEnvironment(
      declared: many,
      environment: 'production',
      resolved: const <String>{},
    );

    expect(problems.map((String p) => p.split('"')[1]).toList(),
        <String>['ALPHA', 'MID', 'ZED']);
  });

  group('the gate resolves the way the running process will', () {
    late io.Directory tmp;

    setUp(() {
      DVSecrets.reset();
      tmp = io.Directory.systemTemp.createTempSync('dartvel_gate_');
    });

    tearDown(() {
      DVSecrets.reset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    String envFile(String contents) {
      final io.File file = io.File('${tmp.path}/.env')
        ..writeAsStringSync(contents);
      return file.path;
    }

    test('an export-prefixed line counts as resolved', () {
      // The gate used to parse .env with a reader of its own, and that
      // reader did not know the `export` form. So a secret the deployed
      // process resolves without trouble failed the gate, and the fix people
      // reach for when a gate is wrong is to stop trusting the gate.
      final Set<String> resolved = dvResolveSecrets(
        <String>['PAYSTACK_SECRET'],
        envFile: envFile('export PAYSTACK_SECRET=sk_live_from_the_file\n'),
      );

      expect(resolved, <String>{'PAYSTACK_SECRET'});
    });

    test('a blank assignment does not count as resolved', () {
      // The direction that ships. `KEY=` is what an unset variable looks
      // like coming through a shell, and treating it as present is how a
      // deploy goes out with an empty credential.
      final Set<String> resolved = dvResolveSecrets(
        <String>['PAYSTACK_SECRET'],
        envFile: envFile('PAYSTACK_SECRET=\n'),
      );

      expect(resolved, isEmpty);
    });

    test('a quoted value counts as resolved', () {
      final Set<String> resolved = dvResolveSecrets(
        <String>['PAYSTACK_SECRET'],
        envFile: envFile('PAYSTACK_SECRET="sk_live_quoted_value"\n'),
      );

      expect(resolved, <String>{'PAYSTACK_SECRET'});
    });

    test('a name in no source at all is missing', () {
      final Set<String> resolved = dvResolveSecrets(
        <String>['NEVER_SET_ANYWHERE'],
        envFile: envFile('SOMETHING_ELSE=value\n'),
      );

      expect(resolved, isEmpty);
    });

    test('a value the caller had configured survives the check', () {
      // The gate must clean up after itself without clearing state it did
      // not put there. Reaching for reset() takes the host process's own
      // configured values and rotation hooks with it, and the caller finds
      // out later, somewhere else.
      DVSecrets.configure(<String, String>{'HOST_SUPPLIED': 'still_here'});

      dvResolveSecrets(
        <String>['PAYSTACK_SECRET'],
        envFile: envFile('PAYSTACK_SECRET=sk_live_from_the_file\n'),
      );

      expect(const DVSecrets().maybeGet('HOST_SUPPLIED'), 'still_here');
    });

    test('resolving does not leave the secret loaded for the next caller', () {
      // The gate runs inside the same process that goes on to build and
      // write a deployment plan. A value left in the resolver after the
      // check is a value that can reach an artifact.
      dvResolveSecrets(
        <String>['PAYSTACK_SECRET'],
        envFile: envFile('PAYSTACK_SECRET=sk_live_from_the_file\n'),
      );

      expect(const DVSecrets().maybeGet('PAYSTACK_SECRET'), isNull);
    });
  });
}
