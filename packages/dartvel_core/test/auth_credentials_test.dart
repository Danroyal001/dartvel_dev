import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVPasswordHasher', () {
    // Low iteration count keeps the suite fast; the algorithm is identical.
    final hasher = DVPasswordHasher(iterations: 1000);

    test('verifies the password it hashed', () {
      final encoded = hasher.hash('correct horse battery staple');
      expect(hasher.verify('correct horse battery staple', encoded), isTrue);
    });

    test('rejects a wrong password', () {
      final encoded = hasher.hash('correct horse battery staple');
      expect(hasher.verify('Correct horse battery staple', encoded), isFalse);
      expect(hasher.verify('', encoded), isFalse);
      expect(hasher.verify('correct horse battery stapl', encoded), isFalse);
    });

    test('salts each hash, so equal passwords differ on disk', () {
      final first = hasher.hash('same-password');
      final second = hasher.hash('same-password');

      expect(first, isNot(second));
      expect(hasher.verify('same-password', first), isTrue);
      expect(hasher.verify('same-password', second), isTrue);
    });

    test('never stores the password itself', () {
      final encoded = hasher.hash('super-secret-value');
      expect(encoded, isNot(contains('super-secret-value')));
    });

    test('encodes its parameters so old hashes stay verifiable', () {
      final weak = DVPasswordHasher(iterations: 500).hash('pw');
      expect(weak, startsWith(r'pbkdf2-sha256$500$'));

      // A hasher configured with different iterations still verifies it,
      // because the count travels with the hash.
      expect(DVPasswordHasher(iterations: 9000).verify('pw', weak), isTrue);
    });

    test('flags hashes weaker than the current configuration', () {
      final weak = DVPasswordHasher(iterations: 500).hash('pw');
      expect(DVPasswordHasher(iterations: 9000).needsRehash(weak), isTrue);
      expect(DVPasswordHasher(iterations: 500).needsRehash(weak), isFalse);
    });

    test('treats a corrupt or foreign hash as a failed verification', () {
      for (final corrupt in <String>[
        '',
        'not-a-hash',
        r'pbkdf2-sha256$1000$notbase64!!$notbase64!!',
        r'bcrypt$1000$c2FsdA==$aGFzaA==',
        r'pbkdf2-sha256$0$c2FsdA==$aGFzaA==',
        r'pbkdf2-sha256$abc$c2FsdA==$aGFzaA==',
      ]) {
        expect(hasher.verify('anything', corrupt), isFalse,
            reason: 'must not accept "$corrupt"');
      }
    });

    test('rejects a nonsensical iteration count at construction', () {
      expect(() => DVPasswordHasher(iterations: 0), throwsArgumentError);
    });
  });

  group('LocalAuthProvider', () {
    late LocalAuthProvider auth;

    setUp(() {
      auth = LocalAuthProvider(hasher: DVPasswordHasher(iterations: 1000));
    });

    test('signs in an account that was registered', () async {
      final created = await auth.signUp(
        'ada@example.com',
        'lovelace-1843',
        name: 'Ada',
      );
      expect(created!.email, 'ada@example.com');
      expect(created.name, 'Ada');

      await auth.signOut();
      expect(await auth.currentUser(), isNull);

      final signedIn = await auth.signIn('ada@example.com', 'lovelace-1843');
      expect(signedIn!.id, created.id, reason: 'the same account comes back');
      expect(await auth.currentUser(), isNotNull);
    });

    test('rejects a wrong password', () async {
      await auth.signUp('ada@example.com', 'lovelace-1843');
      await auth.signOut();

      await expectLater(
        auth.signIn('ada@example.com', 'not-the-password'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.failure,
            'failure',
            AuthFailure.invalidPassword,
          ),
        ),
      );
      expect(await auth.currentUser(), isNull);
    });

    test('rejects an account that was never registered', () async {
      await expectLater(
        auth.signIn('nobody@example.com', 'any-password-at-all'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.failure,
            'failure',
            AuthFailure.unknownAccount,
          ),
        ),
      );
    });

    test('will not silently overwrite an existing account', () async {
      await auth.signUp('ada@example.com', 'lovelace-1843');

      await expectLater(
        auth.signUp('ADA@example.com', 'a-different-password'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.failure,
            'failure',
            AuthFailure.accountExists,
          ),
        ),
      );

      // The original password still works — the second signUp changed nothing.
      await auth.signOut();
      expect(
        (await auth.signIn('ada@example.com', 'lovelace-1843'))!.email,
        'ada@example.com',
      );
    });

    test('rejects weak passwords and malformed e-mail addresses', () async {
      await expectLater(
        auth.signUp('ada@example.com', 'short'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.failure,
            'failure',
            AuthFailure.weakPassword,
          ),
        ),
      );
      for (final bad in <String>['ada', '@example.com', 'ada@']) {
        await expectLater(
          auth.signUp(bad, 'long-enough-password'),
          throwsA(
            isA<AuthException>().having(
              (error) => error.failure,
              'failure',
              AuthFailure.invalidEmail,
            ),
          ),
          reason: '"$bad" is not a valid address',
        );
      }
      expect(auth.accounts, isEmpty);
    });

    test('normalises e-mail case and surrounding whitespace', () async {
      await auth.signUp('  Ada@Example.COM  ', 'lovelace-1843');
      expect(auth.accounts, <String>['ada@example.com']);

      await auth.signOut();
      expect(
        (await auth.signIn('ADA@EXAMPLE.COM', 'lovelace-1843'))!.email,
        'ada@example.com',
      );
    });

    test('gives each account a distinct id', () async {
      final first = await auth.signUp('a@example.com', 'password-one');
      final second = await auth.signUp('b@example.com', 'password-two');
      expect(first!.id, isNot(second!.id));
    });

    test('emits auth state changes for sign in and sign out', () async {
      final seen = <String?>[];
      final subscription =
          auth.authStateChanges.listen((user) => seen.add(user?.email));
      addTearDown(subscription.cancel);

      await auth.signUp('ada@example.com', 'lovelace-1843');
      await auth.signOut();
      await auth.signIn('ada@example.com', 'lovelace-1843');
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String?>['ada@example.com', null, 'ada@example.com']);
    });

    test('reset clears every account', () async {
      await auth.signUp('ada@example.com', 'lovelace-1843');
      auth.reset();

      expect(auth.accounts, isEmpty);
      expect(await auth.currentUser(), isNull);
      await expectLater(
        auth.signIn('ada@example.com', 'lovelace-1843'),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
