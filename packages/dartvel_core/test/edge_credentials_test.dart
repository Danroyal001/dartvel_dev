import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String sha1Hex(String password) =>
    sha1.convert(utf8.encode(password)).toString().toUpperCase();

/// A provider whose answers take time on a fake clock: an unknown account is
/// answered fast and a wrong password slowly, the oracle the guard must hide.
class SlowProvider implements AuthProvider {
  SlowProvider(this.inner, this.advance);

  final LocalAuthProvider inner;
  final void Function(Duration) advance;
  int signIns = 0;

  @override
  Future<AuthUser?> signIn(String email, String password) async {
    signIns++;
    final known = inner.accounts.contains(email.trim().toLowerCase());
    advance(Duration(milliseconds: known ? 250 : 20));
    return inner.signIn(email, password);
  }

  @override
  Future<AuthUser?> signUp(String email, String password, {String? name}) =>
      inner.signUp(email, password, name: name);

  @override
  Future<void> signOut() => inner.signOut();

  @override
  Future<AuthUser?> currentUser() => inner.currentUser();

  @override
  Stream<AuthUser?> get authStateChanges => inner.authStateChanges;
}

/// A provider written against the old contract, answering an unknown account
/// and a wrong password with different failures and different words.
class LeakyProvider implements AuthProvider {
  @override
  Future<AuthUser?> signIn(String email, String password) async {
    if (email == 'ada@x.com') {
      // ignore: deprecated_member_use_from_same_package
      throw const AuthException(AuthFailure.invalidPassword, 'Wrong password.');
    }
    // ignore: deprecated_member_use_from_same_package
    throw const AuthException(AuthFailure.unknownAccount, 'No such user.');
  }

