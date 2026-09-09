import 'dart:convert';

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

  /// The paths that are never counted or logged.
  ///
  /// A scrape every fifteen seconds is the loudest client a small service
  /// has. Counting it makes every request-rate graph a picture of Prometheus,
  /// and logging it fills the recent-records buffer with health checks so
  /// there is nothing left of the traffic anyone cares about.
  static const Set<String> _unmeasured = <String>{
    '/health',
    '/healthz',
    '/healths',
    '/metrics',
  };

  Future<Response> call(Request req) async {
    if (_unmeasured.contains(req.url.path) ||
        req.url.path.startsWith('/_dartvel/')) {
      return _dispatch(req);
    }

    final Stopwatch clock = Stopwatch()..start();
    try {
      final Response response = await _dispatch(req);
      clock.stop();
      _record(req, response.status, clock, response.headers.get('traceparent'));
      return response;
    } on Object catch (error, stack) {
      clock.stop();
      // The server layer turns this into a 500 inside a bare `catch (_)`, so
      // if it is not recorded here the exception is gone: no line, no count,
      // and a client holding a 500 nobody can explain.
      _record(req, 500, clock, null, error: error, stackTrace: stack);
      rethrow;
    }
  }

  void _record(
    Request req,
    int status,
    Stopwatch clock,
    String? traceparent, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final double seconds = clock.elapsedMicroseconds / 1000000;
    DVObservability.metrics
        .counter(
          'http_requests_total',
          // Method and status only. The path is what an id is in, and one
          // series per id is how a metrics backend gets killed by the
          // application it is watching -- the router cannot tell `42` from a
          // route segment, so it must not put either in a label.
          <String, String>{'method': req.method, 'status': '$status'},
          'HTTP requests served, by method and response status.',
        )
        .increment();
    DVObservability.metrics
        .histogram(
          'http_request_duration_seconds',
          <String, String>{'method': req.method},
          'How long serving a request took, in seconds.',
        )
        .observe(seconds);

    // The span was created inside the handler, so it is out of scope by now;
    // the header the tracing middleware set on the response is what is left
    // of it. Reading the id back from there is what lets a support ticket
    // quoting a traceparent find the log line for that request.
    final DVTraceContext? context = DVTraceContext.parse(traceparent);
    final Map<String, Object?> fields = <String, Object?>{
      'method': req.method,
      'path': req.url.path,
      'status': status,
      'durationMs': clock.elapsedMicroseconds / 1000,
    };

    if (error != null) {
      DVObservability.logger.error(
        '${req.method} ${req.url.path} failed',
        context: fields,
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    DVObservability.logger.info(
      '${req.method} ${req.url.path} $status',
      context: fields,
      traceId: context?.traceId,
      spanId: context?.parentSpanId,
    );
  }

  Future<Response> _dispatch(Request req) async {
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
    // The diagnostics pair. Off unless the process was started with them on,
    // and a plain 404 when they are off -- a 403 would confirm to whoever is
    // probing that there is a log buffer here worth coming back for.
    if (req.method == 'GET' && req.url.path == '/_dartvel/logs') {
      if (!DVObservability.diagnosticsEndpoints) return _notFound();
      return _ndjson(_tail(
        req,
        DVObservability.recentLogs
            .map((DVLogRecord record) => record.toJson())
            .toList(growable: false),
      ));
    }
    if (req.method == 'GET' && req.url.path == '/_dartvel/traces') {
      if (!DVObservability.diagnosticsEndpoints) return _notFound();
      return _ndjson(_tail(
        req,
        DVObservability.recentSpans
            .map((DVSpan span) => span.toJson())
            .toList(growable: false),
      ));
    }
    return Response.text('Not Found',
        status: 404,
        headers: Headers()..set('content-type', 'text/plain; charset=utf-8'));
  }
}

/// The last `?limit=n` entries, or all of them.
///
/// A bad limit is ignored rather than refused: this is a debugging endpoint,
/// and answering a typo with a 400 helps nobody at three in the morning.
List<Map<String, Object?>> _tail(Request req, List<Map<String, Object?>> all) {
  final int? limit = int.tryParse(req.url.queryParameters['limit'] ?? '');
  if (limit == null || limit <= 0 || limit >= all.length) return all;
  return all.sublist(all.length - limit);
}

/// Newline-delimited JSON: one record per line.
///
/// Not a JSON array. A reader can start printing from the first line rather
/// than waiting for a closing bracket, and `dartvel logs` can follow a growing
/// response the same way `tail -f` does.
Response _ndjson(List<Map<String, Object?>> records) => Response.text(
      records.map(jsonEncode).join('\n'),
      headers: Headers()
        ..set('content-type', 'application/x-ndjson; charset=utf-8')
        // Never cached, by anything. A stale log window is a wrong answer
        // that looks exactly like a right one.
        ..set('cache-control', 'no-store'),
    );

Response _notFound() => Response.text(
      'Not Found',
      status: 404,
      headers: Headers()..set('content-type', 'text/plain; charset=utf-8'),
    );

class _Route {
  final String method;
  final URLPattern pattern;
  final Handler handler;
  _Route(this.method, String pattern, this.handler)
      : pattern = URLPattern(pattern);
}
