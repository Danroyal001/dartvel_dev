/// The application as an OAuth 2.1 provider for its own users, and client
/// credentials as an API key with a grant.
///
/// The provider half of the specification's `# Platform API: Keys, Scopes
/// and OAuth Provider`. Every guard below is one whose absence still returns
/// tokens, which is why each is stated where it lives:
///
/// * PKCE with `S256` is required of every client, public or confidential,
///   as OAuth 2.1 requires; `plain` is refused;
/// * a redirect URI is compared as a whole string against the registered
///   ones, and a mismatch is never redirected to;
/// * an authorization code is spent before anything else is checked, by a
///   versioned write, so it redeems once even when two exchanges race; a
///   second presentation revokes the grant the first one produced;
/// * a refresh token is rotated on use, and presenting a rotated one revokes
///   the whole grant, because the provider cannot tell the thief from the
///   client;
/// * codes, tokens and client secrets are stored as SHA-256 only;
/// * a grant belongs to one tenant, and a request resolved to another tenant
///   does not authenticate with its tokens;
/// * a revoked client, a withdrawn consent and a revoked API key each stop
///   the tokens that came from them on the next call.
library dartvel_core.auth.oauth_provider;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import '../data/record_history.dart';
import '../database/adapter.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import '../transaction/transaction.dart';
import 'api_keys.dart';
import 'api_scopes.dart';
import 'secret_hash.dart';

/// A registered OAuth client. Nothing on it is the secret.
class DVOAuthClient {
  const DVOAuthClient({
    required this.id,
    required this.name,
    required this.redirectUris,
    required this.scopes,
    required this.isPublic,
    required this.createdAt,
    this.tenant,
    this.revokedAt,
  });

  final String id;
  final String name;
  final List<String> redirectUris;

  /// The most any authorization for this client can ask for.
  final List<String> scopes;

  /// A client that cannot keep a secret: a mobile, desktop or browser app.
  final bool isPublic;
  final DateTime createdAt;

  /// The tenant it was registered on. A client of another tenant is not this
  /// tenant's to list or revoke.
  final String? tenant;

  final DateTime? revokedAt;

  @override
  String toString() => 'DVOAuthClient($id "$name")';
}

/// A client and its secret, returned once, at registration.
class DVRegisteredOAuthClient {
  const DVRegisteredOAuthClient(this.client, this.secret);

  final DVOAuthClient client;

  /// The only copy, or null for a public client.
  final String? secret;

  @override
  String toString() => 'DVRegisteredOAuthClient(${client.id})';
}

/// An OAuth error, with RFC 6749's error code.
class DVOAuthError implements Exception {
  const DVOAuthError(this.error, this.description, {this.redirectable = true});

  /// `invalid_request`, `invalid_client`, `invalid_grant`, `invalid_scope`,
  /// `unsupported_grant_type` or `unsupported_response_type`.
  final String error;
  final String description;

  /// Whether the error may be sent to the redirect URI. False when the client
  /// or the redirect URI itself is the problem: redirecting there would hand
  /// an attacker's URI the error, and with it an open redirector.
  final bool redirectable;

  Map<String, String> toJson() => <String, String>{
    'error': error,
    'error_description': description,
  };

  @override
  String toString() => 'DVOAuthError($error: $description)';
}

/// A client registration asking for a scope the application does not define
/// (`DV-APIKEY-004`).
class DVUndefinedOAuthScope implements Exception {
  DVUndefinedOAuthScope(this.scopes, Set<String> declared)
    : declared = Set<String>.unmodifiable(declared);

  final List<String> scopes;
  final Set<String> declared;

  String get code => 'DV-APIKEY-004';

  @override
  String toString() =>
      '$code: an OAuth client asked for $scopes, which '
      'dartvel.platformApi.scopes does not declare '
      '(declared: ${declared.toList()..sort()}).';
}

/// An authorization request that passed validation: the client, redirect URI,
/// scopes and PKCE challenge are acceptable. Only [DVOAuthProvider] makes one.
class DVAuthorizationRequest {
  const DVAuthorizationRequest._({
    required this.client,
    required this.redirectUri,
    required this.scopes,
    required this.codeChallenge,
    this.state,
  });

  final DVOAuthClient client;
  final String redirectUri;
  final List<String> scopes;
  final String codeChallenge;
  final String? state;
}

/// An authorization code and the redirect that carries it.
class DVIssuedAuthorizationCode {
  const DVIssuedAuthorizationCode(this.code, this.redirect, this.expiresAt);

  final String code;

  /// The redirect URI with `code` and `state` added. Send the person there.
  final Uri redirect;
  final DateTime expiresAt;

  @override
  String toString() => 'DVIssuedAuthorizationCode(expires $expiresAt)';
}

