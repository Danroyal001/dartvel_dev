// What a module may ask for, and what a parent's grant actually covers.
//
// Every assertion here is about a grant that would look right and cover the
// wrong thing: a domain granted by suffix, a secret granted case-blind, a
// `network: true` that makes every other grant decorative, a malformed value
// read as permission.
import 'package:dartvel_cli/src/module_trust/capabilities.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

DVCapabilityParse parse(String yaml) =>
    dvParseModuleCapabilities(loadYaml(yaml), where: 'grant');

void main() {
  group('reading a declaration or a grant', () {
    test('nothing written is nothing granted', () {
      final DVCapabilityParse result = dvParseModuleCapabilities(
        null,
        where: 'grant',
      );
      expect(result.problems, isEmpty);
      expect(result.capabilities.isEmpty, isTrue);
    });

    test('every capability in the table is read', () {
      final DVCapabilityParse result = parse('''
secrets: [STRIPE_KEY]
rawSql: true
nativeBindings: true
egress: ['api.stripe.com']
filesystem: [uploads]
cron: true
''');
      expect(result.problems, isEmpty);
      expect(result.capabilities.items(), <String>[
        'secrets: STRIPE_KEY',
        'rawSql',
        'nativeBindings',
        'egress: api.stripe.com',
        'filesystem: uploads',
        'cron',
      ]);
      expect(result.capabilities.kinds, <String>[
        'secrets',
        'rawSql',
        'nativeBindings',
        'egress',
        'filesystem',
        'cron',
      ]);
    });

    test('network: true is refused, because per domain or not at all', () {
      final DVCapabilityParse result = parse('network: true\n');
      expect(result.problems.join('\n'), contains('network'));
      expect(result.problems.join('\n'), contains('egress'));
      expect(result.capabilities.isEmpty, isTrue);
    });

    test('an unknown capability is refused by name, not ignored', () {
      final DVCapabilityParse result = parse('keychain: true\n');
      expect(result.problems.join('\n'), contains('keychain'));
    });

    test('a flag that is not true or false grants nothing', () {
      // `rawSql: yes-please` reading as true is a grant nobody wrote.
      final DVCapabilityParse result = parse('rawSql: "yes"\ncron: 1\n');
      expect(result.problems, hasLength(2));
      expect(result.capabilities.rawSql, isFalse);
      expect(result.capabilities.cron, isFalse);
    });

    test(
      'a wildcard domain is refused: it is network: true spelled longer',
      () {
        for (final String domain in <String>[
          '*',
          '*.stripe.com',
          'https://api.stripe.com',
          'api.stripe.com/v1',
          'api.stripe.com:443',
          '',
          '.stripe.com',
          'api stripe.com',
        ]) {
          final DVCapabilityParse result = parse("egress: ['$domain']\n");
          expect(result.problems, isNotEmpty, reason: '"$domain" was accepted');
          expect(
            result.capabilities.egress,
            isEmpty,
            reason: '"$domain" was granted',
          );
        }
      },
    );

    test('a domain is compared as DNS compares it, case-blind', () {
      final DVCapabilityParse result = parse("egress: ['API.Stripe.COM']\n");
      expect(result.problems, isEmpty);
      expect(result.capabilities.egress, <String>{'api.stripe.com'});
    });

    test('secrets, egress and filesystem are lists even with one entry', () {
      final DVCapabilityParse result = parse(
        'secrets: STRIPE_KEY\negress: api.stripe.com\n',
      );
      expect(result.problems, hasLength(2));
      expect(result.capabilities.isEmpty, isTrue);
    });
  });

  group('what a grant does not cover', () {
    DVModuleCapabilities caps(String yaml) => parse(yaml).capabilities;

    test('a granted domain does not cover its subdomains', () {
      final List<String> missing = caps(
        "egress: ['api.stripe.com']\n",
      ).missingFrom(caps("egress: ['stripe.com']\n"));
      expect(missing, <String>['egress: api.stripe.com']);
    });

    test('nor a longer host that happens to end with it', () {
      final List<String> missing = caps(
        "egress: ['api.stripe.com.evil.example']\n",
      ).missingFrom(caps("egress: ['api.stripe.com']\n"));
      expect(missing, <String>['egress: api.stripe.com.evil.example']);
    });

    test('nor a host that merely starts with it', () {
      final List<String> missing = caps(
        "egress: ['evilapi.stripe.com']\n",
      ).missingFrom(caps("egress: ['api.stripe.com']\n"));
      expect(missing, <String>['egress: evilapi.stripe.com']);
    });

    test('a secret name is exact, case included', () {
      final List<String> missing = caps(
        'secrets: [STRIPE_KEY]\n',
      ).missingFrom(caps('secrets: [stripe_key]\n'));
      expect(missing, <String>['secrets: STRIPE_KEY']);
    });

    test('a secret grant is the key, not the namespace', () {
      final List<String> missing = caps(
        'secrets: [STRIPE_KEY_LIVE]\n',
      ).missingFrom(caps('secrets: [STRIPE_KEY]\n'));
      expect(missing, <String>['secrets: STRIPE_KEY_LIVE']);
    });

    test('everything asked for and granted leaves nothing missing', () {
      final DVModuleCapabilities both = caps(
        "secrets: [A]\nrawSql: true\negress: ['a.example']\n",
      );
      expect(both.missingFrom(both), isEmpty);
    });

    test('flags are covered only by the same flag', () {
      expect(caps('rawSql: true\n').missingFrom(caps('cron: true\n')), <String>[
        'rawSql',
      ]);
    });
  });

  test('the canonical form round-trips and is order-independent', () {
    final DVModuleCapabilities a = parse(
      "egress: ['b.example', 'a.example']\nsecrets: [Z, A]\nrawSql: true\n",
    ).capabilities;
    final DVModuleCapabilities b = parse(
      "rawSql: true\nsecrets: [A, Z]\negress: ['a.example', 'b.example']\n",
    ).capabilities;
    expect(a.toJson(), b.toJson());
    expect(DVModuleCapabilities.fromJson(a.toJson()), a);
    expect(a, b);
  });
}
