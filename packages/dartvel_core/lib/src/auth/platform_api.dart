/// The platform API in a running backend: the authentication stage of the
/// generated request lifecycle, over the application's own database.
///
/// `DVApiKeys` and `DVOAuthProvider` could each check a credential, and no
/// generated route asked either, so a key presented to a real backend was a
/// header nobody read. The generated backend installs this where it starts
/// and calls [DVPlatformApi.authenticateRequest] on every route, so a
/// third-party request runs the same lifecycle as any other: the credential
/// resolves to a [DVApiPrincipal] here, and its scopes are the policy context
/// at the authorization stage (`DVBackendPolicy.allows`).
///
/// What goes wrong here goes wrong silently, so each guard says where it is:
///
/// * only a bearer credential shaped like a Dartvel key (`dvk_`) or access
///   token (`dvat_`) is this stage's to judge -- any other `Authorization`
///   header is the application's own auth, and passes through untouched;
/// * the credential is checked against the tenant the request resolved to,
///   so a key for one tenant does not authenticate a request for another;
/// * every refusal of a credential is the same 401 with the same body, so a
///   caller cannot tell a revoked key from an unknown one or a wrong tenant;
/// * nothing presented is ever logged or echoed, including when the database
///   fails while checking it.
library dartvel_core.auth.platform_api;

import 'dart:async';

import '../database/adapter.dart';
import '../middleware/middleware.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import 'api_keys.dart';
import 'api_scopes.dart';
import 'oauth_provider.dart';
import 'platform_api_config.dart';

/// What the authentication stage made of a request.
class DVApiAuthentication {
  const DVApiAuthentication._({
    this.principal,
    this.status,
    this.challenge,
    this.message,
  });

  /// The request carried no platform credential: it is the application's.
  static const DVApiAuthentication none = DVApiAuthentication._();

  const DVApiAuthentication.authenticated(DVApiPrincipal principal)
    : this._(principal: principal);

  const DVApiAuthentication.refused(
    int status,
    String message, {
    String? challenge,
  }) : this._(status: status, message: message, challenge: challenge);

  final DVApiPrincipal? principal;

  /// The status to answer with, when the request is refused.
  final int? status;

  /// The `WWW-Authenticate` value, for a 401.
  final String? challenge;

  /// The fixed text of the refusal. Nothing from the request is in it.
  final String? message;

  bool get refused => status != null;
}