/// A token endpoint response.
class DVOAuthTokenResponse {
  const DVOAuthTokenResponse({
    required this.accessToken,
    required this.expiresIn,
    required this.scopes,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final Duration expiresIn;
  final List<String> scopes;

  String get tokenType => 'Bearer';

  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'token_type': tokenType,
    'expires_in': expiresIn.inSeconds,
    'scope': scopes.join(' '),
    if (refreshToken != null) 'refresh_token': refreshToken,
  };

  @override
  String toString() => 'DVOAuthTokenResponse(${scopes.join(' ')})';
}

/// A token introspection answer (RFC 7662).
class DVOAuthIntrospection {
  const DVOAuthIntrospection.inactive()
    : active = false,
      scopes = const <String>[],
      clientId = null,
      subject = null,
      tenant = null,
      expiresAt = null;

  const DVOAuthIntrospection._active({
    required List<String> this.scopes,
    required String this.clientId,
    required String this.subject,
    required String this.tenant,
    required DateTime this.expiresAt,
  }) : active = true;

  final bool active;
  final List<String> scopes;
  final String? clientId;
  final String? subject;
  final String? tenant;
  final DateTime? expiresAt;

  /// An inactive token says nothing else, so introspection cannot be used to
  /// learn about tokens that no longer work.
  Map<String, Object?> toJson() => !active
      ? const <String, Object?>{'active': false}
      : <String, Object?>{
          'active': true,
          'scope': scopes.join(' '),
          'client_id': clientId,
          'sub': subject,
          'token_type': 'access_token',
          'exp': expiresAt!.millisecondsSinceEpoch ~/ 1000,
          'tenant': tenant,
        };
}

/// A person's standing consent for a client on a tenant.
class DVOAuthConsent {
  const DVOAuthConsent({
    required this.userId,
    required this.clientId,
    required this.tenant,
    required this.scopes,
    required this.grantedAt,
  });

