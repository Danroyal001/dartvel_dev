/// Turning a declared middleware key into a decision.
///
/// `@DVUseMiddleware([DVMiddlewares.rateLimit])` had one reader in the whole
/// repository: a validator in the backend generator that threw when the name
/// was not on a whitelist. It checked the spelling and dropped the list.
/// Nothing was stored, nothing was emitted into the generated router, and no
/// request was ever handled differently for having declared any of the
/// nineteen keys.
///
/// The implementations were not missing. `CommonMiddleware.rateLimit`,
/// `.securityHeaders`, `.locale`, `.maintenance`, `.tenant`, `.idempotency`
/// and `.featureFlags` are written and unit-tested -- through a chain each
/// test builds by hand. Nothing else ever built one.
///
/// So a key now falls into one of three sets, and every one of them means
/// something:
///
///   * built -- there is a middleware and it runs.
///   * already on -- the route enforces it for every request whether or not
///     the key is declared, so declaring it is redundant rather than wrong.
///   * unbuilt -- nothing implements it. The generator refuses the build and
///     says what to use instead. That is the point of this file: nineteen
///     keys that quietly did nothing is worse than nine that say so.
library;

import 'dart:async';

import 'middleware.dart';

/// Configuration the built middleware need, with defaults that are safe when
/// an application sets nothing.
///
/// Deliberately static and small. A middleware key names a behaviour, not a
/// configuration, so the alternative was inventing a per-route argument
/// syntax for an annotation that has never had one.
class DVMiddlewareSettings {
  /// Whether the application is down. Default: it is not.
  static FutureOr<bool> Function() maintenanceIsDown = _notDown;

  /// Paths that stay reachable while it is down.
  static List<String> maintenanceAllows = const <String>['/health'];

  /// The header value that lets an operator through a maintenance window.
  static String? maintenanceBypassSecret;

  /// Flags resolved per request for `DVMiddlewares.featureFlags`.
  static Map<String, FutureOr<bool> Function(Object? request)> featureFlags =
      <String, FutureOr<bool> Function(Object? request)>{};

  /// Locales `DVMiddlewares.locale` negotiates against.
  static List<String> locales = const <String>['en'];

  /// Requests allowed per [rateLimitWindow] per caller.
  static int rateLimitMaxRequests = 100;

  /// The window the limit counts over.
  static Duration rateLimitWindow = const Duration(minutes: 1);

  /// Whether a request that names no tenant is refused rather than served
  /// the default tenant's data.
  static bool requireTenant = false;

  /// Whether a state-changing request must carry an Idempotency-Key.
  static bool requireIdempotencyKey = false;

  /// Who this request is, for `DVMiddlewares.auth`.
  ///
  /// Null means nobody taught the application how to answer, and the key
  /// then refuses every request rather than admitting them all. Default deny
  /// is the same answer `DVBackendPolicy` gives to a policy nobody
  /// registered, and for the same reason: a route that declared
  /// authentication and got none is not a public route.
  static Future<String?> Function(Object? request)? authUserId;

  static bool _notDown() => false;
}

/// Keys with an implementation behind them.
const Set<String> dvMiddlewareKeysBuilt = <String>{
  'auth',
  'tenant',
  'rateLimit',
  'requestLogging',
  'securityHeaders',
  'locale',
  'idempotency',
  'featureFlags',
  'maintenance',
};

/// Keys the route already enforces for every request.
///
/// CSRF is validated in the generated request prelude on every method that
/// changes state, before the handler and before this chain. Declaring the
/// key is redundant, not wrong, so the build accepts it and emits nothing --
/// and this set is why, rather than a silent gap that looks identical.
const Set<String> dvMiddlewareKeysAlwaysOn = <String>{'csrf'};