/// The platform API a backend process serves.
class DVPlatformApi {
  DVPlatformApi(
    this.config, {
    required DVDatabaseAdapter? Function() database,
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock;

  /// Every access token the provider issues starts with this.
  static const String accessTokenPrefix = 'dvat_';

  static const String _challenge = 'Bearer error="invalid_token"';

  static DVPlatformApi? _installed;

  /// The platform API this process serves, or null when it declares none.
  static DVPlatformApi? get installed => _installed;

  /// Makes [config] the platform API of this process. Called by the
  /// generated `startBackend`.
  static DVPlatformApi install(
    DVPlatformApiConfig config, {
    required DVDatabaseAdapter? Function() database,
    DateTime Function()? clock,
  }) => _installed = DVPlatformApi(config, database: database, clock: clock);

  /// Takes the installed platform API away, for a test.
  static void uninstall() => _installed = null;

  final DVPlatformApiConfig config;
  final DVDatabaseAdapter? Function() _database;
  final DateTime Function()? _clock;

  Future<_DVPlatformRuntime?>? _runtime;

  /// The authentication stage for a request whose `Authorization` header is
  /// [authorization], on the tenant the request resolved to.
  ///
  /// Without an installed platform API a platform credential is refused with
  /// 503 rather than ignored: ignoring it would hand the route a request its
  /// caller believes is authenticated and nothing checked.
  static Future<DVApiAuthentication> authenticateRequest(
    String? authorization,
  ) async {
    if (credentialOf(authorization) == null) return DVApiAuthentication.none;
    final DVPlatformApi? platform = _installed;
    if (platform == null) {
      return const DVApiAuthentication.refused(503, 'Service Unavailable');
    }
    return platform.authenticate(authorization);
  }

  /// The platform credential in an `Authorization` header, or null when it
  /// carries none -- which includes the application's own bearer tokens.
  static String? credentialOf(String? authorization) {
    if (authorization == null) return null;
    final String value = authorization.trim();
    if (value.length < 7 || value.substring(0, 7).toLowerCase() != 'bearer ') {
      return null;
    }
    final String credential = value.substring(7).trim();
    if (credential.startsWith(DVApiKeys.keyPrefix) ||
        credential.startsWith(accessTokenPrefix)) {
      return credential;
    }
    return null;
  }

  /// Resolves [authorization] to a principal on [tenant], or the current
  /// tenant when none is given.
  Future<DVApiAuthentication> authenticate(
    String? authorization, {
    String? tenant,
  }) async {
    final String? credential = credentialOf(authorization);
    if (credential == null) return DVApiAuthentication.none;
    final String requested = tenant ?? const DVTenants().currentTenant;
    try {
      final _DVPlatformRuntime? runtime = await _ready();
      if (runtime == null) {
        return const DVApiAuthentication.refused(503, 'Service Unavailable');
      }
      final DVApiPrincipal? principal =
          credential.startsWith(DVApiKeys.keyPrefix)
          ? await runtime.keys.authenticate(credential, tenant: requested)
          : await runtime.oauth?.authenticate(credential, tenant: requested);
      if (principal == null) {
        return const DVApiAuthentication.refused(
          401,
          'Unauthorized',
          challenge: _challenge,
        );
      }
      final MiddlewareContext context = MiddlewareContext()
        ..data[DVApiKeys.principalKey] = principal;
      await runtime.rateLimit(null, context);
      if (!context.shouldContinue) {
        return context.data['diagnostic'] == 'DV-APIKEY-006'
            ? const DVApiAuthentication.refused(429, 'Too Many Requests')
            // A plan the key names and the declaration does not: refused
            // rather than let through unmetered.
            : const DVApiAuthentication.refused(403, 'Forbidden');
      }
      return DVApiAuthentication.authenticated(principal);
    } on Object catch (error) {
      // The type only. An adapter's message can quote what it was given.
      DVObservability.logger.error(
        'Platform API authentication failed (${error.runtimeType}); the '
        'request was refused.',
      );
      return const DVApiAuthentication.refused(503, 'Service Unavailable');
    }
  }

  /// The keys over this process's database, schema ensured.
  Future<DVApiKeys> keys() async => (await _require()).keys;

  /// The OAuth provider, or null when `dartvel.platformApi.oauth` is off.
  Future<DVOAuthProvider?> oauthProvider() async => (await _require()).oauth;

  Future<_DVPlatformRuntime> _require() async {
    final _DVPlatformRuntime? runtime = await _ready();
    if (runtime == null) {
      throw StateError(
        'The platform API needs a database, and this process has none '
        'configured. Configure DV.Database or set DATABASE_URL.',
      );
    }
    return runtime;
  }

  Future<_DVPlatformRuntime?> _ready() {
    final Future<_DVPlatformRuntime?>? started = _runtime;
    if (started != null) return started;
    final DVDatabaseAdapter? database = _database();
    if (database == null) return Future<_DVPlatformRuntime?>.value();
    final Future<_DVPlatformRuntime?> starting = _start(database);
    _runtime = starting;
    // A start that failed is tried again by the next request rather than
    // remembered as a failure for the life of the process.
    unawaited(
      starting.catchError((Object _) {
        if (identical(_runtime, starting)) _runtime = null;
        return null;
      }),
    );
    return starting;
  }

  Future<_DVPlatformRuntime?> _start(DVDatabaseAdapter database) async {
    final DVApiKeys keys = DVApiKeys(
      database: database,
      scopes: config.scopes,
      requireExpiry: config.requireExpiry,
      clock: _clock,
    );
    final DVOAuthSettings? settings = config.oauth;
    final DVOAuthProvider? oauth = settings == null
        ? null
        : DVOAuthProvider(
            database: database,
            scopes: config.scopes,
            apiKeys: keys,
            codeLifetime: settings.codeLifetime,
            accessTokenLifetime: settings.accessTokenLifetime,
            refreshTokenLifetime: settings.refreshTokenLifetime,
            clock: _clock,
          );
    await keys.ensureSchema();
    await oauth?.ensureSchema();
    return _DVPlatformRuntime(
      keys: keys,
      oauth: oauth,
      rateLimit: keys.rateLimit(config.ratePlans),
    );
  }
}

class _DVPlatformRuntime {
  const _DVPlatformRuntime({
    required this.keys,
    required this.oauth,
    required this.rateLimit,
  });

  final DVApiKeys keys;
  final DVOAuthProvider? oauth;
  final Middleware rateLimit;
}