  final String userId;
  final String clientId;
  final String tenant;
  final List<String> scopes;
  final DateTime grantedAt;
}

/// Clients, authorizations, tokens and consents, over one database.
class DVOAuthProvider {
  DVOAuthProvider({
    required this.database,
    required this.scopes,
    this.apiKeys,
    this.codeLifetime = const Duration(minutes: 1),
    this.accessTokenLifetime = const Duration(hours: 1),
    this.refreshTokenLifetime = const Duration(days: 30),
    DateTime Function()? clock,
    Random? random,
    DVLogger? logger,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure(),
       _logger = logger {
    _clients = DVRecordTable(
      table: 'dv_oauth_clients',
      key: 'id',
      columns: const <String>[
        'id',
        'secret_hash',
        'name',
        'redirect_uris',
        'scopes',
        'public',
        'tenant',
        'created_by',
        'created_at',
        'revoked_at',
      ],
      types: const <String, String>{
        'id': 'TEXT',
        'secret_hash': 'TEXT',
        'name': 'TEXT',
        'redirect_uris': 'TEXT',
        'scopes': 'TEXT',
        'public': 'INTEGER',
        'tenant': 'TEXT',
        'created_by': 'TEXT',
        'created_at': 'TEXT',
        'revoked_at': 'TEXT',
      },
      sensitive: const <String>{'secret_hash'},
      history: const DVHistory(),
      database: database,
    );
    _codes = DVRecordTable(
      table: 'dv_oauth_codes',
      key: 'id',
      columns: const <String>[
        'id',
        'client_id',
        'grant_id',
        'user_id',
        'tenant',
        'scopes',
        'redirect_uri',
        'code_challenge',
        'expires_at',
        'used_at',
      ],
      types: const <String, String>{
        'id': 'TEXT',
        'client_id': 'TEXT',
        'grant_id': 'TEXT',
        'user_id': 'TEXT',
        'tenant': 'TEXT',
        'scopes': 'TEXT',
        'redirect_uri': 'TEXT',
        'code_challenge': 'TEXT',
        'expires_at': 'TEXT',
        'used_at': 'TEXT',
      },
      database: database,
    );
    _grants = DVRecordTable(
      table: 'dv_oauth_grants',
      key: 'id',
      columns: const <String>[
        'id',
        'client_id',
        'user_id',
        'key_id',
        'tenant',
        'scopes',
        'created_at',
        'revoked_at',
        'revoked_reason',
      ],
      types: const <String, String>{
        'id': 'TEXT',
        'client_id': 'TEXT',
        'user_id': 'TEXT',
        'key_id': 'TEXT',
        'tenant': 'TEXT',
        'scopes': 'TEXT',
        'created_at': 'TEXT',
        'revoked_at': 'TEXT',
        'revoked_reason': 'TEXT',
      },
      history: const DVHistory(),
      database: database,
    );
    _tokens = DVRecordTable(
      table: 'dv_oauth_tokens',
      key: 'id',
      columns: const <String>[
        'id',
        'grant_id',
        'kind',
        'scopes',
        'expires_at',
        'used_at',
        'revoked_at',
      ],
      types: const <String, String>{
        'id': 'TEXT',
        'grant_id': 'TEXT',
        'kind': 'TEXT',
        'scopes': 'TEXT',
        'expires_at': 'TEXT',
        'used_at': 'TEXT',
        'revoked_at': 'TEXT',
      },
      database: database,
    );
    _consents = DVRecordTable(
      table: 'dv_oauth_consents',
      key: 'id',
      columns: const <String>[
        'id',
        'user_id',
        'client_id',
        'tenant',
        'scopes',
        'granted_at',
        'revoked_at',
      ],
      types: const <String, String>{
        'id': 'TEXT',
        'user_id': 'TEXT',
        'client_id': 'TEXT',
        'tenant': 'TEXT',
        'scopes': 'TEXT',
        'granted_at': 'TEXT',
        'revoked_at': 'TEXT',
      },
      history: const DVHistory(),
      database: database,
    );
  }

  final DVDatabaseAdapter database;
  final DVApiScopes scopes;

  /// The keys client credentials are exchanged for. Without them the grant
  /// is `unsupported_grant_type`.
  final DVApiKeys? apiKeys;

  final Duration codeLifetime;
  final Duration accessTokenLifetime;
  final Duration refreshTokenLifetime;

  final DateTime Function() _clock;
  final Random _random;
  final DVLogger? _logger;

  late final DVRecordTable _clients;
  late final DVRecordTable _codes;
  late final DVRecordTable _grants;
  late final DVRecordTable _tokens;
  late final DVRecordTable _consents;

  static const String _accessPrefix = 'dvat_';
  static const String _refreshPrefix = 'dvrt_';
  static final RegExp _challengePattern = RegExp(r'^[A-Za-z0-9_\-]{43}$');
  static final RegExp _verifierPattern = RegExp(r'^[A-Za-z0-9\-._~]{43,128}$');
  static final String _absentHash = DVSecretHash.of('dvc_absent');

  DVLogger get _log => _logger ?? DVObservability.logger;

  DateTime _now() => _clock().toUtc();

  Future<void> ensureSchema() async {
    await _clients.ensureSchema();
    await _codes.ensureSchema();
    await _grants.ensureSchema();
    await _tokens.ensureSchema();
    await _consents.ensureSchema();
  }

  // --- clients ---------------------------------------------------------------

  /// Registers a client. A confidential client's secret is returned once.
  ///
  /// A scope the application does not declare is refused here
  /// (`DV-APIKEY-004`) rather than at the first call.
  Future<DVRegisteredOAuthClient> registerClient({
    required String name,
    required List<String> redirectUris,
    required List<String> scopes,
    bool public = false,
    String? tenant,
    String? actor,
  }) async {
    if (scopes.isEmpty) {
      throw ArgumentError.value(scopes, 'scopes', 'a client needs a scope');
    }
    final List<String> undeclared = this.scopes.undeclared(scopes);
    if (undeclared.isNotEmpty) {
      final DVUndefinedOAuthScope error = DVUndefinedOAuthScope(
        undeclared,
        this.scopes.names,
      );
      _log.error('$error', code: error.code);
      throw error;
    }
    if (redirectUris.isEmpty) {
      throw ArgumentError.value(
        redirectUris,
        'redirectUris',
        'a client needs a redirect URI',
      );
    }
    for (final String uri in redirectUris) {
      final String? problem = _redirectProblem(uri);
      if (problem != null) {
        throw ArgumentError.value(uri, 'redirectUris', problem);
      }
    }
    final String id = 'dvc_${DVSecretHash.hex(_random, 8)}';
    final String? secret = public
        ? null
        : 'dvcs_${DVSecretHash.token(_random, 32)}';
    final DateTime now = _now();
    final DVRecord record = (await _clients.write(
      <String, Object?>{
        'id': id,
        'secret_hash': secret == null ? null : DVSecretHash.of(secret),
        'name': name,
        'redirect_uris': jsonEncode(redirectUris),
        'scopes': jsonEncode(_unique(scopes)),
        'public': public ? 1 : 0,
        'tenant': tenant,
        'created_by': actor,
        'created_at': _stamp(now),
        'revoked_at': null,
      },
      actor: actor,
      tenant: tenant,
    )).record;
    return DVRegisteredOAuthClient(_clientFrom(record), secret);
  }

  /// The client [clientId] with [secret], or a [DVOAuthError]
  /// `invalid_client`. A public client authenticates with no secret.
  ///
  /// For an endpoint that needs to know who is calling before it does
  /// anything else, such as introspection. An unknown id costs what a wrong
  /// secret does.
  Future<DVOAuthClient> authenticateClient(String clientId, String? secret) =>
      _authenticateClient(clientId, secret);

  Future<DVOAuthClient?> findClient(String id) async {
    final DVRecord? record = await _clients.read(id);
    return record == null ? null : _clientFrom(record);
  }

  /// Revokes a client. Its tokens stop on their next use, and it can get no
  /// more.
  Future<void> revokeClient(String id, {String? actor}) async {
    final DVRecord? record = await _clients.read(id);
    if (record == null || record.values['revoked_at'] != null) return;
    await _clients.write(
      <String, Object?>{...record.values, 'revoked_at': _stamp(_now())},
      base: record,
      actor: actor,
    );
  }

  // --- authorization ---------------------------------------------------------

  /// Validates an authorization request before the consent screen is shown.
  ///
  /// An unknown client or unregistered redirect URI throws a
  /// [DVOAuthError] that is not [DVOAuthError.redirectable]: show it, never
  /// redirect it.
  Future<DVAuthorizationRequest> validateAuthorization({
    required String clientId,
    required String redirectUri,
    required List<String> scopes,
    String? codeChallenge,
    String? codeChallengeMethod,
    String? state,
    String responseType = 'code',
  }) async {
    final DVRecord? record = await _clients.read(clientId);
    if (record == null || record.values['revoked_at'] != null) {
      throw const DVOAuthError(
        'invalid_client',
        'unknown or revoked client',
        redirectable: false,
      );
    }
    final DVOAuthClient client = _clientFrom(record);
    // Compared whole. A prefix or host match turns any path on the partner's
    // domain -- or a look-alike domain -- into a place codes are sent.
    if (!client.redirectUris.contains(redirectUri)) {
      throw const DVOAuthError(
        'invalid_request',
        'redirect_uri is not registered for this client',
        redirectable: false,
      );
    }
    if (responseType != 'code') {
      throw const DVOAuthError(
        'unsupported_response_type',
        'only the code response type is served',
      );
    }
    if (codeChallenge == null) {
      throw const DVOAuthError(
        'invalid_request',
        'code_challenge is required (PKCE)',
      );
    }
    if (codeChallengeMethod != 'S256') {
      throw const DVOAuthError(
        'invalid_request',
        'code_challenge_method must be S256',
      );
    }
    if (!_challengePattern.hasMatch(codeChallenge)) {
      throw const DVOAuthError('invalid_request', 'malformed code_challenge');
    }
    final List<String> requested = _unique(scopes);
    if (requested.isEmpty) {
      throw const DVOAuthError('invalid_scope', 'no scope was requested');
    }
    for (final String scope in requested) {
      if (!client.scopes.contains(scope) || !this.scopes.defines(scope)) {
        throw DVOAuthError(
          'invalid_scope',
          'scope "$scope" is not available to this client',
        );
      }
    }
    return DVAuthorizationRequest._(
      client: client,
      redirectUri: redirectUri,
      scopes: requested,
      codeChallenge: codeChallenge,
      state: state,
    );
  }

  /// The consent screen's lines: each scope with the words its declaration
  /// gave it.
  List<(String, String)> describe(
    DVAuthorizationRequest request,
  ) => <(String, String)>[
    for (final String scope in request.scopes) (scope, scopes.describe(scope)),
  ];

  /// Whether [userId] has to be asked, or already consented to every scope of
  /// [request] on [tenant].
  Future<bool> needsConsent(
    DVAuthorizationRequest request, {
    required String userId,
    required String tenant,
  }) async {
    final DVRecord? consent = await _consents.read(
      _consentKey(tenant, userId, request.client.id),
    );
    if (consent == null || consent.values['revoked_at'] != null) return true;
    final List<String> granted = _list(consent.values['scopes']);
    return !request.scopes.every(granted.contains);
  }

  /// Records [userId]'s consent to [request] on [tenant] and issues the code.
  Future<DVIssuedAuthorizationCode> approve(
    DVAuthorizationRequest request, {
    required String userId,
    required String tenant,
  }) async {
    final DVOAuthClient client = request.client;
    final DVRecord? current = await _clients.read(client.id);
    if (current == null || current.values['revoked_at'] != null) {
      throw const DVOAuthError(
        'invalid_client',
        'unknown or revoked client',
        redirectable: false,
      );
    }
    final DateTime now = _now();
    final String code = DVSecretHash.token(_random, 32);
    final String grantId = 'dvg_${DVSecretHash.hex(_random, 8)}';
    final DateTime expiresAt = now.add(codeLifetime);
    await DVTransactionRunner()<void>((DVContext context) async {
      final String consentKey = _consentKey(tenant, userId, client.id);
      final DVRecord? consent = await _consents.read(consentKey);
      final bool live = consent != null && consent.values['revoked_at'] == null;
      await _consents.write(
        <String, Object?>{
          'id': consentKey,
          'user_id': userId,
          'client_id': client.id,
          'tenant': tenant,
          'scopes': jsonEncode(
            _unique(<String>[
              if (live) ..._list(consent.values['scopes']),
              ...request.scopes,
            ])..sort(),
          ),
          'granted_at': _stamp(now),
          'revoked_at': null,
        },
        base: consent,
        actor: userId,
        tenant: tenant,
      );
      await _grants.write(
        <String, Object?>{
          'id': grantId,
          'client_id': client.id,
          'user_id': userId,
          'key_id': null,
          'tenant': tenant,
          'scopes': jsonEncode(request.scopes),
          'created_at': _stamp(now),
          'revoked_at': null,
          'revoked_reason': null,
        },
        actor: userId,
        tenant: tenant,
      );
      await _codes.write(<String, Object?>{
        'id': DVSecretHash.of(code),
        'client_id': client.id,
        'grant_id': grantId,
        'user_id': userId,
        'tenant': tenant,
        'scopes': jsonEncode(request.scopes),
        'redirect_uri': request.redirectUri,
        'code_challenge': request.codeChallenge,
        'expires_at': _stamp(expiresAt),
        'used_at': null,
      });
    });
    final Uri base = Uri.parse(request.redirectUri);
    final Uri redirect = base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'code': code,
        if (request.state != null) 'state': request.state!,
      },
    );
    return DVIssuedAuthorizationCode(code, redirect, expiresAt);
  }

