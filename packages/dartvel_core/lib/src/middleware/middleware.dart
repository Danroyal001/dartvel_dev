// Middleware system - Next.js inspired
import 'dart:async';
import 'dart:convert';

import '../annotations/annotations.dart' show DVCSRF;
import '../http/wintercg.dart' as dv;
import '../tenancy/tenants.dart';

/// Request context for middleware
class MiddlewareContext {
  final Map<String, Object?> data = {};
  bool _shouldContinue = true;

  void abort() {
    _shouldContinue = false;
  }

  bool get shouldContinue => _shouldContinue;
}

/// Middleware function type
typedef Middleware = FutureOr<void> Function(
  Object? request,
  MiddlewareContext context,
);

typedef ClientIdentifier = String Function(Object? request);

/// Middleware chain executor
class MiddlewareChain {
  final List<Middleware> _middleware = [];

  void use(Middleware middleware) {
    _middleware.add(middleware);
  }

  Future<MiddlewareContext> execute(Object? request) async {
    final context = MiddlewareContext();

    for (final middleware in _middleware) {
      if (!context.shouldContinue) break;
      await middleware(request, context);
    }

    return context;
  }
}

/// Common middleware implementations
class CommonMiddleware {
  /// CORS middleware
  static Middleware cors({
    List<String> allowedOrigins = const ['*'],
    List<String> allowedMethods = const [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH'
    ],
    List<String> allowedHeaders = const ['*'],
  }) {
    return (request, context) {
      // Set CORS headers on response
      context.data['cors'] = {
        'allowedOrigins': allowedOrigins,
        'allowedMethods': allowedMethods,
        'allowedHeaders': allowedHeaders,
      };
    };
  }

  /// Authentication middleware
  static Middleware auth({
    required Future<String?> Function(Object? request) getUserId,
  }) {
    return (request, context) async {
      final userId = await getUserId(request);
      if (userId == null) {
        context.abort();
        context.data['authError'] = 'Unauthorized';
      } else {
        context.data['userId'] = userId;
      }
    };
  }

  /// Rate limiting middleware
  static Middleware rateLimit({
    int maxRequests = 100,
    Duration window = const Duration(minutes: 1),
    ClientIdentifier? clientIdentifier,
  }) {
    final Map<String, List<DateTime>> requestsMap = {};

    return (request, context) {
      final clientId =
          clientIdentifier?.call(request) ?? _clientIdentifier(request);

      final now = DateTime.now();
      final requests = requestsMap[clientId] ?? [];

      // Remove old requests
      requests.removeWhere((t) => now.difference(t) > window);

      if (requests.length >= maxRequests) {
        context.abort();
        context.data['rateLimitError'] = 'Too many requests';
      } else {
        requests.add(now);
        requestsMap[clientId] = requests;
      }
    };
  }

  /// Logging middleware
  static Middleware logger() {
    return (request, context) {
      final method = _requestMethod(request);
      final path = _requestPath(request);
      // ignore: avoid_print
      print('[${DateTime.now()}] $method $path');
    };
  }

  /// Request timing middleware
  static Middleware timing() {
    return (request, context) {
      context.data['startTime'] = DateTime.now();
    };
  }

  /// Body parser middleware
  static Middleware bodyParser() {
    return (request, context) async {
      context.data['parsedBody'] = await _parseBody(request);
    };
  }

  /// Security headers middleware
  static Middleware securityHeaders() {
    return (request, context) {
      context.data['securityHeaders'] = {
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'X-XSS-Protection': '1; mode=block',
        'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
      };
    };
  }

  /// Compression middleware
  static Middleware compression() {
    return (request, context) {
      context.data['enableCompression'] = true;
    };
  }

  /// CSRF validation middleware.
  ///
  /// State-changing methods must present the token in the
  /// `x-dartvel-csrf-token` header. When [issuedToken] is provided it resolves
  /// the token the server issued for this request's session and the header
  /// must equal it — format checks alone accept any well-shaped forgery.
  /// Without it, the header is compared against the `_dv_csrf` body field
  /// (double-submit), so a cross-site form that cannot read the page still
  /// cannot forge a matching pair.
  static Middleware csrf({
    FutureOr<String?> Function(Object? request)? issuedToken,
  }) {
    const validator = DVCSRF();
    return (request, context) async {
      final method = _requestMethod(request);
      if (!validator.requiresValidation(method)) return;

      final headerToken = _requestHeaders(request)[DVCSRF.headerName];
      String? expected;
      if (issuedToken != null) {
        expected = await issuedToken(request);
      } else {
        final body = await _parseBody(request);
        expected = body is Map ? body[DVCSRF.fieldName]?.toString() : null;
      }

      final valid = validator.validate(headerToken, bodyToken: expected) &&
          expected != null;
      if (!valid) {
        context.abort();
        context.data['csrfError'] = 'CSRF token missing or invalid';
      }
    };
  }

