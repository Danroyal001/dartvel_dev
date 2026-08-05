// Prefixed: dartvel_core exports its own `Platform`, which would shadow this.
import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVSecrets', () {
    const DVSecrets secrets = DVSecrets();

    tearDown(DVSecrets.reset);

    test('reads the process environment', () {
      // PATH is set for every process that can run this test, so it exercises
      // the real environment read rather than a stand-in.
      final expected = io.Platform.environment['PATH'];
      expect(expected, isNotNull, reason: 'test host has no PATH');

      expect(secrets.get('PATH'), expected);
      expect(secrets.has('PATH'), isTrue);
    });

    test('configure takes precedence over the environment', () {
      DVSecrets.configure(<String, String>{'PATH': 'configured'});

      expect(secrets.get('PATH'), 'configured');
    });

    test('reset drops configured secrets', () {
      DVSecrets.configure(<String, String>{'PAYSTACK_SECRET': 'sk_test'});
      expect(secrets.get('PAYSTACK_SECRET'), 'sk_test');

      DVSecrets.reset();

      expect(secrets.maybeGet('PAYSTACK_SECRET'), isNull);
    });

    test('a missing secret names the key and how to supply it', () {
      expect(
        () => secrets.get('DARTVEL_NOT_SET_SECRET'),
        throwsA(
          isA<DVSecretNotFoundException>()
              .having((DVSecretNotFoundException e) => e.key, 'key',
                  'DARTVEL_NOT_SET_SECRET')
              .having((DVSecretNotFoundException e) => e.toString(), 'message',
                  contains('DVSecrets.configure')),
        ),
      );
    });

    test('an empty value counts as absent', () {
      // A variable unset through a shell commonly arrives as '', and a client
      // configured with '' fails far away from the cause.
      DVSecrets.configure(<String, String>{'EMPTY_SECRET': ''});

      expect(secrets.has('EMPTY_SECRET'), isFalse);
      expect(secrets.maybeGet('EMPTY_SECRET'), isNull);
      expect(() => secrets.get('EMPTY_SECRET'),
          throwsA(isA<DVSecretNotFoundException>()));
    });

    test('getOr falls back only when the secret is absent', () {
      DVSecrets.configure(<String, String>{'PRESENT': 'value'});

      expect(secrets.getOr('PRESENT', 'fallback'), 'value');
      expect(secrets.getOr('ABSENT', 'fallback'), 'fallback');
    });
  });
}