  // --- token endpoint --------------------------------------------------------

  /// The `authorization_code` grant.
  Future<DVOAuthTokenResponse> exchangeCode({
    required String clientId,
    required String? clientSecret,
    required String code,
    required String redirectUri,
    required String? codeVerifier,
  }) async {
    final DVOAuthClient client = await _authenticateClient(
      clientId,
      clientSecret,
    );
    final DVRecord? record = await _codes.read(DVSecretHash.of(code));
    if (record == null) {
      throw const DVOAuthError('invalid_grant', 'unknown authorization code');
    }
    final String grantId = '${record.values['grant_id']}';
    // Spent before anything else is checked, so a failed attempt -- a wrong
    // verifier, a wrong client -- cannot be retried against the same code.
    if (record.values['used_at'] != null || !await _spend(_codes, record)) {
      await _revokeGrant(grantId, 'authorization code presented twice');
      throw const DVOAuthError(
        'invalid_grant',
        'authorization code already used',
      );
    }
    final Map<String, Object?> v = record.values;
    if (v['client_id'] != client.id) {
      throw const DVOAuthError(
        'invalid_grant',
        'code was issued to another client',
      );
    }
    if (!_now().isBefore(_date(v['expires_at'])!)) {
      throw const DVOAuthError('invalid_grant', 'authorization code expired');
    }
    if (v['redirect_uri'] != redirectUri) {
      throw const DVOAuthError('invalid_grant', 'redirect_uri does not match');
    }
    if (codeVerifier == null ||
        !_verifierPattern.hasMatch(codeVerifier) ||
        !DVSecretHash.equals('${v['code_challenge']}', _s256(codeVerifier))) {
      throw const DVOAuthError(
        'invalid_grant',
        'code_verifier does not match the challenge',
      );
    }
    final DVRecord grant = await _liveGrant(grantId);
    return _issue(grant, _list(v['scopes']), refresh: true);
  }