  /// Idempotency-key middleware.
  ///
  /// A request carrying an `Idempotency-Key` header records its key; a repeat
  /// of the same key within [window] is flagged as a replay and given the
  /// stored response, so retrying a payment cannot charge twice. Keys are
  /// scoped to method + path: the same key on a different endpoint is a
  /// different operation.
  static Middleware idempotency({
    Duration window = const Duration(hours: 24),
    bool require = false,
  }) {
    final seen = <String, ({DateTime at, Object? response})>{};

    return (request, context) {
      final method = _requestMethod(request);
      // Safe methods are naturally idempotent; a key on a GET is a no-op.
      if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') return;

      final key = _requestHeaders(request)['idempotency-key'];
      if (key == null || key.trim().isEmpty) {
        if (require) {
          context.abort();
          context.data['idempotencyError'] =
              'This endpoint requires an Idempotency-Key header.';
        }
        return;
      }

      final now = DateTime.now();
      seen.removeWhere((_, entry) => now.difference(entry.at) > window);

      final scoped = '$method ${_requestPath(request)} ${key.trim()}';
      final previous = seen[scoped];
      if (previous != null) {
        context.abort();
        context.data['idempotentReplay'] = true;
        context.data['idempotentResponse'] = previous.response;
        return;
      }
      seen[scoped] = (at: now, response: null);
      context.data['idempotencyKey'] = key.trim();
      // The handler stores its response for replays through this callback.
      context.data['recordIdempotentResponse'] = (Object? response) {
        seen[scoped] = (at: now, response: response);
      };
    };
  }

  /// Locale negotiation middleware.
  ///
  /// Resolution order: `?locale=` query parameter, then `Accept-Language`
  /// against [supported], then [fallback]. Matching tries the exact tag first
  /// and then the bare language, so `en-GB` finds `en` when only `en` ships.
  static Middleware locale({
    List<String> supported = const <String>['en'],
    String? fallback,
  }) {
    final normalized = <String, String>{
      for (final tag in supported) tag.toLowerCase(): tag,
    };
    final defaultLocale = fallback ?? supported.first;

    String? match(String tag) {
      final lower = tag.toLowerCase();
      final exact = normalized[lower];
      if (exact != null) return exact;
      return normalized[lower.split('-').first];
    }

    return (request, context) {
      final query = _requestUri(request).queryParameters['locale'];
      if (query != null) {
        final resolved = match(query);
        if (resolved != null) {
          context.data['locale'] = resolved;
          return;
        }
      }

      final header = _requestHeaders(request)['accept-language'];
      if (header != null) {
        // "fr-CH, fr;q=0.9, en;q=0.8" — order carries the preference; the
        // q-values arrive already sorted from every mainstream browser.
        for (final part in header.split(',')) {
          final tag = part.split(';').first.trim();
          if (tag.isEmpty || tag == '*') continue;
          final resolved = match(tag);
          if (resolved != null) {
            context.data['locale'] = resolved;
            return;
          }
        }
      }

      context.data['locale'] = defaultLocale;
    };
  }

  /// Feature-flag middleware.
  ///
  /// [flags] resolves each flag for the request — a lookup table, a percentage
  /// rollout, a tenant check. The resolved set lands in
  /// `context.data['featureFlags']` so later middleware and handlers branch on
  /// it without re-resolving.
  static Middleware featureFlags({
    required Map<String, FutureOr<bool> Function(Object? request)> flags,
  }) {
    return (request, context) async {
      final enabled = <String>{};
      for (final entry in flags.entries) {
        if (await entry.value(request)) enabled.add(entry.key);
      }
      context.data['featureFlags'] = enabled;
    };
  }

  /// Maintenance-mode middleware.
  ///
  /// While [isDown] reports true, requests abort with a `maintenanceError`
  /// unless the path is in [allowedPaths] (health checks must stay
  /// reachable) or the request carries the bypass secret in
  /// `x-dartvel-maintenance-bypass` (operators need to see the site they are
  /// fixing).
  static Middleware maintenance({
    required FutureOr<bool> Function() isDown,
    List<String> allowedPaths = const <String>['/health'],
    String? bypassSecret,
  }) {
    return (request, context) async {
      if (!await isDown()) return;

      final path = _requestPath(request);
      if (allowedPaths.contains(path)) return;

      if (bypassSecret != null &&
          _requestHeaders(request)['x-dartvel-maintenance-bypass'] ==
              bypassSecret) {
        return;
      }

      context.abort();
      context.data['maintenanceError'] =
          'The application is down for maintenance.';
    };
  }

  /// Tenant resolution middleware.
  ///
  /// Reads the tenant from the request through the configured
  /// [DVTenants.source] and makes it current for the rest of the chain. With
  /// [require] set, a request that names no tenant is aborted rather than
  /// served the default tenant's data.
  static Middleware tenant({bool require = false}) {
    return (request, context) {
      const tenants = DVTenants();
      final resolved = tenants.resolve(
        _requestUri(request),
        headers: _requestHeaders(request),
      );

      if (resolved == null && require) {
        context.abort();
        context.data['tenantError'] = 'No tenant could be resolved from the '
            'request (source: ${tenants.source.name}).';
        return;
      }

      tenants.currentTenant = resolved ?? DVTenants.defaultTenant;
      context.data['tenant'] = tenants.currentTenant;
    };
  }
}

