// `dartvel deploy` refusing to ship an environment that is missing a secret.
//
// The spec states it as a guarantee: "dartvel deploy refuses to ship when a
// declared secret required for the target environment does not resolve.
// Checked against the declaration, so a secret forgotten in a new environment
// fails the deploy rather than the first request that needs it."
//
// dvValidateEnvironment existed and nothing called it, so the guarantee was
// prose. The first request that needed the value was still where it failed.
import 'package:dartvel_cli/src/secrets/secrets_analysis.dart';
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
}
