/// API key and OAuth client management for the organization on the current
/// tenant, asked of `DV.Auth.authorization` before anything is written.
///
/// `DVApiKeys` and `DVOAuthProvider` issue, rotate and revoke for whoever
/// calls them. This is the surface an application's settings page and
/// backend functions call instead, reached as `DV.Auth.apiKeys` and
/// `DV.Auth.oauthClients`:
///
/// * the organization is the one on the current tenant, never an id the
///   caller names, so a key or client of another organization cannot be
///   rotated, revoked or listed from this one;
/// * every operation is a policy question on [DVApiKeyResource] or
///   [DVOAuthClientResource] -- `create`, `viewAny`, `update`, `delete` --
///   and the policy sees what is asked for, such as the scopes; with no
///   policy registered the answer is no;
/// * a third-party caller is refused by its scopes before any policy runs,
///   as everywhere else (`DV-APIKEY-002`);
/// * a rate plan the declaration does not have is refused at issue, rather
///   than on every call the key makes.
library dartvel_core.auth.platform_api_management;

import 'dart:async';

import '../../dartvel.dart' show DVAuthAuthorization;
import '../tenancy/tenants.dart';
import 'api_keys.dart';
import 'oauth_provider.dart';
import 'organizations.dart';
import 'platform_api.dart';

/// What a policy on API keys is asked about.
class DVApiKeyResource {
  const DVApiKeyResource({
    required this.organization,
    this.key,
    this.scopes = const <String>[],
    this.ratePlan,
    this.expiresIn,
  });

  /// The organization on the current tenant.
  final DVOrganization organization;

  /// The key being rotated or revoked; null for an issue or a list.
  final DVApiKey? key;

  /// The scopes asked for at issue, or the key's.
  final List<String> scopes;
  final String? ratePlan;
  final Duration? expiresIn;
}

/// What a policy on OAuth clients is asked about.
class DVOAuthClientResource {
  const DVOAuthClientResource({
    required this.organization,
    this.client,
    this.scopes = const <String>[],
    this.redirectUris = const <String>[],
    this.isPublic = false,
  });

  final DVOrganization organization;

  /// The client being revoked; null for a registration or a list.
  final DVOAuthClient? client;
  final List<String> scopes;
  final List<String> redirectUris;
  final bool isPublic;
}

/// `DV.Auth.apiKeys` and `DV.Auth.oauthClients`.
class DVPlatformApiAuth {
  const DVPlatformApiAuth({
    this.authorization = const DVAuthAuthorization(),
  });

  final DVAuthAuthorization authorization;

  DVApiKeyManagement get apiKeys => DVApiKeyManagement(authorization);

  DVOAuthClientManagement get oauthClients =>
      DVOAuthClientManagement(authorization);
}

/// Issues, lists, rotates and revokes the current organization's API keys.
class DVApiKeyManagement {
  const DVApiKeyManagement(this.authorization);

  final DVAuthAuthorization authorization;

  /// Issues a key for the current organization. [user] is asked about as the
  /// policy's user, and [actor] is recorded in Record History. The secret is
  /// on the result, once.
  Future<DVIssuedApiKey> issue({
    required Object? user,
    required String? actor,
    required List<String> scopes,
    Duration? expiresIn,
    String? name,
    String? ratePlan,
  }) async {
    final DVPlatformApi platform = _platform();
    if (ratePlan != null && !platform.config.ratePlans.containsKey(ratePlan)) {
      throw ArgumentError.value(
        ratePlan,
        'ratePlan',
        'is not declared under dartvel.platformApi.ratePlans (declared: '
            '${platform.config.ratePlans.keys.toList()..sort()})',
      );
    }
    final DVOrganization organization = await _currentOrganization(platform);
    await _authorize<DVApiKeyResource>(
      authorization,
      user,
      'create',
      DVApiKeyResource(
        organization: organization,
        scopes: List<String>.unmodifiable(scopes),
        ratePlan: ratePlan,
        expiresIn: expiresIn,
      ),
    );
    return (await platform.keys()).issue(
      organization: organization,
      scopes: scopes,
      expiresIn: expiresIn,
      name: name,
      ratePlan: ratePlan,
      actor: actor,
    );
  }

  /// The current organization's keys, revoked and expired ones included.
  Future<List<DVApiKey>> list({required Object? user}) async {
    final DVPlatformApi platform = _platform();
    final DVOrganization organization = await _currentOrganization(platform);
    await _authorize<DVApiKeyResource>(
      authorization,
      user,
      'viewAny',
      DVApiKeyResource(organization: organization),
    );
    return (await platform.keys()).forOrganization(organization.id);
  }

  /// Rotates key [id] of the current organization, with an overlap.
  Future<DVIssuedApiKey> rotate(
    String id, {
    required Object? user,
    required String? actor,
    Duration? overlap,
  }) async {
    final DVPlatformApi platform = _platform();
    final DVOrganization organization = await _currentOrganization(platform);
    final DVApiKeys keys = await platform.keys();
    final DVApiKey key = await _own(keys, organization, id);
    await _authorize<DVApiKeyResource>(
      authorization,
      user,
      'update',
      DVApiKeyResource(organization: organization, key: key, scopes: key.scopes),
    );
    return keys.rotate(id, overlap: overlap, actor: actor);
  }