  /// The `refresh_token` grant. The presented token is spent; a spent one
  /// presented again revokes the grant.
  Future<DVOAuthTokenResponse> refresh({
    required String clientId,
    required String? clientSecret,
    required String refreshToken,
    List<String>? scopes,
  }) async {
    final DVOAuthClient client = await _authenticateClient(
      clientId,
      clientSecret,
    );
    final DVRecord? record = await _tokens.read(DVSecretHash.of(refreshToken));
    if (record == null || record.values['kind'] != 'refresh') {
      throw const DVOAuthError('invalid_grant', 'unknown refresh token');
    }
    final String grantId = '${record.values['grant_id']}';
    final DVRecord? grant = await _grants.read(grantId);
    // Checked before spending: another client presenting this token must not
    // be able to burn it, or to trigger the reuse revocation below.
    if (grant == null || grant.values['client_id'] != client.id) {
      throw const DVOAuthError('invalid_grant', 'unknown refresh token');
    }
    if (record.values['used_at'] != null) {
      await _revokeGrant(grantId, 'rotated refresh token presented again');
      throw const DVOAuthError('invalid_grant', 'refresh token already used');
    }
    final List<String> granted = _list(grant.values['scopes']);
    final List<String> requested = scopes == null
        ? _list(record.values['scopes'])
        : _unique(scopes);
    if (requested.isEmpty || !requested.every(granted.contains)) {
      throw const DVOAuthError(
        'invalid_scope',
        'a refresh cannot widen the granted scopes',
      );
    }
    if (record.values['revoked_at'] != null ||
        !_now().isBefore(_date(record.values['expires_at'])!)) {
      throw const DVOAuthError('invalid_grant', 'refresh token expired');
    }
    await _liveGrant(grantId);
    if (!await _spend(_tokens, record)) {
      await _revokeGrant(grantId, 'refresh token presented twice at once');
      throw const DVOAuthError('invalid_grant', 'refresh token already used');
    }
    return _issue(await _liveGrant(grantId), requested, refresh: true);
  }

