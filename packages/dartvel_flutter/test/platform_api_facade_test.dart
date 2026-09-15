// DV.Auth.apiKeys and DV.Auth.oauthClients are the platform API's management
// surface, asked of DV.Auth.authorization -- the registry the application's
// policies are in, not a second one.
//
// The silent failure is a facade wired to its own registry: every policy the
// application registered through DV.Auth would be skipped, and the answer
// would be whatever that other registry defaults to.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryDVDatabaseAdapter db;

  setUp(() async {
    const DVTestHarness().resetPolicies();
    db = MemoryDVDatabaseAdapter();
    DVPlatformApi.install(
      DVPlatformApiConfig.fromConfig(<String, Object?>{
        'scopes': <String, Object?>{
          'orders:read': <String>['Order.view'],
        },
        'oauth': true,
      }),
      database: () => db,
    );
    await (await DVPlatformApi.installed!.organizations()).create(
      name: 'Acme',
      tenant: 'acme',
      ownerId: 'ada',
    );
  });

  tearDown(() {
    DVPlatformApi.uninstall();
    const DVTestHarness().resetPolicies();
  });

  test('a policy registered through DV.Auth decides DV.Auth.apiKeys', () async {
    final DVAuthUser ada = const DVTestHarness().fakeAuthUser(id: 'ada');
    final DVAuthUser bob = const DVTestHarness().fakeAuthUser(id: 'bob');
    DV.Auth.registerPolicy<DVAuthUser, DVApiKeyResource>(
      'create',
      (DVAuthUser user, DVApiKeyResource _) => user.id == 'ada',
    );

    final DVIssuedApiKey issued = await const DVTenants().withTenant(
      'acme',
      () => DV.Auth.apiKeys.issue(
        user: ada,
        actor: ada.id,
        scopes: <String>['orders:read'],
      ),
    );
    expect(issued.secret, startsWith('dvk_'));

    await expectLater(
      const DVTenants().withTenant(
        'acme',
        () => DV.Auth.apiKeys.issue(
          user: bob,
          actor: bob.id,
          scopes: <String>['orders:read'],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('DV.Auth.oauthClients registers through the same registry', () async {
    final DVAuthUser ada = const DVTestHarness().fakeAuthUser(id: 'ada');
    await expectLater(
      const DVTenants().withTenant(
        'acme',
        () => DV.Auth.oauthClients.register(
          user: ada,
          actor: ada.id,
          name: 'Partner',
          redirectUris: <String>['https://partner.example/cb'],
          scopes: <String>['orders:read'],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    DV.Auth.registerPolicy<DVAuthUser, DVOAuthClientResource>(
      'create',
      (DVAuthUser user, DVOAuthClientResource _) => true,
    );
    final DVRegisteredOAuthClient client = await const DVTenants().withTenant(
      'acme',
      () => DV.Auth.oauthClients.register(
        user: ada,
        actor: ada.id,
        name: 'Partner',
        redirectUris: <String>['https://partner.example/cb'],
        scopes: <String>['orders:read'],
      ),
    );
    expect(client.client.name, 'Partner');
  });
}
