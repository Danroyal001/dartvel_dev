import 'dart:async';
import 'dart:convert';

import '../observability/observability.dart';
import 'client_address.dart';
import 'peer_address.dart';
import 'wintercg.dart';

typedef Handler = Future<Response> Function(Request);

/// A route as the native server needs to know it: its method, its pattern,
/// and the largest body it reads.
final class DVRouteBodyLimit {
  const DVRouteBodyLimit(this.method, this.pattern, this.maxBytes);

  /// `GET`, `POST` and so on, or `*` for a route that takes any method.
  final String method;

  /// The pattern as the route was registered.
  final String pattern;

  /// Bytes this route reads, or null for the server's `maxBodyBytes`.
  final int? maxBytes;
}

/// Routes a request to the first route whose method and pattern match it.
///
/// Each registration takes `maxBodyBytes`, the largest body that route reads
/// when it needs more (or less) than the server's own limit. The native side
/// reads a body before any Dart runs, so it has to be told: serve() takes
/// [bodyLimits] as `routeBodyLimits`.
class Router {
  final _routes = <_Route>[];

  Router get(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('GET', pattern, h, maxBodyBytes);

  Router post(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('POST', pattern, h, maxBodyBytes);

  Router put(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('PUT', pattern, h, maxBodyBytes);

  Router delete(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('DELETE', pattern, h, maxBodyBytes);

  Router head(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('HEAD', pattern, h, maxBodyBytes);

  Router any(String pattern, Handler h, {int? maxBodyBytes}) =>
      _add('*', pattern, h, maxBodyBytes);

  Router _add(String method, String pattern, Handler h, int? maxBodyBytes) {
    // Refused here rather than read as "the server's limit": somebody who
    // wrote a number meant that number.
    if (maxBodyBytes != null && maxBodyBytes <= 0) {
      throw ArgumentError.value(maxBodyBytes, 'maxBodyBytes',
          'must be positive: a route that reads no body declares no limit');
    }
    _routes.add(_Route(method, pattern, h, maxBodyBytes));
    return this;
  }

  /// Every route, in the order requests are dispatched to them, with the
  /// limit it declared or null for the server's.
  ///
  /// All of them rather than only the limited ones: the native side matches
  /// first route first, as [call] does, so a route with no limit of its own
  /// keeps the server's limit for the requests it takes even when a later
  /// route with a larger limit would match them too.
  List<DVRouteBodyLimit> get bodyLimits => List<DVRouteBodyLimit>.unmodifiable(
      <DVRouteBodyLimit>[
        for (final _Route route in _routes)
          DVRouteBodyLimit(route.method, route.source, route.maxBodyBytes),
      ]);

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

  Future<Response> call(Request req) {
    // Recorded once, by whoever answers last. A server that tries the router
    // first and renders the page itself when the router has no route for it
    // records the status it sent, and the router's 404 on the way is not a
    // request of its own.
    if (Zone.current[_measuredOutside] == true) return _dispatch(req);
    return measure(req, () => _dispatch(req));
  }

  static final Object _measuredOutside = Object();

  // The zone a measured request runs in: the caller's, with the mark that
  // tells a router inside it not to record the request again. Forked once
  // for the zone requests come from -- every request of a server comes from
  // the same one -- rather than once per request.
  static Zone? _measuringParent;
  static Zone? _measuring;

  static Zone _measuringZone() {
    final Zone current = Zone.current;
    if (!identical(current, _measuringParent)) {
      _measuringParent = current;
      _measuring = current.fork(
          zoneValues: <Object?, Object?>{_measuredOutside: true});
    }
    return _measuring!;
  }

  /// [accessLogsPerSecond] unless the process says otherwise.
  static const int defaultAccessLogsPerSecond = 100;

  /// Access records written one per request in any one second; the rest of
  /// that second is one summary line with their count. Answers of 500 and
  /// above, and failures, are always written one each, and the request
  /// metrics count every request whatever this is. Zero writes no individual
  /// access lines below 500. `DARTVEL_ACCESS_LOGS_PER_SECOND` sets it for a
  /// server.
  ///
  /// A line per request at volume costs more than the request: the JSON
  /// encoding, the redaction scans and the write to stdout took more of the
  /// isolate than the handlers did, and a shipper billed per line turns it
  /// into a bill.
  static int accessLogsPerSecond = defaultAccessLogsPerSecond;

  static final _AccessLogBudget _accessBudget = _AccessLogBudget();

  /// Runs [serve] for [req] and records the request once, with the status
  /// [serve] answered: the count in `http_requests_total`, the duration and
  /// the access record.
  ///
  /// For a server that passes a request through a [Router] and may answer it
  /// some other way afterwards: a web-server build gives every page to the
  /// router first, gets a 404 because pages are not routes, and renders the
  /// page with 200. Measured at the router, every such page was logged and
  /// counted as a 404. A router called inside [serve] records nothing itself.
  static Future<Response> measure(
      Request req, Future<Response> Function() serve) async {
    final Future<Response> Function() inner =
        () => _measuringZone().run(serve);
    if (_unmeasured.contains(req.url.path) ||
        req.url.path.startsWith('/_dartvel/')) {
      return inner();
    }

    // The request's server span, when anything is reading spans. Checked as a
    // field read, so a process nobody traces pays nothing else here.
    final DVSpan? span = DVObservability.requestTracing
        ? dvStartServerSpan(DVObservability.tracer, req)
        : null;
    final bool semantic = DVObservability.semanticMetrics;
    // Only when something will read it back: the metrics, or a route matched
    // inside a child span naming the request's span.
    final DVRequestTelemetry? scope =
        semantic || span != null ? DVRequestTelemetry(span) : null;

    final Map<String, String> activeLabels = semantic
        ? <String, String>{
            'http.request.method': req.method,
            'url.scheme': req.url.scheme.isEmpty ? 'http' : req.url.scheme,
          }
        : const <String, String>{};
    final DVGauge? active = semantic ? _activeRequests(activeLabels) : null;
    active?.increment();

    final Stopwatch clock = Stopwatch()..start();
    try {
      Future<Response> traced() => span == null ? inner() : dvInSpan(span, inner);
      final Response response = await (scope == null ? traced() : scope.run(traced));
      clock.stop();
      if (span != null) dvFinishServerSpan(span, response);
      // Inside the span, so the access line names the request's trace.
      void record() => _record(
          req, response.status, clock, response.headers.get('traceparent'));
      span == null ? record() : dvInSpan(span, record);
      if (semantic) _recordSemantic(activeLabels, scope?.route, response.status, clock);
      return response;
    } on Object catch (error, stack) {
      clock.stop();
      span?.recordError(error, stack);
      span?.setAttribute('http.response.status_code', 500);
      // The server layer turns this into a 500 inside a bare `catch (_)`, so
      // if it is not recorded here the exception is gone: no line, no count,
      // and a client holding a 500 nobody can explain.
      void record() =>
          _record(req, 500, clock, null, error: error, stackTrace: stack);
      span == null ? record() : dvInSpan(span, record);
      if (semantic) _recordSemantic(activeLabels, scope?.route, 500, clock);
      rethrow;
    } finally {
      active?.decrement();
      span?.end();
    }
  }

  static DVGauge _activeRequests(Map<String, String> labels) {
    DVObservability.metrics.setUnit('http.server.active_requests', '{request}');
    return DVObservability.metrics.gauge('http.server.active_requests', labels,
        'Number of active HTTP server requests.');
  }

  /// `http.server.request.duration`, labelled as the semantic conventions
  /// say: the route template, never the path, which is where ids are.
  static void _recordSemantic(Map<String, String> base, String? route,
      int status, Stopwatch clock) {
    DVObservability.metrics.setUnit('http.server.request.duration', 's');
    DVObservability.metrics
        .histogram(
          'http.server.request.duration',
          <String, String>{
            ...base,
            if (route != null) 'http.route': route,
            'http.response.status_code': '$status',
          },
          'Duration of HTTP server requests.',
        )
        .observe(clock.elapsedMicroseconds / 1000000);
  }

  static void _record(
    Request req,
    int status,
    Stopwatch clock,
    String? traceparent, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final double seconds = clock.elapsedMicroseconds / 1000000;
    final _RequestSeries series = _RequestSeries.of(req.method, status);
    series.requests.increment();
    series.duration.observe(seconds);

    // Decided before the record is built, so a request past the rate costs
    // nothing more than its metrics.
    if (error == null && status < 500 && !_accessBudget.take()) return;

    // The span was created inside the handler, so it is out of scope by now;
    // the header the tracing middleware set on the response is what is left
    // of it. Reading the id back from there is what lets a support ticket
    // quoting a traceparent find the log line for that request.
    final DVTraceContext? context =
        dvCurrentSpan == null ? DVTraceContext.parse(traceparent) : null;
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
        // The template, for the request's span name and its metrics.
        dvRecordHttpRoute(route.source);
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
      if (!_mayReadMetrics(req)) return _notFound();
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
    return Response(404);
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

Response _notFound() => Response(404);

class _Route {
  final String method;
  final String source;
  final URLPattern pattern;
  final Handler handler;
  final int? maxBodyBytes;
  _Route(this.method, this.source, this.handler, this.maxBodyBytes)
      : pattern = URLPattern(source);
}

/// The networks a scraper on the same host or network calls from: loopback,
/// the private IPv4 ranges and IPv6 unique-local addresses.
final List<DVCidr> _privateNetworks = <DVCidr>[
  for (final String range in const <String>[
    '127.0.0.0/8',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '::1/128',
    'fc00::/7',
  ])
    DVCidr.parse(range),
];

/// Whether [req] may read `GET /metrics`.
///
/// Request counts, route timings and uptime are an operator's, not the
/// internet's: dartvel.dev served them to anyone. The token opens it from
/// anywhere. Otherwise the caller must be on this host or a private network
/// *and* not be a request a proxy forwarded: behind a proxy on the same host
/// every request arrives from loopback, and one carrying a forwarding header
/// came from somewhere else, whether or not the proxy is trusted. A request
/// with no peer address at all is the process calling itself.
bool _mayReadMetrics(Request req) {
  final String? token = DVObservability.metricsToken;
  if (token != null && token.isNotEmpty) {
    final String given = req.headers.get('authorization') ?? '';
    if (_sameText(given, 'Bearer $token')) return true;
  }
  for (final String forwarding in const <String>[
    'forwarded',
    'x-forwarded-for',
    'x-real-ip',
  ]) {
    if (req.headers.get(forwarding) != null) return false;
  }
  final DVPeerAddress? peer = DVClientAddress.peerOf(req);
  if (peer == null) return true;
  final DVIpAddress? caller = DVClientAddress.current.resolve(req);
  if (caller == null) return false;
  return _privateNetworks.any((DVCidr network) => network.contains(caller));
}

/// Compares in time that does not depend on where the texts differ.
bool _sameText(String a, String b) {
  if (a.length != b.length) return false;
  int difference = 0;
  for (int i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

/// How many access records may still be written this second, and how many
/// were not.
final class _AccessLogBudget {
  final Stopwatch _clock = Stopwatch()..start();
  int _windowStartMs = 0;
  int _taken = 0;
  int _skipped = 0;
  Timer? _flush;

  /// Whether one more record may be written now.
  bool take() {
    _roll();
    if (_taken < Router.accessLogsPerSecond) {
      _taken++;
      return true;
    }
    _skipped++;
    // The summary is written when the second ends, whether or not another
    // request comes to notice it.
    _flush ??= Timer(
        Duration(milliseconds: 1000 - (_clock.elapsedMilliseconds - _windowStartMs)),
        _summarise);
    return false;
  }

  void _roll() {
    if (_clock.elapsedMilliseconds - _windowStartMs < 1000) return;
    _summarise();
    _windowStartMs = _clock.elapsedMilliseconds;
    _taken = 0;
  }

  void _summarise() {
    _flush?.cancel();
    _flush = null;
    final int skipped = _skipped;
    if (skipped == 0) return;
    _skipped = 0;
    DVObservability.logger.info(
      '$skipped requests not logged one by one (over '
      '${Router.accessLogsPerSecond} a second)',
      context: <String, Object?>{'notLogged': skipped},
    );
  }
}

/// The request counter and duration histogram for one method and status,
/// kept from one request to the next.
///
/// Looking a series up by name and labels sorts and joins the labels into a
/// key on every call, twice per request. The same few method and status
/// pairs come back all the time, so each is looked up once per registry
/// generation.
final class _RequestSeries {
  _RequestSeries(this.requests, this.duration);

  final DVCounter requests;
  final DVHistogram duration;

  static final Map<String, Map<int, _RequestSeries>> _byMethod =
      <String, Map<int, _RequestSeries>>{};
  static int _generation = -1;

  static _RequestSeries of(String method, int status) {
    final DVMetrics metrics = DVObservability.metrics;
    if (metrics.generation != _generation) {
      _byMethod.clear();
      _generation = metrics.generation;
    }
    final Map<int, _RequestSeries> byStatus =
        _byMethod[method] ??= <int, _RequestSeries>{};
    return byStatus[status] ??= _RequestSeries(
      metrics.counter(
        'http_requests_total',
        // Method and status only. The path is what an id is in, and one
        // series per id is how a metrics backend gets killed by the
        // application it is watching -- the router cannot tell `42` from a
        // route segment, so it must not put either in a label.
        <String, String>{'method': method, 'status': '$status'},
        'HTTP requests served, by method and response status.',
      ),
      metrics.histogram(
        'http_request_duration_seconds',
        <String, String>{'method': method},
        'How long serving a request took, in seconds.',
      ),
    );
  }
}