/// The full request URI, which tenant resolution needs — the host carries the
/// subdomain, and [_requestPath] deliberately returns only the path.
Uri _requestUri(Object? request) {
  if (request is Uri) return request;
  if (request is dv.Request) return request.url;
  if (request is Map<String, Object?>) {
    final url = request['url'];
    if (url is Uri) return url;
    if (url is String) {
      final parsed = Uri.tryParse(url);
      if (parsed != null) return parsed;
    }
    final host = request['host'];
    if (host is String && host.trim().isNotEmpty) {
      return Uri(scheme: 'https', host: host.trim(), path: _requestPath(request));
    }
  }
  return Uri(path: _requestPath(request));
}

String _clientIdentifier(Object? request) {
  final headers = _requestHeaders(request);
  final forwardedFor = headers['x-forwarded-for'];
  if (forwardedFor != null && forwardedFor.trim().isNotEmpty) {
    return forwardedFor.split(',').first.trim();
  }

  for (final name in const [
    'cf-connecting-ip',
    'x-real-ip',
    'fastly-client-ip',
    'true-client-ip',
  ]) {
    final value = headers[name];
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }

  final forwarded = headers['forwarded'];
  if (forwarded != null) {
    final match = RegExp(r'for="?([^;,"]+)"?').firstMatch(forwarded);
    final value = match?.group(1);
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  if (request is Map<String, Object?>) {
    for (final key in const ['clientId', 'client_id', 'remoteAddress', 'ip']) {
      final value = request[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }

  final method = _requestMethod(request);
  final path = _requestPath(request);
  return '$method $path';
}

String _requestMethod(Object? request) {
  if (request is dv.Request) return request.method.toUpperCase();
  if (request is Map<String, Object?>) {
    final value = request['method'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim().toUpperCase();
    }
  }
  return 'GET';
}

String _requestPath(Object? request) {
  if (request is dv.Request) {
    return request.url.path.isEmpty ? '/' : request.url.path;
  }
  if (request is Uri) {
    return request.path.isEmpty ? '/' : request.path;
  }
  if (request is Map<String, Object?>) {
    final path = request['path'];
    if (path is String && path.trim().isNotEmpty) {
      return path.trim();
    }
    final url = request['url'];
    if (url is Uri) {
      return url.path.isEmpty ? '/' : url.path;
    }
    if (url is String && url.trim().isNotEmpty) {
      final parsed = Uri.tryParse(url);
      return parsed?.path.isNotEmpty == true ? parsed!.path : url.trim();
    }
  }
  return '/';
}

Map<String, String> _requestHeaders(Object? request) {
  if (request is dv.Request) return request.headers.singleValueMap;
  if (request is Map<String, Object?>) {
    final headers = request['headers'];
    if (headers is Map<String, String>) {
      return {
        for (final entry in headers.entries)
          entry.key.toLowerCase(): entry.value,
      };
    }
    if (headers is Map<String, Object?>) {
      return {
        for (final entry in headers.entries)
          if (entry.value != null) entry.key.toLowerCase(): '${entry.value}',
      };
    }
  }
  return const <String, String>{};
}

Future<Object?> _parseBody(Object? request) async {
  if (request is! dv.Request) return const <String, Object?>{};

  final contentType = request.headers.get('content-type') ?? '';
  if (contentType.startsWith('application/json')) {
    final text = await request.body.text();
    if (text.trim().isEmpty) return const <String, Object?>{};
    final value = jsonDecode(text);
    return value is Object ? value : const <String, Object?>{};
  }

  if (contentType.startsWith('application/x-www-form-urlencoded')) {
    final text = await request.body.text();
    return Uri.splitQueryString(text);
  }

  return const <String, Object?>{};
}

/// Route-specific middleware configuration
class RouteMiddleware {
  final String path;
  final List<Middleware> middleware;

  const RouteMiddleware(this.path, this.middleware);

  bool matches(String requestPath) {
    // Simple prefix matching
    return requestPath.startsWith(path);
  }
}

/// Global middleware manager
class MiddlewareManager {
  static final _instance = MiddlewareManager._();
  MiddlewareManager._();

  static MiddlewareManager get instance => _instance;

  final MiddlewareChain _globalChain = MiddlewareChain();
  final List<RouteMiddleware> _routeMiddleware = [];

  void useGlobal(Middleware middleware) {
    _globalChain.use(middleware);
  }

  void useForRoute(String path, Middleware middleware) {
    _routeMiddleware.add(RouteMiddleware(path, [middleware]));
  }

  Future<MiddlewareContext> execute(Object? request, String path) async {
    // Execute global middleware
    final context = await _globalChain.execute(request);

    if (!context.shouldContinue) return context;

    // Execute route-specific middleware
    for (final route in _routeMiddleware) {
      if (route.matches(path)) {
        for (final middleware in route.middleware) {
          if (!context.shouldContinue) break;
          await middleware(request, context);
        }
      }
    }

    return context;
  }
}
