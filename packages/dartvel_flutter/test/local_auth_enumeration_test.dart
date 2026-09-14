import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts the hashing work the provider does, so equal work is asserted by
/// counting rather than by a stopwatch that a busy machine makes flaky.
class CountingHasher extends DVPasswordHasher {
  CountingHasher({this.match = false}) : super(iterations: 1000);

  /// Accept every password: a dummy hash that happens to match must still
  /// not sign anybody in.
  final bool match;

  int hashes = 0;
  int verifies = 0;

  void clear() {
    hashes = 0;
    verifies = 0;
  }

  @override
  String hash(String password) {
    hashes++;
    return super.hash(password);
  }

  @override
  bool verify(String password, String encoded) {
    verifies++;
    return match || super.verify(password, encoded);
  }
}

Future<AuthException> refusal(
  DVLocalAuthProvider provider,
  String email,
  String password,
) async {
  try {
    await provider.signInWithEmailAndPassword(email: email, password: password);
  } on AuthException catch (error) {
    return error;
  }
  fail('$email was signed in');
}

void main() {
  group('DVLocalAuthProvider does not reveal which e-mails have accounts', () {
    test('an unknown account fails exactly as a wrong password does',
        () async {
      final provider = DVLocalAuthProvider(hasher: CountingHasher());
      await provider.signUp(email: 'ada@example.com', password: 'lovelace-1843');

      final missing =
          await refusal(provider, 'nobody@example.com', 'lovelace-1843');
      final wrong = await refusal(provider, 'ada@example.com', 'not-it-at-all');

      expect(missing.failure, wrong.failure);
      expect(missing.message, wrong.message);
      expect(missing.toString(), wrong.toString());
    });

    test('an unknown account costs one verification and no hashing, the same '
        'work as a wrong password', () async {
      final hasher = CountingHasher();
      final provider = DVLocalAuthProvider(hasher: hasher);
      await provider.signUp(email: 'ada@example.com', password: 'lovelace-1843');

      hasher.clear();
      await refusal(provider, 'nobody@example.com', 'lovelace-1843');
      final (missingHashes, missingVerifies) = (hasher.hashes, hasher.verifies);

      hasher.clear();
      await refusal(provider, 'ada@example.com', 'not-it-at-all');

      expect(missingVerifies, 1);
      expect(missingHashes, 0,
          reason: 'hashing on every miss doubles the work a miss costs');
      expect((missingHashes, missingVerifies), (hasher.hashes, hasher.verifies));
    });

    test('an unknown account is refused even if the dummy hash matched',
        () async {
      final provider = DVLocalAuthProvider(hasher: CountingHasher(match: true));
      await expectLater(
        provider.signInWithEmailAndPassword(
          email: 'nobody@example.com',
          password: 'anything-at-all',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('a weak password is reported before whether the address is taken',
        () async {
      final provider = DVLocalAuthProvider(hasher: CountingHasher());
      await provider.signUp(email: 'ada@example.com', password: 'lovelace-1843');

      await expectLater(
        provider.signUp(email: 'ada@example.com', password: 'short'),
        throwsA(isA<AuthException>()
            .having((e) => e.failure, 'failure', AuthFailure.weakPassword)),
        reason: 'validation that depends on the account existing is an oracle '
            'a single request can read',
      );
    });

    test('signing up an existing address hashes the password as a new one '
        'does', () async {
      final hasher = CountingHasher();
      final provider = DVLocalAuthProvider(hasher: hasher);
      await provider.signUp(email: 'ada@example.com', password: 'lovelace-1843');

      hasher.clear();
      await provider.signUp(email: 'grace@example.com', password: 'hopper-1906');
      final fresh = hasher.hashes;

      hasher.clear();
      await expectLater(
        provider.signUp(email: 'ada@example.com', password: 'another-password'),
        throwsA(isA<AuthException>()),
      );
      expect(hasher.hashes, fresh);
    });
  });
}
