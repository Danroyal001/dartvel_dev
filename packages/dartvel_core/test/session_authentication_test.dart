// The application's own sessions, as the authentication stage of a request.
//
// DVSessions could issue, rotate and revoke a session, and nothing in a served
// request ever asked it: a request carrying the application's own session
// reached a route policy with no caller, because the server had no user to
// hand it. Only an API key or an OAuth token became a principal. This is the
// stage that turns a session credential into one.
//
// The silent failures, each of which still produces a plausible caller:
//  * a revoked, expired or rotated-away session still resolving to its user;
//  * a session issued on one tenant authenticating a request on another;
//  * a caller whose roles were read when the session was issued, so a person
//    demoted mid-session keeps acting with the old role;
//  * the application's other bearer tokens swallowed as sessions and refused;
//  * a session credential ignored because nothing was installed, which hands
//    the route a request its caller believes is authenticated.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Account {
  _Account(this.id, this.role);

  final String id;
  String role;
}

void main() {
  late DateTime now;
  late DVSessions sessions;
  late Map<String, _Account> accounts;
  late List<String> resolved;
  late DVSessionAuthentication auth;

  Future<T> onTenant<T>(String tenant, Future<T> Function() body) =>
      const DVTenants().withTenant(tenant, body);

  setUp(() {
    now = DateTime.utc(2026, 9, 15, 12);
    sessions = DVSessions(
      idleTimeout: const Duration(days: 14),
      absoluteTimeout: const Duration(days: 30),
      clock: () => now,
    );
    accounts = <String, _Account>{
      'u-admin': _Account('u-admin', 'admin'),
      'u-viewer': _Account('u-viewer', 'viewer'),
    };
    resolved = <String>[];
    auth = DVSessionAuthentication(
      sessions: sessions,
      resolveUser: (DVSession session) {
        resolved.add(session.userId);
        return accounts[session.userId];
      },
    );
  });

  tearDown(DVSessionAuthentication.uninstall);

  group('a session token', () {
    test('is shaped so the stage can tell it from the application\'s own',
        () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      expect(issued.token, startsWith(DVSessions.tokenPrefix));
      expect(DVSessions.tokenPrefix, 'dvs_');
    });

    test('records the tenant it was issued on, on every driver', () async {
      for (final DVSessionStore store in <DVSessionStore>[
        DVMemorySessionStore(),
        DVDatabaseSessionStore(MemoryDVDatabaseAdapter()),
        DVDatabaseSessionStore(SqliteDVDatabaseAdapter.memory()),
      ]) {
        final DVSessions onStore = DVSessions(store: store);
        final DVIssuedSession issued =
            await onTenant('acme', () => onStore.create('u-admin'));
        expect(issued.session.tenant, 'acme');
        final DVSession? read = await onStore.authenticate(issued.token);
        expect(read!.tenant, 'acme', reason: '${store.runtimeType}');
        final DVIssuedSession rotated = await onStore.rotate(issued.token);
        expect(rotated.session.tenant, 'acme',
            reason: 'rotation must not move a session to another tenant');
      }
    });
  });

  group('the authentication stage', () {
    test('resolves a bearer session to a caller with the user, tenant and id',
        () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));

      final DVSessionAuthenticationResult result = await onTenant(
          'acme', () => auth.authenticate(authorization: 'Bearer ${issued.token}'));

      expect(result.refused, isFalse);
      final DVSessionPrincipal principal = result.principal!;
      expect(principal.userId, 'u-admin');
      expect(principal.tenant, 'acme');
      expect(principal.session.id, issued.session.id);
      expect(principal.user, same(accounts['u-admin']));
      expect('$principal', isNot(contains(issued.token)));
    });

    test('resolves the session cookie under its host-prefixed name', () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));

      final DVSessionAuthenticationResult hosted = await onTenant(
          'acme',
          () => auth.authenticate(
              cookie: 'theme=dark; __Host-dv_session=${issued.token}'));
      expect(hosted.principal?.userId, 'u-admin');

      // Outside development the bare name is a cookie a sibling subdomain
      // could have planted; it is not the session.
      final DVSessionAuthenticationResult bare = await onTenant('acme',
          () => auth.authenticate(cookie: 'dv_session=${issued.token}'));
      expect(bare.principal, isNull);
      expect(bare.refused, isFalse);

      final DVSessionAuthentication development = DVSessionAuthentication(
          sessions: sessions, development: true);
      final DVSessionAuthenticationResult local = await onTenant('acme',
          () => development.authenticate(cookie: 'dv_session=${issued.token}'));
      expect(local.principal?.userId, 'u-admin');
    });

    test('leaves every other credential to whoever owns it', () async {
      for (final String? header in <String?>[
        null,
        'Bearer app-session-token',
        'Bearer dvk_0123456789abcdef_${'A' * 43}',
        'Bearer dvat_${'B' * 43}',
        'Basic dXNlcjpwYXNz',
      ]) {
        final DVSessionAuthenticationResult result =
            await onTenant('acme', () => auth.authenticate(authorization: header));
        expect(result.refused, isFalse, reason: '$header');
        expect(result.principal, isNull, reason: '$header');
      }
      expect(resolved, isEmpty);
    });

    Future<void> expectRefused(
      DVSessionAuthenticationResult result,
      String why,
    ) async {
      expect(result.principal, isNull, reason: why);
      expect(result.status, 401, reason: why);
      expect(result.challenge, 'Bearer error="invalid_token"', reason: why);
    }

    test('refuses a revoked session on its very next request', () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      await sessions.revoke(issued.session.id);

      await expectRefused(
          await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')),
          'revoked');
      expect(resolved, isEmpty,
          reason: 'a revoked session must not reach the user it belonged to');
    });

    test('refuses an expired session', () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      now = now.add(const Duration(days: 15));

      await expectRefused(
          await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')),
          'idle past its timeout');
    });

    test('refuses a token rotated away, and accepts the one that replaced it',
        () async {
      final DVIssuedSession first =
          await onTenant('acme', () => sessions.create('u-admin'));
      final DVIssuedSession second = await sessions.rotate(first.token);

      await expectRefused(
          await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${first.token}')),
          'rotated away');
      final DVSessionAuthenticationResult current = await onTenant(
          'acme', () => auth.authenticate(authorization: 'Bearer ${second.token}'));
      expect(current.principal?.userId, 'u-admin');
    });

    test('refuses a session issued on another tenant', () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));

      await expectRefused(
          await onTenant('globex',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')),
          'issued on acme, presented on globex');
      expect(resolved, isEmpty);
    });

    test('refuses a session whose user no longer exists', () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      accounts.remove('u-admin');

      await expectRefused(
          await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')),
          'deleted user');
    });

    test('clears the cookie when it refuses a session the cookie carried',
        () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      await sessions.revoke(issued.session.id);

      final DVSessionAuthenticationResult result = await onTenant('acme',
          () => auth.authenticate(cookie: '__Host-dv_session=${issued.token}'));
      expect(result.status, 401);
      expect(result.clearCookie, allOf(startsWith('__Host-dv_session='),
          contains('Max-Age=0')));

      final DVSessionAuthenticationResult bearer = await onTenant('acme',
          () => auth.authenticate(authorization: 'Bearer ${issued.token}'));
      expect(bearer.clearCookie, isNull);
    });

    test('reads the user again on every request, so a role change is seen',
        () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      Future<DVSessionPrincipal> caller() async => (await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')))
          .principal!;

      expect(((await caller()).user! as _Account).role, 'admin');
      accounts['u-admin'] = _Account('u-admin', 'viewer');
      expect(((await caller()).user! as _Account).role, 'viewer',
          reason: 'a demotion mid-session applies to the next request');
      expect(resolved, <String>['u-admin', 'u-admin']);
    });

    test('carries the membership of the organization on the request\'s tenant',
        () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final DVOrganizations organizations = DVOrganizations(database: db);
      await organizations.ensureSchema();
      await organizations.create(name: 'Acme', tenant: 'acme', ownerId: 'u-admin');
      final DVSessionAuthentication withOrganizations = DVSessionAuthentication(
        sessions: sessions,
        organizations: () => organizations,
      );
      final DVIssuedSession owner =
          await onTenant('acme', () => sessions.create('u-admin'));
      final DVIssuedSession outsider =
          await onTenant('acme', () => sessions.create('u-viewer'));

      final DVSessionPrincipal ownerCaller = (await onTenant('acme',
              () => withOrganizations.authenticate(
                  authorization: 'Bearer ${owner.token}')))
          .principal!;
      expect(ownerCaller.membership?.role.name, 'owner');

      Future<DVSessionPrincipal> outsiderCaller() async => (await onTenant(
              'acme',
              () => withOrganizations.authenticate(
                  authorization: 'Bearer ${outsider.token}')))
          .principal!;
      expect((await outsiderCaller()).membership, isNull);

      // Joined and then promoted while the session is live: each request
      // reads the membership as it is now.
      final DVOrganization acme = (await organizations.forTenant('acme'))!;
      await organizations.addMember(acme.id, 'u-viewer',
          role: organizations.roles['member'], actor: 'u-admin');
      expect((await outsiderCaller()).membership?.role.name, 'member');
      await organizations.changeRole(
          acme.id, 'u-viewer', organizations.roles['admin'],
          actor: 'u-admin');
      expect((await outsiderCaller()).membership?.role.name, 'admin');
    });
  });

  group('installed', () {
    test('a session credential with nothing installed is refused, not ignored',
        () async {
      DVSessionAuthentication.uninstall();
      final DVSessionAuthenticationResult result =
          await DVSessionAuthentication.authenticateRequest(
              authorization: 'Bearer dvs_${'C' * 43}');
      expect(result.status, 503);

      final DVSessionAuthenticationResult none =
          await DVSessionAuthentication.authenticateRequest();
      expect(none.refused, isFalse);
      expect(none.principal, isNull);
    });

    test('the installed stage answers, and its sessions are the ones issued',
        () async {
      DVSessionAuthentication.install(sessions: sessions);
      expect(DVSessionAuthentication.sessions, same(sessions));
      final DVIssuedSession issued =
          await onTenant('acme', () => DVSessionAuthentication.sessions.create('u-1'));
      final DVSessionAuthenticationResult result = await onTenant(
          'acme',
          () => DVSessionAuthentication.authenticateRequest(
              authorization: 'Bearer ${issued.token}'));
      expect(result.principal?.userId, 'u-1');
      expect(result.principal?.user, isNull,
          reason: 'with no resolver the caller is the session principal alone');
    });
  });

  group('the caller', () {
    test('is current for the request, and reaches an injected DVContext',
        () async {
      final DVIssuedSession issued =
          await onTenant('acme', () => sessions.create('u-admin'));
      final DVSessionPrincipal principal = (await onTenant('acme',
              () => auth.authenticate(authorization: 'Bearer ${issued.token}')))
          .principal!;

      expect(DVSessionPrincipal.current, isNull);
      expect(DVContext().session, isNull);
      await DVSessionPrincipal.actingAs(principal, () async {
        await Future<void>.delayed(Duration.zero);
        expect(DVSessionPrincipal.current, same(principal));
        final DVContext context = DVContext();
        expect(context.session, same(principal));
        expect(context.user, same(accounts['u-admin']));
        expect(context.apiPrincipal, isNull);
      });
      expect(DVSessionPrincipal.current, isNull);
    });
  });
}
