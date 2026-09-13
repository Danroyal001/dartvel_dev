// Sessions: the thing that carries every authenticated request.
//
// The silent failures are the ones worth the tests. A session identifier that
// survives a privilege change hands the elevated session to whoever planted
// the identifier (fixation). A revoked session that keeps authenticating until
// it expires is a sign-out that did nothing. A store that holds bearer tokens
// in the clear turns a database dump into every account. None of those throws;
// each looks exactly like working software.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  for (final (String name, DVSessionStore Function() makeStore)
      in <(String, DVSessionStore Function())>[
    ('memory', DVMemorySessionStore.new),
    ('in-memory database', () => DVDatabaseSessionStore(MemoryDVDatabaseAdapter())),
    ('sqlite', () => DVDatabaseSessionStore(SqliteDVDatabaseAdapter.memory())),
  ]) {
    group('sessions on the $name driver', () {
      late DateTime now;
      late DVSessionStore store;
      late DVSessions sessions;

      setUp(() {
        now = DateTime.utc(2026, 9, 13, 12);
        store = makeStore();
        sessions = DVSessions(
          store: store,
          idleTimeout: const Duration(days: 14),
          absoluteTimeout: const Duration(days: 30),
          clock: () => now,
        );
      });

      test('a created session authenticates with its token', () async {
        final DVIssuedSession issued = await sessions.create(
          'user-1',
          device: 'Pixel 9 · Android 16',
          claims: <String, Object?>{'role': 'member'},
        );

        final DVSession? session = await sessions.authenticate(issued.token);
        expect(session, isNotNull);
        expect(session!.userId, 'user-1');
        expect(session.device, 'Pixel 9 · Android 16');
        expect(session.claims, <String, Object?>{'role': 'member'});
        expect(session.mfaSatisfiedAt, isNull);
        expect(session.id, isNot(issued.token),
            reason: 'the listed id must not be the bearer secret, or listing '
                'a person\'s devices would hand out their other sessions');
      });

      test('an unknown token does not authenticate', () async {
        await sessions.create('user-1');
        expect(await sessions.authenticate('not-a-token'), isNull);
      });

      test('the store never holds a bearer token', () async {
        final DVIssuedSession issued = await sessions.create('user-1');
        final String dump = jsonEncode(await store.debugRows());
        expect(dump, isNot(contains(issued.token)),
            reason: 'a dump of the session table must not be a set of '
                'working credentials');
      });

      group('rotation', () {
        test('rotating issues a new token and kills the old one', () async {
          final DVIssuedSession first = await sessions.create('user-1');
          final DVIssuedSession second = await sessions.rotate(first.token);

          expect(second.token, isNot(first.token));
          expect(await sessions.authenticate(first.token), isNull,
              reason: 'a stable identifier across a boundary is fixation');
          expect(await sessions.authenticate(second.token), isNotNull);
        });

        test('elevating privilege rotates, and only the new token carries it',
            () async {
          final DVIssuedSession planted = await sessions.create('user-1',
              claims: <String, Object?>{'role': 'member'});
          final DVIssuedSession elevated = await sessions.elevate(
            planted.token,
            claims: <String, Object?>{'role': 'admin'},
          );

          expect(await sessions.authenticate(planted.token), isNull);
          final DVSession? session =
              await sessions.authenticate(elevated.token);
          expect(session!.claims['role'], 'admin');
        });

        test('completing a second factor rotates and records when', () async {
          final DVIssuedSession before = await sessions.create('user-1');
          now = now.add(const Duration(minutes: 3));
          final DVIssuedSession after = await sessions.completeMfa(before.token);

          expect(await sessions.authenticate(before.token), isNull);
          final DVSession? session = await sessions.authenticate(after.token);
          expect(session!.mfaSatisfiedAt, now);
        });

        test('rotation does not extend the absolute lifetime', () async {
          // Otherwise a session kept alive by rotating never ends, which is
          // exactly the session an attacker holding it would keep alive.
          DVIssuedSession issued = await sessions.create('user-1');
          for (int i = 0; i < 5; i++) {
            now = now.add(const Duration(days: 5));
            issued = await sessions.rotate(issued.token);
          }
          now = now.add(const Duration(days: 6));
          expect(await sessions.authenticate(issued.token), isNull,
              reason: '31 days after sign-in, however recently it rotated');
        });

        test('a revoked or unknown token cannot be rotated into life',
            () async {
          final DVIssuedSession issued = await sessions.create('user-1');
          await sessions.revoke(issued.session.id);
          expect(() => sessions.rotate(issued.token),
              throwsA(isA<DVSessionInvalid>()));
          expect(() => sessions.rotate('nothing'),
              throwsA(isA<DVSessionInvalid>()));
        });
      });

      group('revocation', () {
        test('a revoked session fails its very next request', () async {
          final DVIssuedSession issued = await sessions.create('user-1');
          expect(await sessions.authenticate(issued.token), isNotNull);

          await sessions.revoke(issued.session.id);

          final DVSessionCheck check = await sessions.check(issued.token);
          expect(check.session, isNull);
          expect(check.failure, DVSessionFailure.revoked);
          expect(check.code, 'DV-SESSION-002');
        });

        test('listing shows every device newest first and marks this one',
            () async {
          final DVIssuedSession laptop =
              await sessions.create('user-1', device: 'MacBook');
          now = now.add(const Duration(minutes: 1));
          final DVIssuedSession phone =
              await sessions.create('user-1', device: 'iPhone');
          await sessions.create('user-2', device: 'Somebody else');

          final List<DVSession> mine =
              await sessions.list('user-1', currentToken: laptop.token);
          expect(mine.map((DVSession s) => s.device), <String?>['iPhone', 'MacBook']);
          expect(mine.map((DVSession s) => s.isCurrent), <bool>[false, true]);
          expect(phone.session.userId, 'user-1');
        });

        test('revoking the others keeps this device signed in', () async {
          final DVIssuedSession here = await sessions.create('user-1');
          final DVIssuedSession there = await sessions.create('user-1');
          final DVIssuedSession elsewhere = await sessions.create('user-2');

          final int revoked = await sessions.revokeOthers(here.token);

          expect(revoked, 1);
          expect(await sessions.authenticate(here.token), isNotNull);
          expect(await sessions.authenticate(there.token), isNull);
          expect(await sessions.authenticate(elsewhere.token), isNotNull,
              reason: 'another person\'s sessions are not "the others"');
          expect(await sessions.list('user-1', currentToken: here.token),
              hasLength(1));
        });
      });

      group('expiry', () {
        test('an idle session expires, and use keeps it alive', () async {
          final DVIssuedSession used = await sessions.create('user-1');
          final DVIssuedSession idle = await sessions.create('user-1');

          for (int i = 0; i < 3; i++) {
            now = now.add(const Duration(days: 6));
            expect(await sessions.authenticate(used.token), isNotNull);
          }
          final DVSessionCheck check = await sessions.check(idle.token);
          expect(check.session, isNull);
          expect(check.failure, DVSessionFailure.expired);
        });

        test('even a session in constant use ends at the absolute lifetime',
            () async {
          final DVIssuedSession issued = await sessions.create('user-1');
          for (int day = 0; day < 30; day++) {
            now = now.add(const Duration(days: 1));
            await sessions.authenticate(issued.token);
          }
          now = now.add(const Duration(minutes: 1));
          expect(await sessions.authenticate(issued.token), isNull);
        });
      });

      group('multi-factor as policy', () {
        test('required is met by any second factor in this session', () async {
          final DVIssuedSession issued = await sessions.create('user-1');
          await expectLater(
            sessions.requireMfa(issued.token, DVMfa.required),
            throwsA(isA<DVMfaRequired>()
                .having((DVMfaRequired e) => e.code, 'code', 'DV-SESSION-001')),
          );

          final DVIssuedSession after = await sessions.completeMfa(issued.token);
          now = now.add(const Duration(days: 2));
          expect(await sessions.requireMfa(after.token, DVMfa.required),
              isA<DVSession>());
        });

        test('recent needs a second factor inside the window', () async {
          final DVIssuedSession issued = await sessions.create('user-1');
          final DVIssuedSession after = await sessions.completeMfa(issued.token);
          const DVMfa stepUp = DVMfa.recent(Duration(minutes: 15));

          now = now.add(const Duration(minutes: 14));
          expect(await sessions.requireMfa(after.token, stepUp), isA<DVSession>());

          now = now.add(const Duration(minutes: 2));
          await expectLater(sessions.requireMfa(after.token, stepUp),
              throwsA(isA<DVMfaRequired>()));
        });

        test('a caller with no valid session is refused, not waved through',
            () async {
          await expectLater(sessions.requireMfa('forged', DVMfa.none),
              throwsA(isA<DVSessionInvalid>()));
        });
      });
    });
  }

  group('the session cookie', () {
    test('production cookies are host-prefixed, HttpOnly, Secure and Lax', () {
      final String header =
          const DVSessionCookie().header('tok_abc', development: false);
      expect(header, startsWith('__Host-dv_session=tok_abc'));
      expect(header, contains('Path=/'));
      expect(header, contains('HttpOnly'));
      expect(header, contains('Secure'));
      expect(header, contains('SameSite=Lax'));
      expect(header, isNot(contains('Domain=')),
          reason: '__Host- forbids a Domain attribute');
    });

    test('development drops Secure and with it the host prefix', () {
      // A browser refuses a __Host- cookie without Secure, and localhost is
      // plain HTTP; the alternative is a session that silently never sets.
      final String header =
          const DVSessionCookie().header('tok_abc', development: true);
      expect(header, startsWith('dv_session=tok_abc'));
      expect(header, isNot(contains('Secure')));
      expect(header, contains('HttpOnly'));
    });

    test('a cross-site session is a configuration error, not a weaker cookie',
        () {
      expect(
        () => const DVSessionCookie(sameSite: 'None').header('t', development: false),
        throwsA(isA<DVSessionConfigError>()
            .having((DVSessionConfigError e) => e.code, 'code', 'DV-SESSION-003')),
      );
    });

    test('reading the cookie back finds the token among others', () {
      expect(
        const DVSessionCookie().read(
            'theme=dark; __Host-dv_session=tok_abc; other=1',
            development: false),
        'tok_abc',
      );
      expect(const DVSessionCookie().read('theme=dark', development: false),
          isNull);
    });

    test('revocation clears the cookie', () {
      final String header =
          const DVSessionCookie().clearHeader(development: false);
      expect(header, startsWith('__Host-dv_session=;'));
      expect(header, contains('Max-Age=0'));
    });
  });
}