  /// The `client_credentials` grant: an API key's own id and secret, for a
  /// token with at most the key's scopes. No refresh token -- the key is the
  /// long-lived credential.
  Future<DVOAuthTokenResponse> clientCredentials({
    required String clientId,
    required String clientSecret,
    List<String>? scopes,
  }) async {
    final DVApiKeys? keys = apiKeys;
    if (keys == null) {
      throw const DVOAuthError(
        'unsupported_grant_type',
        'client credentials need API keys configured',
      );
    }
    final DVApiKeyCheck check = await keys.check(clientSecret);
    final DVApiKey? key = check.key;
    if (check.principal == null || key == null || key.prefix != clientId) {
      throw const DVOAuthError('invalid_client', 'invalid client credentials');
    }
    final List<String> requested = scopes == null
        ? key.scopes
        : _unique(scopes);
    if (requested.isEmpty || !requested.every(key.scopes.contains)) {
      throw const DVOAuthError(
        'invalid_scope',
        'a token cannot have scopes its key does not',
      );
    }
    final DateTime now = _now();
    final String grantId = 'dvg_${DVSecretHash.hex(_random, 8)}';
    final DVRecord grant = (await _grants.write(
      <String, Object?>{
        'id': grantId,
        'client_id': key.prefix,
        'user_id': null,
        'key_id': key.id,
        'tenant': key.tenant,
        'scopes': jsonEncode(requested),
        'created_at': _stamp(now),
        'revoked_at': null,
        'revoked_reason': null,
      },
      actor: key.prefix,
      tenant: key.tenant,
    )).record;
    return _issue(grant, requested, refresh: false);
  }

  // --- resource server -------------------------------------------------------

  /// The principal [accessToken] authenticates as, or null.
  ///
  /// [tenant] is the tenant the request resolved to; when it is not given and
  /// the call runs in a `DV.Tenants.withTenant` scope, that tenant is used.
  Future<DVApiPrincipal?> authenticate(
    String accessToken, {
    String? tenant,
  }) async => (await _resolve(accessToken, tenant))?.$2;

  /// RFC 7662 introspection of an access token.
  Future<DVOAuthIntrospection> introspect(
    String token, {
    String? tenant,
  }) async {
    final (DVRecord, DVApiPrincipal)? resolved = await _resolve(token, tenant);
    if (resolved == null) return const DVOAuthIntrospection.inactive();
    final DVApiPrincipal principal = resolved.$2;
    return DVOAuthIntrospection._active(
      scopes: principal.scopes.toList()..sort(),
      clientId: principal.clientId!,
      subject: principal.subject,
      tenant: principal.tenant,
      expiresAt: principal.expiresAt!,

    );
  }

  /// RFC 7009 revocation. A refresh token ends its whole grant; an access
  /// token ends itself. A token that is unknown, or belongs to another
  /// client, is ignored without saying so.
  Future<void> revokeToken(
    String token, {
    required String clientId,
    String? clientSecret,
  }) async {
    final DVOAuthClient client = await _authenticateClient(
      clientId,
      clientSecret,
    );
    final DVRecord? record = await _tokens.read(DVSecretHash.of(token));
    if (record == null) return;
    final String grantId = '${record.values['grant_id']}';
    final DVRecord? grant = await _grants.read(grantId);
    if (grant == null || grant.values['client_id'] != client.id) return;
    if (record.values['kind'] == 'refresh') {
      await _revokeGrant(grantId, 'refresh token revoked');
      return;
    }
    if (record.values['revoked_at'] != null) return;
    await _tokens.write(<String, Object?>{
      ...record.values,
      'revoked_at': _stamp(_now()),
    }, base: record);
  }

  // --- consent ---------------------------------------------------------------

