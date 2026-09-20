// Managing API keys and OAuth clients through DV.Auth, authorized by
// DV.Auth.authorization, for the organization on the current tenant.
//
// DVApiKeys and DVOAuthProvider issue, rotate and revoke for whoever calls
// them: they take an organization and an id and ask nobody. An application
// wiring a settings page straight to them has a key-issuing endpoint anybody
// signed in can use, for any organization whose id they can guess. The
// facade is where "who may" is asked, so the failures worth a test are the
// silent ones:
//  * a key issued with no policy registered, because nothing asked;
//  * a key or client of another organization rotated, revoked or listed by
//    naming its id from this tenant;
//  * a refused issue that still wrote a key;
//  * a policy that never sees what is being asked for (the scopes), and so
//    cannot refuse a wide one;
//  * a rate plan misspelt at issue, which would be refused on every call
//    rather than when somebody could fix it;
//  * a third-party key managing keys because a policy said yes to its
//    organization.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class User {
  const User(this.id, {this.admin = false});

  final String id;
  final bool admin;
}

void main() {
  late MemoryDVDatabaseAdapter db;
  // Two tenants: a key's only boundary.
  const String acme = 'acme';
  const String globex = 'globex';
  final List<List<String>> askedScopes = <List<String>>[];

  const User admin = User('ada', admin: true);
  const User member = User('bob');

  const DVTestHarness harness = DVTestHarness();

  void registerPolicies() {
    const DVAuthAuthorization authz = DVAuthAuthorization();
    authz.register<User, DVApiKeyResource>('create', (User u, DVApiKeyResource r) {
      askedScopes.add(r.scopes);
      return u.admin && !r.scopes.contains('orders:write');
    });
    authz.register<User, DVApiKeyResource>('viewAny', (User u, _) => u.admin);
    authz.register<User, DVApiKeyResource>('update', (User u, _) => u.admin);
    authz.register<User, DVApiKeyResource>('delete', (User u, _) => u.admin);
    authz.register<User, DVOAuthClientResource>(
      'create',
      (User u, DVOAuthClientResource r) => u.admin,
    );
    authz.register<User, DVOAuthClientResource>('viewAny', (User u, _) => u.admin);
    authz.register<User, DVOAuthClientResource>('delete', (User u, _) => u.admin);
  }

  setUp(() async {
    harness.resetPolicies();
    askedScopes.clear();
    db = MemoryDVDatabaseAdapter();
    DVPlatformApi.install(
      DVPlatformApiConfig.fromConfig(<String, Object?>{
        'scopes': <String, Object?>{
          'orders:read': <String>['Order.view'],
          'orders:write': <String>['Order.create'],
        },
        'ratePlans': <String, Object?>{
          'standard': <String, Object?>{'maxRequests': 10, 'window': '1m'},
        },
        'oauth': true,
      }),
      database: () => db,
    );
    registerPolicies();
  });

  tearDown(() {
    DVPlatformApi.uninstall();
    harness.resetPolicies();
  });

  Future<T> onTenant<T>(String tenant, Future<T> Function() body) =>
      const DVTenants().withTenant(tenant, body);

  const DVPlatformApiAuth platform = DVPlatformApiAuth();

  group('API keys', () {
    test('an allowed person issues a key for the organization on the current '
        'tenant, and it authenticates there', () async {
      final DVIssuedApiKey issued = await onTenant(
        'acme',
        () => platform.apiKeys.issue(
          user: admin,
          actor: admin.id,
          scopes: <String>['orders:read'],
          expiresIn: const Duration(days: 30),
          ratePlan: 'standard',
        ),
      );
      expect(issued.key.tenant, acme);
      expect(issued.key.createdBy, 'ada');
      expect(askedScopes, <List<String>>[
        <String>['orders:read'],
      ]);
      final DVApiKeys keys = await DVPlatformApi.installed!.keys();
      expect(await keys.authenticate(issued.secret, tenant: 'acme'), isNotNull);
    });

    test('nothing is issued when no policy is registered', () async {
      harness.resetPolicies();
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: admin,
            actor: admin.id,
            scopes: <String>['orders:read'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
      final DVApiKeys keys = await DVPlatformApi.installed!.keys();
      expect(await keys.forTenant(acme), isEmpty);
    });

    test('a refused issue writes no key, and the policy saw the scopes',
        () async {
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: member,
            actor: member.id,
            scopes: <String>['orders:read'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: admin,
            actor: admin.id,
            scopes: <String>['orders:write'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(askedScopes.last, <String>['orders:write']);
      final DVApiKeys keys = await DVPlatformApi.installed!.keys();
      expect(await keys.forTenant(acme), isEmpty);
    });

    test('nobody signed in manages nothing', () async {
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: null,
            actor: null,
            scopes: <String>['orders:read'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a rate plan the declaration does not have is refused at issue',
        () async {
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: admin,
            actor: admin.id,
            scopes: <String>['orders:read'],
            ratePlan: 'standrad',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a list holds the current organization\'s keys only', () async {
      await onTenant(
        'acme',
        () => platform.apiKeys.issue(
          user: admin,
          actor: admin.id,
          scopes: <String>['orders:read'],
        ),
      );
      await onTenant(
        'globex',
        () => platform.apiKeys.issue(
          user: admin,
          actor: admin.id,
          scopes: <String>['orders:read'],
        ),
      );
      final List<DVApiKey> listed = await onTenant(
        'acme',
        () => platform.apiKeys.list(user: admin),
      );
      expect(listed.map((DVApiKey k) => k.tenant), <String>[acme]);
      await expectLater(
        onTenant('acme', () => platform.apiKeys.list(user: member)),
        throwsA(isA<StateError>()),
      );
    });

    test('another organization\'s key cannot be rotated or revoked from this '
        'tenant, and keeps working', () async {
      final DVIssuedApiKey theirs = await onTenant(
        'globex',
        () => platform.apiKeys.issue(
          user: admin,
          actor: admin.id,
          scopes: <String>['orders:read'],
        ),
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.revoke(theirs.key.id, user: admin, actor: 'ada'),
        ),
        throwsA(isA<DVApiKeyNotLive>()),
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.rotate(theirs.key.id, user: admin, actor: 'ada'),
        ),
        throwsA(isA<DVApiKeyNotLive>()),
      );
      final DVApiKeys keys = await DVPlatformApi.installed!.keys();
      expect(await keys.authenticate(theirs.secret, tenant: 'globex'), isNotNull);
      expect(await keys.forTenant(globex), hasLength(1));
    });

    test('rotation overlaps and revocation is immediate, each authorized',
        () async {
      final DVIssuedApiKey first = await onTenant(
        'acme',
        () => platform.apiKeys.issue(
          user: admin,
          actor: admin.id,
          scopes: <String>['orders:read'],
        ),
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.rotate(first.key.id, user: member, actor: 'bob'),
        ),
        throwsA(isA<StateError>()),
      );
      final DVIssuedApiKey second = await onTenant(
        'acme',
        () => platform.apiKeys.rotate(first.key.id, user: admin, actor: 'ada'),
      );
      final DVApiKeys keys = await DVPlatformApi.installed!.keys();
      expect(await keys.authenticate(first.secret, tenant: 'acme'), isNotNull);
      expect(await keys.authenticate(second.secret, tenant: 'acme'), isNotNull);
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.revoke(second.key.id, user: member, actor: 'bob'),
        ),
        throwsA(isA<StateError>()),
      );
      await onTenant(
        'acme',
        () => platform.apiKeys.revoke(second.key.id, user: admin, actor: 'ada'),
      );
      expect(await keys.authenticate(second.secret, tenant: 'acme'), isNull);
    });

    test('a third-party key is refused by its scopes before any policy',
        () async {
      final DVApiPrincipal partner = DVApiPrincipal(
        kind: DVApiPrincipalKind.apiKey,
        subject: '0123456789abcdef',
        tenant: 'acme',
        scopes: <String>{'orders:read'},
        actions: <String>{'Order.view'},
      );
      const DVAuthAuthorization().register<DVApiPrincipal, DVApiKeyResource>(
        'create',
        (DVApiPrincipal p, _) => true,
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.apiKeys.issue(
            user: partner,
            actor: partner.subject,
            scopes: <String>['orders:read'],
          ),
        ),
        throwsA(isA<DVApiScopeRefused>()),
      );
    });
  });

  group('OAuth clients', () {
    test('an allowed person registers a client for the current organization',
        () async {
      final DVRegisteredOAuthClient registered = await onTenant(
        'acme',
        () => platform.oauthClients.register(
          user: admin,
          actor: admin.id,
          name: 'Partner',
          redirectUris: <String>['https://partner.example/cb'],
          scopes: <String>['orders:read'],
        ),
      );
      expect(registered.client.id, startsWith('dvc_'));
      expect(registered.secret, startsWith('dvcs_'));
      await expectLater(
        onTenant(
          'acme',
          () => platform.oauthClients.register(
            user: member,
            actor: member.id,
            name: 'Partner 2',
            redirectUris: <String>['https://partner.example/cb'],
            scopes: <String>['orders:read'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
      final List<DVOAuthClient> listed = await onTenant(
        'acme',
        () => platform.oauthClients.list(user: admin),
      );
      expect(listed.map((DVOAuthClient c) => c.name), <String>['Partner']);
    });

    test('another organization\'s client cannot be revoked from this tenant',
        () async {
      final DVRegisteredOAuthClient theirs = await onTenant(
        'globex',
        () => platform.oauthClients.register(
          user: admin,
          actor: admin.id,
          name: 'Globex partner',
          redirectUris: <String>['https://globex.example/cb'],
          scopes: <String>['orders:read'],
        ),
      );
      await expectLater(
        onTenant(
          'acme',
          () => platform.oauthClients.revoke(
            theirs.client.id,
            user: admin,
            actor: 'ada',
          ),
        ),
        throwsA(isA<StateError>()),
      );
      final DVOAuthProvider provider =
          (await DVPlatformApi.installed!.oauthProvider())!;
      expect((await provider.findClient(theirs.client.id))!.revokedAt, isNull);
      await onTenant(
        'globex',
        () => platform.oauthClients.revoke(
          theirs.client.id,
          user: admin,
          actor: 'gil',
        ),
      );
      expect((await provider.findClient(theirs.client.id))!.revokedAt, isNotNull);
    });
  });

  test('a process with no platform API installed says so', () async {
    DVPlatformApi.uninstall();
    await expectLater(
      onTenant('acme', () => platform.apiKeys.list(user: admin)),
      throwsA(isA<StateError>()),
    );
  });
}