  @override
  Future<AuthUser?> signUp(String email, String password, {String? name}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthUser?> currentUser() async => null;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream<AuthUser?>.empty();
}

void main() {
  late DateTime now;
  DateTime clock() => now;
  void advance(Duration by) => now = now.add(by);

  setUp(() => now = DateTime.utc(2026, 9, 14, 12));

  group('velocity limits', () {
    DVVelocityLimiter limiter({int account = 3, int source = 100}) =>
        DVVelocityLimiter(
          perAccount: DVVelocityBudget(account, const Duration(minutes: 15)),
          perSource: DVVelocityBudget(source, const Duration(minutes: 15)),
          clock: clock,
        );

    test('an account trips after its failures, whichever sources sent them',
        () async {
      final velocity = limiter();
      for (final source in <String>['10.0.0.1', '10.0.0.2', '10.0.0.3']) {
        expect(await velocity.check(account: 'ada@x.com', source: source),
            isNull);
        await velocity.recordFailure(account: 'ada@x.com', source: source);
      }
      final refusal =
          await velocity.check(account: 'ada@x.com', source: '10.0.0.4');
      expect(refusal, isNotNull);
      expect(refusal!.code, 'DV-EDGE-005');
      expect(refusal.scope, 'account');
    });

    test('one account however it is spelled', () async {
      final velocity = limiter();
      for (final spelling in <String>[' Ada@X.com', 'ada@x.com', 'ADA@x.com ']) {
        await velocity.recordFailure(account: spelling, source: 's');
      }
      expect(await velocity.check(account: 'ada@x.com', source: 's'),
          isNotNull);
    });

    test('a source spraying many accounts trips the per-source limit',
        () async {
      final velocity = limiter(source: 5);
      for (var i = 0; i < 5; i++) {
        await velocity.recordFailure(account: 'user$i@x.com', source: 'bot');
      }
      final refusal =
          await velocity.check(account: 'fresh@x.com', source: 'bot');
      expect(refusal?.scope, 'source');
      expect(await velocity.check(account: 'fresh@x.com', source: 'office'),
          isNull);
    });

    test('failures older than the window stop counting', () async {
      final velocity = limiter();
      for (var i = 0; i < 3; i++) {
        await velocity.recordFailure(account: 'ada@x.com', source: 's');
      }
      final refusal = await velocity.check(account: 'ada@x.com', source: 's');
      expect(refusal!.retryAfter, const Duration(minutes: 15));
      advance(const Duration(minutes: 15, seconds: 1));
      expect(await velocity.check(account: 'ada@x.com', source: 's'), isNull);
    });

    test('a success clears the account, not the source', () async {
      final velocity = limiter(account: 3, source: 3);
      await velocity.recordFailure(account: 'ada@x.com', source: 's');
      await velocity.recordFailure(account: 'ada@x.com', source: 's');
      await velocity.recordSuccess(account: 'ada@x.com');
      await velocity.recordFailure(account: 'ada@x.com', source: 'other');
      expect(await velocity.check(account: 'ada@x.com', source: 'other'),
          isNull);
      await velocity.recordFailure(account: 'grace@x.com', source: 's');
      expect(
        (await velocity.check(account: 'new@x.com', source: 's'))?.scope,
        'source',
      );
    });

    test('counts live in the store, so every instance sees them', () async {
      final store = DVMemoryVelocityStore();
      final a = DVVelocityLimiter(
          store: store,
          clock: clock,
          perAccount: const DVVelocityBudget(2, Duration(minutes: 5)));
      final b = DVVelocityLimiter(
          store: store,
          clock: clock,
          perAccount: const DVVelocityBudget(2, Duration(minutes: 5)));
      await a.recordFailure(account: 'ada@x.com', source: 's1');
      await a.recordFailure(account: 'ada@x.com', source: 's2');
      expect(await b.check(account: 'ada@x.com', source: 's3'), isNotNull);
    });
  });

  group('credential guard', () {
    late LocalAuthProvider local;
    late SlowProvider provider;
    late List<Duration> padded;

    DVCredentialGuard guard({
      DVVelocityLimiter? velocity,
      DVBreachedPasswords? breached,
      DVBotProtection? bots,
      bool breachCheckFailsClosed = false,
    }) =>
        DVCredentialGuard(
          provider: provider,
          velocity: velocity ??
              DVVelocityLimiter(
                perAccount: const DVVelocityBudget(2, Duration(minutes: 15)),
                clock: clock,
              ),
          breachedPasswords: breached,
          botProtection: bots,
          breachCheckFailsClosed: breachCheckFailsClosed,
          refusalFloor: const Duration(milliseconds: 400),
          clock: clock,
          delay: (duration) async {
            padded.add(duration);
            advance(duration);
          },
        );

    setUp(() async {
      local = LocalAuthProvider(hasher: DVPasswordHasher(iterations: 1));
      await local.signUp('ada@x.com', 'correct-horse');
      provider = SlowProvider(local, advance);
      padded = <Duration>[];
    });

    Future<(Object, Duration)> refusedSignIn(
      DVCredentialGuard guard,
      String email,
      String password,
    ) async {
      final started = now;
      try {
        await guard.signIn(email, password, source: '10.0.0.1');
      } catch (error) {
        return (error, now.difference(started));
      }
      fail('$email was signed in');
    }

    test('an unknown account and a wrong password are refused identically',
        () async {
      final g = guard();
      final (missing, missingTook) =
          await refusedSignIn(g, 'nobody@x.com', 'whatever-1');
      final (wrong, wrongTook) =
          await refusedSignIn(g, 'ada@x.com', 'wrong-horse');

      expect(missing, isA<AuthException>());
      expect(wrong, isA<AuthException>());
      expect((missing as AuthException).failure,
          (wrong as AuthException).failure);
      expect(missing.message, wrong.message);
      expect(missingTook, wrongTook,
          reason: 'a faster "no such user" is an enumeration oracle');
      expect(missingTook, const Duration(milliseconds: 400));
    });

    test('once the velocity limit trips, the refusal is the same for an '
        'existing and a missing account, and the password is not tried',
        () async {
      final g = guard();
      for (var i = 0; i < 2; i++) {
        await refusedSignIn(g, 'ada@x.com', 'wrong-horse');
        await refusedSignIn(g, 'nobody@x.com', 'wrong-horse');
      }
      final triedBefore = provider.signIns;

      final (existing, existingTook) =
          await refusedSignIn(g, 'ada@x.com', 'correct-horse');
      final (missing, missingTook) =
          await refusedSignIn(g, 'nobody@x.com', 'correct-horse');

      expect(existing, isA<DVVelocityRefusal>());
      expect(missing, isA<DVVelocityRefusal>());
      expect((existing as DVVelocityRefusal).message,
          (missing as DVVelocityRefusal).message);
      expect(existingTook, missingTook);
      expect(provider.signIns, triedBefore,
          reason: 'a locked account must not confirm the right password');
    });

    test('a success returns the user and clears the account counter',
        () async {
      final g = guard();
      await refusedSignIn(g, 'ada@x.com', 'wrong-horse');
      final user =
          await g.signIn('ada@x.com', 'correct-horse', source: '10.0.0.1');
      expect(user?.email, 'ada@x.com');
      await refusedSignIn(g, 'ada@x.com', 'wrong-horse');
      final again =
          await g.signIn('ada@x.com', 'correct-horse', source: '10.0.0.1');
      expect(again, isNotNull);
    });

    test('a guarded refusal is the refusal the provider itself gives',
        () async {
      Object? unguarded;
      try {
        await local.signIn('nobody@x.com', 'whatever-1');
      } catch (error) {
        unguarded = error;
      }
      final (guarded, _) = await refusedSignIn(guard(), 'nobody@x.com', 'x');
      expect((guarded as AuthException).failure,
          (unguarded as AuthException).failure);
      expect(guarded.message, unguarded.message);
    });

    test('a provider that still tells the two apart is collapsed by the guard',
        () async {
      final leaky = DVCredentialGuard(
        provider: LeakyProvider(),
        refusalFloor: const Duration(milliseconds: 400),
        clock: clock,
        delay: (duration) async => advance(duration),
      );
      final (missing, missingTook) =
          await refusedSignIn(leaky, 'nobody@x.com', 'x');
      final (wrong, wrongTook) = await refusedSignIn(leaky, 'ada@x.com', 'x');
      expect((missing as AuthException).failure,
          (wrong as AuthException).failure);
      expect(missing.message, wrong.message);
      expect(missingTook, wrongTook);
    });

    test('sign-ups that hit existing accounts count against the source, and '
        'never lock the account', () async {
      final g = guard(
        velocity: DVVelocityLimiter(
          perAccount: const DVVelocityBudget(2, Duration(minutes: 15)),
          perSource: const DVVelocityBudget(2, Duration(minutes: 15)),
          clock: clock,
        ),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          g.signUp('ada@x.com', 'another-phrase', source: 'prober'),
          throwsA(isA<AuthException>()
              .having((e) => e.failure, 'failure', AuthFailure.accountExists)),
        );
      }

      await expectLater(
        g.signUp('fresh@x.com', 'a-fresh-phrase', source: 'prober'),
        throwsA(isA<DVVelocityRefusal>()
            .having((r) => r.scope, 'scope', 'source')),
      );
      expect(local.accounts, isNot(contains('fresh@x.com')),
          reason: 'a refused source is not tried against the provider');

      expect(
        await g.signUp('fresh@x.com', 'a-fresh-phrase', source: 'office'),
        isNotNull,
      );
      expect(
        await g.signIn('ada@x.com', 'correct-horse', source: 'office'),
        isNotNull,
        reason: 'counting a taken address per account would make a lockout '
            'the oracle the refusal hides',
      );
    });

    test('a sign-up that creates an account does not count against the '
        'source', () async {
      final g = guard(
        velocity: DVVelocityLimiter(
          perSource: const DVVelocityBudget(1, Duration(minutes: 15)),
          clock: clock,
        ),
      );
      await g.signUp('one@x.com', 'a-fresh-phrase', source: 'office');
      await g.signUp('two@x.com', 'a-fresh-phrase', source: 'office');
      expect(local.accounts, containsAll(<String>['one@x.com', 'two@x.com']));
    });

    test('a breached password is refused at sign-up, before an account exists',
        () async {
      final g =
          guard(breached: DVMemoryBreachedPasswords(<String>['password123']));
      await expectLater(
        g.signUp('grace@x.com', 'password123', source: 's'),
        throwsA(isA<DVBreachedPasswordRefusal>()
            .having((r) => r.code, 'code', 'DV-EDGE-004')),
      );
      expect(local.accounts, isNot(contains('grace@x.com')));
      expect(await g.signUp('grace@x.com', 'a-fresh-phrase', source: 's'),
          isNotNull);
    });

    test('a breached password is refused on change', () async {
      final g =
          guard(breached: DVMemoryBreachedPasswords(<String>['password123']));
      await expectLater(g.checkNewPassword('password123'),
          throwsA(isA<DVBreachedPasswordRefusal>()));
      await g.checkNewPassword('a-fresh-phrase');
    });

    test('an unreachable breach service lets sign-up through unless told to '
        'fail closed', () async {
      final down = DVRangeQueryBreachedPasswords(
          (prefix) async => throw StateError('503'));
      expect(
        await guard(breached: down)
            .signUp('grace@x.com', 'a-fresh-phrase', source: 's'),
        isNotNull,
      );
      await expectLater(
        guard(breached: down, breachCheckFailsClosed: true)
            .signUp('linus@x.com', 'a-fresh-phrase', source: 's'),
        throwsA(isA<DVBreachedPasswordsUnavailable>()),
      );
      expect(local.accounts, isNot(contains('linus@x.com')));
    });

    test('sign-up needs a challenge the bot adapter accepts', () async {
      final g =
          guard(bots: DVTestBotProtection(acceptedTokens: <String>{'ok'}));
      await expectLater(g.signUp('grace@x.com', 'a-fresh-phrase', source: 's'),
          throwsA(isA<DVBotRefusal>()));
      await expectLater(
          g.signUp('grace@x.com', 'a-fresh-phrase',
              source: 's', challengeToken: 'forged'),
          throwsA(isA<DVBotRefusal>()));
      expect(local.accounts, isNot(contains('grace@x.com')));
      expect(
        await g.signUp('grace@x.com', 'a-fresh-phrase',
            source: 's', challengeToken: 'ok'),
        isNotNull,
      );
    });

    test('a bot adapter that fails refuses rather than letting a bot through',
        () async {
      final g = guard(
          bots: DVTestBotProtection(failWith: StateError('provider down')));
      await expectLater(
          g.signUp('grace@x.com', 'a-fresh-phrase',
              source: 's', challengeToken: 'ok'),
          throwsA(isA<DVBotRefusal>()));
    });
  });

