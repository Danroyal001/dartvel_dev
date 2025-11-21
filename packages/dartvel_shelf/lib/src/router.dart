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
    if (req.method == 'GET' && req.url.path == '/health') {
      return Response.json({'status': 'ok'});
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
