// Middleware system - Next.js inspired
import 'dart:async';

/// Request context for middleware
class MiddlewareContext {
  final Map<String, dynamic> data = {};
  bool _shouldContinue = true;

  void abort() {
    _shouldContinue = false;
  }

  bool get shouldContinue => _shouldContinue;
}

/// Middleware function type
typedef Middleware = FutureOr<void> Function(
  dynamic request,
  MiddlewareContext context,
);

/// Middleware chain executor
class MiddlewareChain {
  final List<Middleware> _middleware = [];

  void use(Middleware middleware) {
    _middleware.add(middleware);
  }

  Future<MiddlewareContext> execute(dynamic request) async {
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
    required Future<String?> Function(dynamic request) getUserId,
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
  }) {
    final Map<String, List<DateTime>> requestsMap = {};

    return (request, context) {
      // Note: Get client IP
      final clientId = 'client'; // Placeholder

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
      final method = 'GET'; // Note: Extract from request
      final path = '/'; // Note: Extract from request
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
      // Note: Parse request body based on content-type
      context.data['parsedBody'] = {};
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

  Future<MiddlewareContext> execute(dynamic request, String path) async {
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