  group('bot challenge middleware', () {
    test('refuses a request without an accepted challenge token', () async {
      final middleware = DVBotChallenge(
        DVTestBotProtection(acceptedTokens: <String>{'ok'}),
      ).middleware();
      Future<MiddlewareContext> run(Map<String, String> headers) async {
        final context = MiddlewareContext();
        await middleware(<String, Object?>{
          'method': 'POST',
          'path': '/register',
          'headers': headers,
        }, context);
        return context;
      }

      final missing = await run(const <String, String>{});
      expect(missing.shouldContinue, isFalse);
      expect(missing.data['botError'], isNotNull);
      expect(
          (await run(const <String, String>{'x-dv-challenge': 'nope'}))
              .shouldContinue,
          isFalse);
      expect(
          (await run(const <String, String>{'X-DV-Challenge': 'ok'}))
              .shouldContinue,
          isTrue);
    });
  });

  group('k-anonymity range query', () {
    const password = 'password123';

    test('only the first five characters of the hash leave the process',
        () async {
      final sent = <String>[];
      final checker = DVRangeQueryBreachedPasswords((prefix) async {
        sent.add(prefix);
        return '';
      });
      await checker.contains(password);
      expect(sent, <String>[sha1Hex(password).substring(0, 5)]);
    });

    test('a suffix in the range is a breach, whatever its case', () async {
      final suffix = sha1Hex(password).substring(5);
      final checker = DVRangeQueryBreachedPasswords((prefix) async =>
          '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n'
          '${suffix.toLowerCase()}:42\r\n');
      expect(await checker.contains(password), isTrue);
      expect(await checker.contains('something-else-entirely'), isFalse);
    });

    test('a padding entry with a count of zero is not a breach', () async {
      final suffix = sha1Hex(password).substring(5);
      final checker =
          DVRangeQueryBreachedPasswords((prefix) async => '$suffix:0\r\n');
      expect(await checker.contains(password), isFalse);
    });

    test('a range that is not a range is an error, not a clean bill',
        () async {
      final checker = DVRangeQueryBreachedPasswords(
          (prefix) async => '<html><body>Service unavailable</body></html>');
      await expectLater(checker.contains(password),
          throwsA(isA<DVBreachedPasswordsUnavailable>()));
    });

    group('over DV.Http', () {
      tearDown(DVHttp.reset);

      test('asks the endpoint for the prefix and reads the range', () async {
        final suffix = sha1Hex(password).substring(5);
        const DVHttp().fake(<String, DVHttpStub>{
          'range.example': DVHttpStub.text('$suffix:7\n'),
        });
        final asked = <String>[];
        final checker = DVRangeQueryBreachedPasswords.overHttp((prefix) {
          asked.add(prefix);
          return Uri.parse('https://range.example/range/$prefix');
        });
        expect(await checker.contains(password), isTrue);
        expect(asked.single, hasLength(5));
      });

      test('a failing service is an error, not a clean bill of health',
          () async {
        const DVHttp().fake(<String, DVHttpStub>{
          'range.example': DVHttpStub.status(503),
        });
        final checker = DVRangeQueryBreachedPasswords.overHttp(
            (prefix) => Uri.parse('https://range.example/range/$prefix'));
        await expectLater(checker.contains(password),
            throwsA(isA<DVBreachedPasswordsUnavailable>()));
      });
    });
  });
}