  /// [userId]'s live consents on [tenant].
  Future<List<DVOAuthConsent>> consents(
    String userId, {
    required String tenant,
  }) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_oauth_consents WHERE user_id = ? AND tenant = ?',
      <Object?>[userId, tenant],
    );
    final List<DVOAuthConsent> consents = <DVOAuthConsent>[];
    for (final Map<String, Object?> row in rows) {
      final DVRecord? record = await _consents.read('${row['id']}');
      if (record == null || record.values['revoked_at'] != null) continue;
      final Map<String, Object?> v = record.values;
      consents.add(
        DVOAuthConsent(
          userId: '${v['user_id']}',
          clientId: '${v['client_id']}',
          tenant: '${v['tenant']}',
          scopes: _list(v['scopes']),
          grantedAt: _date(v['granted_at'])!,
        ),
      );
    }
    return consents;
  }

  /// Withdraws [userId]'s consent for [clientId] on [tenant], and ends every
  /// grant it allowed.
  Future<void> revokeConsent(
    String userId,
    String clientId, {
    required String tenant,
  }) async {
    final DVRecord? consent = await _consents.read(
      _consentKey(tenant, userId, clientId),
    );
    if (consent != null && consent.values['revoked_at'] == null) {
      await _consents.write(
        <String, Object?>{...consent.values, 'revoked_at': _stamp(_now())},
        base: consent,
        actor: userId,
        tenant: tenant,
      );
    }
    final List<Map<String, Object?>> grants = await database.query(
      'SELECT id FROM dv_oauth_grants WHERE user_id = ? AND client_id = ? '
      'AND tenant = ?',
      <Object?>[userId, clientId, tenant],
    );
    for (final Map<String, Object?> row in grants) {
      await _revokeGrant('${row['id']}', 'consent withdrawn');
    }
  }

  // --- internals -------------------------------------------------------------

  Future<(DVRecord, DVApiPrincipal)?> _resolve(
    String token,
    String? tenant,
  ) async {
    if (!token.startsWith(_accessPrefix)) return null;
    final DVRecord? record = await _tokens.read(DVSecretHash.of(token));
    if (record == null || record.values['kind'] != 'access') return null;
    final DateTime now = _now();
    if (record.values['revoked_at'] != null ||
        !now.isBefore(_date(record.values['expires_at'])!)) {
      return null;
    }
    final DVRecord? grant = await _grants.read('${record.values['grant_id']}');
    if (grant == null || grant.values['revoked_at'] != null) return null;
    final Map<String, Object?> g = grant.values;
    final String grantTenant = '${g['tenant']}';
    final String? requested =
        tenant ?? (DVTenants.hasScope ? const DVTenants().currentTenant : null);
    if (requested != null && requested != grantTenant) return null;

    final Object? keyId = g['key_id'];
    final Object? userId = g['user_id'];
    if (keyId != null) {
      final DVApiKeys? keys = apiKeys;
      if (keys == null) return null;
      final DVApiKey? key = await keys.find('$keyId');
      if (key == null || !key.isLiveAt(now)) return null;
    } else {
      final DVRecord? client = await _clients.read('${g['client_id']}');
      if (client == null || client.values['revoked_at'] != null) return null;
      final DVRecord? consent = await _consents.read(
        _consentKey(grantTenant, '$userId', '${g['client_id']}'),
      );
      if (consent == null || consent.values['revoked_at'] != null) return null;
    }
    final List<String> tokenScopes = _list(record.values['scopes']);
    return (
      record,
      DVApiPrincipal(
        kind: keyId != null
            ? DVApiPrincipalKind.oauthClient
            : DVApiPrincipalKind.oauthUser,
        subject: keyId != null ? '$keyId' : '$userId',
        tenant: grantTenant,

        clientId: '${g['client_id']}',
        scopes: tokenScopes.toSet(),
        actions: scopes.actionsOf(tokenScopes),
        expiresAt: _date(record.values['expires_at']),
      ),
    );
  }

  Future<DVOAuthTokenResponse> _issue(
    DVRecord grant,
    List<String> tokenScopes, {
    required bool refresh,
  }) async {
    final DateTime now = _now();
    final String grantId = '${grant.values['id']}';
    final String access = '$_accessPrefix${DVSecretHash.token(_random, 32)}';
    final String? refreshToken = refresh
        ? '$_refreshPrefix${DVSecretHash.token(_random, 32)}'
        : null;
    await _tokens.write(<String, Object?>{
      'id': DVSecretHash.of(access),
      'grant_id': grantId,
      'kind': 'access',
      'scopes': jsonEncode(tokenScopes),
      'expires_at': _stamp(now.add(accessTokenLifetime)),
      'used_at': null,
      'revoked_at': null,
    });
    if (refreshToken != null) {
      await _tokens.write(<String, Object?>{
        'id': DVSecretHash.of(refreshToken),
        'grant_id': grantId,
        'kind': 'refresh',
        'scopes': jsonEncode(tokenScopes),
        'expires_at': _stamp(now.add(refreshTokenLifetime)),
        'used_at': null,
        'revoked_at': null,
      });
    }
    // A grant revoked while these were written -- a racing reuse -- gets no
    // tokens out of it.
    await _liveGrant(grantId);
    return DVOAuthTokenResponse(
      accessToken: access,
      refreshToken: refreshToken,
      expiresIn: accessTokenLifetime,
      scopes: tokenScopes,
    );
  }

  Future<DVOAuthClient> _authenticateClient(
    String clientId,
    String? secret,
  ) async {
    final DVRecord? record = await _clients.read(clientId);
    if (record == null) {
      if (secret != null) DVSecretHash.matches(_absentHash, secret);
      throw const DVOAuthError(
        'invalid_client',
        'client authentication failed',
        redirectable: false,
      );
    }
    final DVOAuthClient client = _clientFrom(record);
    final Object? stored = record.values['secret_hash'];
    final bool authenticated = client.isPublic
        ? secret == null
        : secret != null && DVSecretHash.matches('$stored', secret);
    if (!authenticated || client.revokedAt != null) {
      throw const DVOAuthError(
        'invalid_client',
        'client authentication failed',
        redirectable: false,
      );
    }
    return client;
  }

  Future<DVRecord> _liveGrant(String id) async {
    final DVRecord? grant = await _grants.read(id);
    if (grant == null || grant.values['revoked_at'] != null) {
      throw const DVOAuthError('invalid_grant', 'the grant was revoked');
    }
    final Object? userId = grant.values['user_id'];
    if (userId != null) {
      final DVRecord? consent = await _consents.read(
        _consentKey(
          '${grant.values['tenant']}',
          '$userId',
          '${grant.values['client_id']}',
        ),
      );
      if (consent == null || consent.values['revoked_at'] != null) {
        throw const DVOAuthError('invalid_grant', 'consent was withdrawn');
      }
    }
    return grant;
  }

  /// Marks [record] used with a versioned write. False when another writer
  /// moved it first -- which for a code or refresh token means it was spent.
  Future<bool> _spend(DVRecordTable table, DVRecord record) async {
    try {
      await table.write(<String, Object?>{
        ...record.values,
        'used_at': _stamp(_now()),
      }, base: record);
      return true;
    } on DVConflictError {
      return false;
    }
  }

  Future<void> _revokeGrant(String id, String reason) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final DVRecord? grant = await _grants.read(id);
      if (grant == null || grant.values['revoked_at'] != null) return;
      try {
        await _grants.write(
          <String, Object?>{
            ...grant.values,
            'revoked_at': _stamp(_now()),
            'revoked_reason': reason,
          },
          base: grant,
          tenant: '${grant.values['tenant']}',
        );
        _log.warn('OAuth grant $id revoked: $reason.');
        return;
      } on DVConflictError {
        continue;
      }
    }
  }

  /// Why [uri] cannot be a redirect URI, or null when it can.
  static String? _redirectProblem(String uri) {
    if (uri.contains('*')) return 'a redirect URI is exact, not a pattern';
    final Uri? parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.hasScheme) return 'not an absolute URI';
    if (parsed.hasFragment) return 'a redirect URI has no fragment';
    switch (parsed.scheme) {
      case 'https':
        return parsed.host.isEmpty
            ? 'an https redirect URI needs a host'
            : null;
      case 'http':
        // Plain http only to the loopback interface, where a native app
        // listens for its own code (RFC 8252).
        const Set<String> loopback = <String>{'127.0.0.1', '::1', 'localhost'};
        return loopback.contains(parsed.host)
            ? null
            : 'plain http is only for a loopback redirect';
      default:
        // A private-use scheme for a native app is reverse-domain (RFC 8252).
        return parsed.scheme.contains('.')
            ? null
            : 'a custom scheme is reverse-domain, as in com.example.app';
    }
  }

  static String _consentKey(String tenant, String userId, String clientId) =>
      DVSecretHash.of(jsonEncode(<String>[tenant, userId, clientId]));

  static String _s256(String verifier) => base64Url
      .encode(crypto.sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static List<String> _unique(Iterable<String> values) {
    final List<String> out = <String>[];
    for (final String value in values) {
      if (!out.contains(value)) out.add(value);
    }
    return out;
  }

  static List<String> _list(Object? json) => json == null
      ? const <String>[]
      : List<String>.unmodifiable(
          (jsonDecode('$json') as List<Object?>).map((Object? s) => '$s'),
        );

  DVOAuthClient _clientFrom(DVRecord record) {
    final Map<String, Object?> v = record.values;
    return DVOAuthClient(
      id: '${v['id']}',
      name: '${v['name']}',
      redirectUris: _list(v['redirect_uris']),
      scopes: _list(v['scopes']),
      isPublic: v['public'] == 1 || v['public'] == true || v['public'] == '1',
      createdAt: _date(v['created_at'])!,
      tenant: v['tenant'] as String?,
      revokedAt: _date(v['revoked_at']),
    );
  }

  static String _stamp(DateTime at) => at.toUtc().toIso8601String();

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse('$value');
}