/// Keys nothing implements, and what to reach for instead.
///
/// The generator refuses a build that declares one of these. A developer who
/// wrote `bodyLimit` has decided large bodies are rejected; serving them is
/// not a smaller failure for having been quiet about it.
const Map<String, String> dvMiddlewareKeysUnbuiltReason = <String, String>{
  'policy': 'Nothing carries the policy name, so this key cannot say which '
      'policy applies. Declare it on the function instead: '
      '@DVBackendFunction(policy: DVPolicies.yourPolicy), which is enforced '
      'per route.',
  'cors': 'CORS is configured for the whole server, not per route. Pass '
      'cors: to the serve call rather than declaring it here.',
  'compression': 'Compression is a server-wide setting decided when the '
      'server starts, so a per-route declaration would change nothing. Pass '
      'compression: to the serve call.',
  'rateLimitCheckout': 'Nothing implements this. It is not a preset of '
      'rateLimit; there is no code behind the name at all. Use '
      'DVMiddlewares.rateLimit.',
  'tracing': 'The tracing helper wraps a handler and returns a response, so '
      'it is not a middleware in this chain. Nothing wires it to this key.',
  'csp': 'No Content-Security-Policy is emitted anywhere, and there is no '
      'configuration surface for the policy string. securityHeaders sends '
      'the fixed headers that do exist.',
  'bodyLimit': 'Nothing enforces a request body size. The body is read '
      'before any limit could be applied.',
  'uploadLimit': 'Nothing enforces an upload size. Multipart parts are read '
      'before any limit could be applied.',
  'cacheTags': 'Nothing implements this. Cache invalidation lives on '
      'DV.Cache.tag and DV.Cache.revalidateTag.',
};

/// Keys nothing implements.
Set<String> get dvMiddlewareKeysUnbuilt =>
    dvMiddlewareKeysUnbuiltReason.keys.toSet();

/// What a middleware puts in `context.data` when it refuses, and the status
/// that refusal is.
const Map<String, int> _refusalStatus = <String, int>{
  'authError': 401,
  'csrfError': 403,
  'tenantError': 400,
  'idempotencyError': 400,
  'idempotentReplay': 409,
  'rateLimitError': 429,
  'maintenanceError': 503,
};

/// What the client is told for each refusal.
///
/// Fixed text. The middleware's own message is not used, because two of them
/// quote the request -- the tenant one names the configured source -- and
/// these strings reach whoever sent the request.
const Map<String, String> _refusalMessage = <String, String>{
  'authError': 'Not authenticated',
  'csrfError': 'CSRF token missing or invalid',
  'tenantError': 'No tenant',
  'idempotencyError': 'An Idempotency-Key header is required',
  'idempotentReplay': 'This request was already handled',
  'rateLimitError': 'Too many requests',
  'maintenanceError': 'Down for maintenance',
};

/// The outcome of running a route's declared middleware.
class DVMiddlewareResult {
  const DVMiddlewareResult({
    required this.allowed,
    required this.status,
    required this.message,
    required this.headers,
    required this.data,
  });

  /// Whether the handler should run.
  final bool allowed;

  /// The status to answer with when it should not.
  final int status;

  /// What to say when it should not. Never contains anything from the
  /// request.
  final String message;

  /// Headers to add to the handler's response.
  final Map<String, String> headers;

  /// What the chain resolved, for the handler to read: the locale, the
  /// tenant, the enabled flags.
  final Map<String, Object?> data;
}

/// Built middleware, kept between requests.
///
/// The rate limiter and the idempotency store keep their state in the
/// closure the factory returns, so building one per request would throw the
/// counter away every time and the limit would never be reached. That is a
/// bug that passes every test written against a single request.
final Map<String, Middleware> _built = <String, Middleware>{};

/// The middleware a key builds, or null when nothing implements it.
Middleware? dvMiddlewareFor(String key) {
  if (!dvMiddlewareKeysBuilt.contains(key)) return null;
  return _built.putIfAbsent(key, () => _build(key));
}

