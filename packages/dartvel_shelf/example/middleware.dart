// Middleware is a function from a handler to a handler. There is no special
// type for it: wrap the router's call, or any other handler, and pass the
// result to serve().
//
//   dart run example/middleware.dart
//
//   curl -i http://127.0.0.1:8080/private                        # 401
//   curl -i -H 'x-api-key: secret' http://127.0.0.1:8080/private # 200
//   curl -i http://127.0.0.1:8080/health                         # 200, no key
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

typedef Handler = Future<Response> Function(Request request);
typedef Middleware = Handler Function(Handler inner);

/// Applies [middleware] so the first in the list is the outermost.
Handler pipeline(List<Middleware> middleware, Handler handler) =>
    middleware.reversed.fold(handler, (inner, wrap) => wrap(inner));

/// Adds a Server-Timing header with how long the inner handler took.
Handler timing(Handler inner) => (req) async {
  final clock = Stopwatch()..start();
  final res = await inner(req);
  res.headers.set('server-timing', 'app;dur=${clock.elapsedMilliseconds}');
  return res;
};

/// Refuses requests without the right `x-api-key`, except the health check,
/// which a load balancer calls without credentials.
Middleware requireApiKey(String key) =>
    (inner) => (req) async {
      if (req.url.path == '/health') return inner(req);
      if (req.headers.get('x-api-key') != key) {
        return Response.json({'error': 'unauthorized'}, status: 401);
      }
      return inner(req);
    };

/// Turns an exception into a JSON 500 instead of the server's plain-text one.
Handler jsonErrors(Handler inner) => (req) async {
  try {
    return await inner(req);
  } catch (error) {
    stderr.writeln('${req.method} ${req.url.path} failed: $error');
    return Response.json({'error': 'internal error'}, status: 500);
  }
};

Future<void> main() async {
  final router = Router()
    ..get('/private', (req) async => Response.json({'secret': 42}))
    ..get('/fail', (req) async => throw StateError('broken'));

  final handler = pipeline([
    jsonErrors,
    timing,
    requireApiKey('secret'),
  ], router.call);

  final server = await serve(
    handler,
    host: '127.0.0.1',
    port: 8080,
    routeBodyLimits: router.bodyLimits,
  );
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
