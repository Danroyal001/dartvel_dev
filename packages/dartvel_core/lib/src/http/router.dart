import '../observability/observability.dart';
import 'wintercg.dart';

typedef Handler = Future<Response> Function(Request);

class Router {
  final _routes = <_Route>[];

  Router get(String pattern, Handler h) {
    _routes.add(_Route('GET', pattern, h));
    return this;
  }

  Router post(String pattern, Handler h) {
    _routes.add(_Route('POST', pattern, h));
    return this;
  }

  Router put(String pattern, Handler h) {
    _routes.add(_Route('PUT', pattern, h));
    return this;
  }

  Router delete(String pattern, Handler h) {
    _routes.add(_Route('DELETE', pattern, h));
    return this;
  }

  Router head(String pattern, Handler h) {
    _routes.add(_Route('HEAD', pattern, h));
    return this;
  }

  Router any(String pattern, Handler h) {
    _routes.add(_Route('*', pattern, h));
    return this;
  }

  Future<Response> call(Request req) async {
    for (final route in _routes) {
      if (route.method != '*' && route.method != req.method) continue;
      final match = route.pattern.exec(req.url);
      if (match != null) {
        req.params
          ..clear()
          ..addAll(match.pathname);
        return route.handler(req);
      }
    }
    // Reached only when the application registered no route of its own for
    // it: the built-ins are a fallback, and an application that wants a
    // deeper check or a different shape must be able to have one.
    if (req.method == 'GET' && req.url.path == '/health') {
      // It used to return the literal {'status':'ok'}, which checked nothing
      // and so could not fail. A health check that cannot fail is worse than
      // none: a load balancer keeps routing to an instance whose database is
      // gone and the dashboard stays green through the outage.
      final DVHealthReport report = await DVObservability.health.reportAsync();
      return Response.json(report.toJson(), status: report.httpStatus);
    }
    if (req.method == 'GET' && req.url.path == '/metrics') {
      return Response.text(
        DVObservability.render(),
        headers: Headers()
          // Not decoration: a scraper sent application/json refuses the
          // payload, and the version is part of what it negotiates on.
          ..set('content-type',
              'text/plain; version=0.0.4; charset=utf-8'),
      );
    }
    if (req.method == 'GET' &&
        (req.url.path == '/healths' || req.url.path == '/healthz')) {
      return Response.redirect('/health', 308);
    }
    return Response.text('Not Found',
        status: 404,
        headers: Headers()..set('content-type', 'text/plain; charset=utf-8'));
  }
}

class _Route {
  final String method;
  final URLPattern pattern;
  final Handler handler;
  _Route(this.method, String pattern, this.handler)
      : pattern = URLPattern(pattern);
}