  /// Revokes key [id] of the current organization, at once.
  Future<void> revoke(
    String id, {
    required Object? user,
    required String? actor,
  }) async {
    final DVPlatformApi platform = _platform();
    final DVOrganization organization = await _currentOrganization(platform);
    final DVApiKeys keys = await platform.keys();
    final DVApiKey key = await _own(keys, organization, id);
    await _authorize<DVApiKeyResource>(
      authorization,
      user,
      'delete',
      DVApiKeyResource(organization: organization, key: key, scopes: key.scopes),
    );
    await keys.revoke(id, actor: actor);
  }

  /// Key [id], when it belongs to [organization]. Another organization's key
  /// is answered as no key at all, so an id cannot be probed from here.
  static Future<DVApiKey> _own(
    DVApiKeys keys,
    DVOrganization organization,
    String id,
  ) async {
    final DVApiKey? key = await keys.find(id);
    if (key == null || key.organizationId != organization.id) {
      throw DVApiKeyNotLive(id, 'no such key in this organization');
    }
    return key;
  }
}

/// Registers, lists and revokes the current organization's OAuth clients.
class DVOAuthClientManagement {
  const DVOAuthClientManagement(this.authorization);

  final DVAuthAuthorization authorization;

  /// Registers a client for the current organization. A confidential
  /// client's secret is on the result, once.
  Future<DVRegisteredOAuthClient> register({
    required Object? user,
    required String? actor,
    required String name,
    required List<String> redirectUris,
    required List<String> scopes,
    bool public = false,
  }) async {
    final DVPlatformApi platform = _platform();
    final DVOAuthProvider provider = await _provider(platform);
    final DVOrganization organization = await _currentOrganization(platform);
    await _authorize<DVOAuthClientResource>(
      authorization,
      user,
      'create',
      DVOAuthClientResource(
        organization: organization,
        scopes: List<String>.unmodifiable(scopes),
        redirectUris: List<String>.unmodifiable(redirectUris),
        isPublic: public,
      ),
    );
    return provider.registerClient(
      name: name,
      redirectUris: redirectUris,
      scopes: scopes,
      public: public,
      organization: organization,
      actor: actor,
    );
  }

  /// The current organization's clients, oldest first.
  Future<List<DVOAuthClient>> list({required Object? user}) async {
    final DVPlatformApi platform = _platform();
    final DVOAuthProvider provider = await _provider(platform);
    final DVOrganization organization = await _currentOrganization(platform);
    await _authorize<DVOAuthClientResource>(
      authorization,
      user,
      'viewAny',
      DVOAuthClientResource(organization: organization),
    );
    final List<Map<String, Object?>> rows = await provider.database.query(
      'SELECT id FROM dv_oauth_clients WHERE organization_id = ?',
      <Object?>[organization.id],
    );
    final List<DVOAuthClient> clients = <DVOAuthClient>[
      for (final Map<String, Object?> row in rows)
        if (await provider.findClient('${row['id']}')
            case final DVOAuthClient client)
          client,
    ]..sort((DVOAuthClient a, DVOAuthClient b) => a.createdAt.compareTo(b.createdAt));
    return clients;
  }

  /// Revokes client [clientId] of the current organization; its tokens stop
  /// on their next use.
  Future<void> revoke(
    String clientId, {
    required Object? user,
    required String? actor,
  }) async {
    final DVPlatformApi platform = _platform();
    final DVOAuthProvider provider = await _provider(platform);
    final DVOrganization organization = await _currentOrganization(platform);
    final DVOAuthClient? client = await provider.findClient(clientId);
    if (client == null || client.organizationId != organization.id) {
      throw StateError('No OAuth client with that id belongs to this '
          'organization.');
    }
    await _authorize<DVOAuthClientResource>(
      authorization,
      user,
      'delete',
      DVOAuthClientResource(
        organization: organization,
        client: client,
        scopes: client.scopes,
        redirectUris: client.redirectUris,
        isPublic: client.isPublic,
      ),
    );
    await provider.revokeClient(clientId, actor: actor);
  }

  static Future<DVOAuthProvider> _provider(DVPlatformApi platform) async {
    final DVOAuthProvider? provider = await platform.oauthProvider();
    if (provider == null) {
      throw StateError(
        'OAuth clients need dartvel.platformApi.oauth, and this application '
        'does not declare it.',
      );
    }
    return provider;
  }
}

DVPlatformApi _platform() =>
    DVPlatformApi.installed ??
    (throw StateError(
      'The platform API is not installed in this process. Keys and OAuth '
      'clients are managed where dartvel.platformApi is declared and the '
      'database is: the generated backend.',
    ));

Future<DVOrganization> _currentOrganization(DVPlatformApi platform) async {
  final String tenant = const DVTenants().currentTenant;
  final DVOrganizations organizations = await platform.organizations();
  final DVOrganization? organization = await organizations.forTenant(tenant);
  if (organization == null) throw DVTenantHasNoOrganization(tenant);
  final DateTime? closedAt = organization.closedAt;
  if (closedAt != null) {
    throw DVOrganizationClosed(
      organization.id,
      closedAt: closedAt,
      restorableUntil: closedAt.add(organizations.closeGrace),
    );
  }
  return organization;
}

/// Asks [authorization] whether [user] may [action] [resource], typed by
/// the resource so the policy registered for it is the one asked.
Future<void> _authorize<TResource>(
  DVAuthAuthorization authorization,
  Object? user,
  String action,
  TResource resource,
) async {
  if (user == null) {
    throw StateError(
      'Nobody is signed in, so nobody may $action on $TResource.',
    );
  }
  await authorization.authorize<Object?, TResource>(user, action, resource);
}