Middleware _build(String key) {
  switch (key) {
    case 'auth':
      return CommonMiddleware.auth(getUserId: _resolveUser);
    case 'tenant':
      return CommonMiddleware.tenant(
        require: DVMiddlewareSettings.requireTenant,
      );
    case 'rateLimit':
      return CommonMiddleware.rateLimit(
        maxRequests: DVMiddlewareSettings.rateLimitMaxRequests,
        window: DVMiddlewareSettings.rateLimitWindow,
      );
    case 'requestLogging':
      return CommonMiddleware.logger();
    case 'securityHeaders':
      return CommonMiddleware.securityHeaders();
    case 'locale':
      return CommonMiddleware.locale(
        supported: DVMiddlewareSettings.locales,
      );
    case 'idempotency':
      return CommonMiddleware.idempotency(
        require: DVMiddlewareSettings.requireIdempotencyKey,
      );
    case 'featureFlags':
      return CommonMiddleware.featureFlags(
        flags: DVMiddlewareSettings.featureFlags,
      );
    case 'maintenance':
      return CommonMiddleware.maintenance(
        isDown: () => DVMiddlewareSettings.maintenanceIsDown(),
        allowedPaths: DVMiddlewareSettings.maintenanceAllows,
        bypassSecret: DVMiddlewareSettings.maintenanceBypassSecret,
      );
  }
  // Unreachable while the switch covers dvMiddlewareKeysBuilt, and the test
  // that walks that set is what keeps it so.
  throw ArgumentError.value(key, 'key', 'is listed as built and is not.');
}

Future<String?> _resolveUser(Object? request) async {
  final Future<String?> Function(Object? request)? resolve =
      DVMiddlewareSettings.authUserId;
  if (resolve == null) return null;
  return resolve(request);
}

/// Runs a route's declared middleware in the order it declared them.
///
/// Throws when a key nothing implements reaches this: the generator refuses
/// such a build, and a request arriving with one anyway means a generated
/// file is older than the framework running it. Serving it as though the
/// middleware applied is the failure this whole file exists to end.
Future<DVMiddlewareResult> dvRunMiddlewares(
  List<String> keys,
  Object? request,
) async {
  final MiddlewareChain chain = MiddlewareChain();
  for (final String key in keys) {
    if (dvMiddlewareKeysAlwaysOn.contains(key)) continue;
    final Middleware? middleware = dvMiddlewareFor(key);
    if (middleware == null) {
      throw ArgumentError.value(
        key,
        'middleware',
        dvMiddlewareKeysUnbuiltReason[key] ??
            'is not a middleware this version of Dartvel implements.',
      );
    }
    chain.use(middleware);
  }

  final MiddlewareContext context = await chain.execute(request);

  for (final MapEntry<String, int> refusal in _refusalStatus.entries) {
    if (!context.data.containsKey(refusal.key)) continue;
    return DVMiddlewareResult(
      allowed: false,
      status: refusal.value,
      message: _refusalMessage[refusal.key]!,
      // Nothing from a refused chain decorates a response that is not being
      // sent.
      headers: const <String, String>{},
      data: const <String, Object?>{},
    );
  }

  final Map<String, String> headers = <String, String>{};
  final Object? security = context.data['securityHeaders'];
  if (security is Map) {
    for (final MapEntry<Object?, Object?> entry in security.entries) {
      final Object? name = entry.key;
      final Object? value = entry.value;
      if (name is String && value is String) headers[name] = value;
    }
  }

  return DVMiddlewareResult(
    allowed: context.shouldContinue,
    status: 200,
    message: '',
    headers: headers,
    data: Map<String, Object?>.unmodifiable(context.data),
  );
}

/// Forgets every built middleware and restores the default settings.
///
/// The rate limiter and the idempotency store are deliberately long-lived,
/// which makes them shared state between tests. This is how a test gets a
/// fresh one.
void dvResetMiddlewareRuntime() {
  _built.clear();
  DVMiddlewareSettings.maintenanceIsDown = DVMiddlewareSettings._notDown;
  DVMiddlewareSettings.maintenanceAllows = const <String>['/health'];
  DVMiddlewareSettings.maintenanceBypassSecret = null;
  DVMiddlewareSettings.featureFlags =
      <String, FutureOr<bool> Function(Object? request)>{};
  DVMiddlewareSettings.locales = const <String>['en'];
  DVMiddlewareSettings.rateLimitMaxRequests = 100;
  DVMiddlewareSettings.rateLimitWindow = const Duration(minutes: 1);
  DVMiddlewareSettings.requireTenant = false;
  DVMiddlewareSettings.requireIdempotencyKey = false;
  DVMiddlewareSettings.authUserId = null;
}
