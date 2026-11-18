// Automatic instrumentation: what a Dartvel process records with no code.
//
// Every span here follows the OpenTelemetry semantic conventions, because the
// point of exporting OTLP is that Jaeger, Tempo, Honeycomb and Datadog already
// know what `http.route` and `db.system.name` mean and draw the right thing.
// A span named `GET /orders/42` instead of `GET /orders/:id` is one span name
// per order, which is how a tracing backend's index gets blown up by the
// application it is watching.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/http/router.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

Request _request(String method, String path, {Map<String, String>? headers}) =>
    Request(
      method: method,
      url: Uri.parse('http://localhost$path'),
      headers: Headers(headers ?? <String, String>{}),
      bodyStream: const Stream<List<int>>.empty(),
    );

void main() {
  late DVMemoryTraceExporter spans;

  setUp(() {
    DVObservability.metrics.reset();
    DVObservability.resetLogging();
    DVObservability.resetTracing();
    DVHttp.reset();
    spans = DVMemoryTraceExporter();
    DVObservability.useTracing(exporter: spans);
  });

  tearDown(() {
    DVObservability.resetTracing();
    DVObservability.semanticMetrics = false;
    DVHttp.reset();
  });

  group('inbound requests', () {
    test('every request is a server span named by its route template', () async {
      final Router router = Router()
        ..get('/orders/:id', (Request _) async => Response.text('ok', status: 201));

      final Response response = await router(_request('GET', '/orders/42'));

      final DVSpan span = spans.spans.single;
      expect(span.kind, DVSpanKind.server);
      expect(span.name, 'GET /orders/:id');
      expect(span.attributes['http.request.method'], 'GET');
      expect(span.attributes['http.route'], '/orders/:id');
      expect(span.attributes['url.path'], '/orders/42');
      expect(span.attributes['http.response.status_code'], 201,
          reason: 'an int, as the convention types it, not the string "201"');
      expect(response.headers.get('traceparent'), contains(span.traceId),
          reason: 'sent back, so a support ticket can quote it');
    });

    test('a request with no route is named by its method alone', () async {
      final Router router = Router();
      await router(_request('GET', '/nowhere/123'));
      expect(spans.spans.single.name, 'GET');
      expect(spans.spans.single.attributes.containsKey('http.route'), isFalse);
    });

    test('an incoming traceparent is joined, not replaced', () async {
      final Router router = Router()
        ..get('/x', (Request _) async => Response.text('ok'));
      const String trace = '4bf92f3577b34da6a3ce929d0e0e4736';
      await router(_request('GET', '/x', headers: <String, String>{
        'traceparent': '00-$trace-00f067aa0ba902b7-01',
      }));
      expect(spans.spans.single.traceId, trace);
      expect(spans.spans.single.parentSpanId, '00f067aa0ba902b7');
    });

    test('a 500 is an error span; a 404 is not', () async {
      final Router router = Router()
        ..get('/boom', (Request _) async => Response.text('no', status: 500))
        ..get('/gone', (Request _) async => Response.text('no', status: 404));
      await router(_request('GET', '/boom'));
      await router(_request('GET', '/gone'));
      expect(spans.spans[0].status, DVSpanStatus.error);
      expect(spans.spans[0].attributes['error.type'], '500');
      expect(spans.spans[1].status, isNot(DVSpanStatus.error));
    });

    test('a request declaring the tracing middleware is not traced twice',
        () async {
      final Router router = Router()
        ..get(
            '/x',
            (Request req) => dvTraced(DVObservability.tracer, req,
                (Request _) async => Response.text('ok')));
      await router(_request('GET', '/x'));
      expect(spans.spans, hasLength(1));
    });

    test('health checks and scrapes are not traced', () async {
      final Router router = Router();
      await router(_request('GET', '/health'));
      expect(spans.spans, isEmpty);
    });

    test('with tracing off a request makes no span at all: the cost of not '
        'tracing is a field read', () async {
      DVObservability.resetTracing();
      final Router router = Router()
        ..get('/x', (Request _) async => Response.text('ok'));
      await router(_request('GET', '/x'));
      expect(DVObservability.recentSpans, isEmpty);
    });

    test('the access log line names the request span', () async {
      final Router router = Router()
        ..get('/x', (Request _) async => Response.text('ok'));
      await router(_request('GET', '/x'));
      final DVLogRecord line = DVObservability.recentLogs.last;
      expect(line.traceId, spans.spans.single.traceId);
      expect(line.spanId, spans.spans.single.spanId);
    });
  });

  group('semantic-convention metrics', () {
    test('http.server.request.duration by method, route and status, and '
        'active requests back to zero', () async {
      DVObservability.semanticMetrics = true;
      final Router router = Router()
        ..get('/orders/:id', (Request _) async {
          expect(
              DVObservability.metrics.valueOf('http.server.active_requests',
                  <String, String>{'http.request.method': 'GET', 'url.scheme': 'http'}),
              1);
          return Response.text('ok');
        });
      await router(_request('GET', '/orders/7'));

      final DVMetricPoint duration = DVObservability.metrics
          .collect()
          .singleWhere((DVMetricPoint p) => p.name == 'http.server.request.duration');
      expect(duration.kind, DVMetricKind.histogram);
      expect(duration.unit, 's');
      expect(duration.labels, <String, String>{
        'http.request.method': 'GET',
        'http.route': '/orders/:id',
        'http.response.status_code': '200',
        'url.scheme': 'http',
      });
      expect(duration.count, 1);
      expect(
          DVObservability.metrics.valueOf('http.server.active_requests',
              <String, String>{'http.request.method': 'GET', 'url.scheme': 'http'}),
          0);
    });

    test('off, nothing extra is recorded per request', () async {
      final Router router = Router()
        ..get('/x', (Request _) async => Response.text('ok'));
      await router(_request('GET', '/x'));
      expect(DVObservability.metrics.typeOf('http.server.request.duration'),
          isNull);
    });

    test('the Prometheus scrape still parses with dotted names in the registry',
        () async {
      DVObservability.semanticMetrics = true;
      final Router router = Router()
        ..get('/x', (Request _) async => Response.text('ok'));
      await router(_request('GET', '/x'));
      final String text = DVObservability.render();
      expect(text, contains('dartvel_http_server_request_duration_count{'));
      expect(text, isNot(contains('dartvel_http.server')),
          reason: 'a dot in a Prometheus metric name fails the whole scrape');
    });
  });

  group('the database', () {
    test('a query inside a request is a client span under it, with the '
        'statement and none of its values', () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      await db.execute('CREATE TABLE orders (id TEXT, total INTEGER)');
      final DVSpan request = DVObservability.tracer.startSpan('GET');
      await dvInSpan(request, () async {
        await db.execute(
            'INSERT INTO orders (id, total) VALUES (?, ?)', <Object?>['o-1', 4200]);
        await db.query('SELECT * FROM orders WHERE id = ?', <Object?>['o-1']);
      });

      final List<DVSpan> queries =
          spans.spans.where((DVSpan s) => s.kind == DVSpanKind.client).toList();
      expect(queries, hasLength(2));
      final DVSpan insert = queries[0];
      expect(insert.parentSpanId, request.spanId);
      expect(insert.traceId, request.traceId);
      expect(insert.name, 'INSERT orders');
      expect(insert.attributes['db.operation.name'], 'INSERT');
      expect(insert.attributes['db.collection.name'], 'orders');
      expect(insert.attributes['db.system.name'], 'other_sql');
      expect(insert.attributes['db.query.text'],
          'INSERT INTO orders (id, total) VALUES (?, ?)',
          reason: 'the statement, never the values bound to it');
      expect(queries[1].attributes['db.query.text'],
          'SELECT * FROM orders WHERE id = ?');
      expect(queries[1].attributes.values, isNot(contains('o-1')),
          reason: 'bound parameters are never exported');
    });

    test('a query outside any trace makes no span: a queue poll every second '
        'is not a trace anybody wants', () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      await db.execute('CREATE TABLE t (id TEXT)');
      await db.query('SELECT * FROM t');
      expect(spans.spans, isEmpty);
    });

    test('a failed query records the error on its span', () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final DVSpan request = DVObservability.tracer.startSpan('GET');
      await dvInSpan(request, () async {
        // A join is outside what the in-memory adapter runs, so it throws.
        await expectLater(
            db.query('SELECT * FROM a JOIN b ON a.id = b.id'), throwsA(anything));
      });
      expect(spans.spans.single.status, DVSpanStatus.error);
    });

    test('statement sanitising strips string, number and hex literals', () {
      expect(
        dvSanitizeSqlForTelemetry(
            "UPDATE users SET email = 'a@b.co', age = 42, k = x'ff' WHERE id = 7"),
        'UPDATE users SET email = ?, age = ?, k = ? WHERE id = ?',
      );
      expect(dvSanitizeSqlForTelemetry("SELECT 'it''s' FROM t"),
          'SELECT ? FROM t');
      expect(dvSanitizeSqlForTelemetry('SELECT * FROM t2 WHERE c1 = \$1'),
          'SELECT * FROM t2 WHERE c1 = \$1',
          reason: 'identifiers with digits and placeholders stay');
    });
  });

  group('outbound HTTP', () {
    test('a call is a client span with the conventions\' names', () async {
      const DVHttp http = DVHttp();
      http.declare('rates', const DVHttpHostConfig(baseUrl: 'https://api.rates.test'));
      DVHttp.transport = (DVHttpRequest request) async => DVHttpStreamedResponse(
          statusCode: 200,
          headers: const <String, String>{},
          body: Stream<List<int>>.value(const <int>[]));
      final DVSpan request = DVObservability.tracer.startSpan('GET');
      await dvInSpan(request, () => http.get('https://api.rates.test/v1/fx?k=secret'));

      final DVSpan call =
          spans.spans.singleWhere((DVSpan s) => s.kind == DVSpanKind.client);
      expect(call.parentSpanId, request.spanId);
      expect(call.name, 'GET');
      expect(call.attributes['http.request.method'], 'GET');
      expect(call.attributes['server.address'], 'api.rates.test');
      expect(call.attributes['url.full'], 'https://api.rates.test/v1/fx',
          reason: 'the query string is where keys travel; it is not exported');
      expect(call.attributes['http.response.status_code'], 200);
    });
  });

  group('jobs and schedules', () {
    test('a dispatch inside a request is a producer span, and running the job '
        'is a consumer span the handler\'s logs and queries hang off', () async {
      const DVQueues queues = DVQueues();
      String? handlerTrace;
      queues.register<String>((String payload) async {
        handlerTrace = dvCurrentSpan?.traceId;
      });
      final DVSpan request = DVObservability.tracer.startSpan('POST');
      await dvInSpan(request, () => queues.dispatch<String>('hello', queue: 'mail'));
      await queues.work(queue: 'mail');

      final DVSpan publish =
          spans.spans.singleWhere((DVSpan s) => s.kind == DVSpanKind.producer);
      expect(publish.name, 'publish mail');
      expect(publish.parentSpanId, request.spanId);
      expect(publish.attributes['messaging.operation.type'], 'send');
      expect(publish.attributes['messaging.destination.name'], 'mail');

      final DVSpan process =
          spans.spans.singleWhere((DVSpan s) => s.kind == DVSpanKind.consumer);
      expect(process.name, 'process mail');
      expect(process.attributes['messaging.operation.type'], 'process');
      expect(handlerTrace, process.traceId,
          reason: 'the handler runs inside the job\'s span');
    });

    test('a failing job is an error span', () async {
      const DVQueues queues = DVQueues();
      queues.register<int>((int _) async => throw StateError('nope'));
      await queues.dispatch<int>(1, queue: 'fails');
      await queues.work(queue: 'fails');
      final DVSpan process =
          spans.spans.singleWhere((DVSpan s) => s.kind == DVSpanKind.consumer);
      expect(process.status, DVSpanStatus.error);
    });

    test('a scheduled run is a span of its own', () async {
      DateTime now = DateTime.utc(2026, 11, 17, 9);
      final DVScheduler scheduler = DVScheduler(clock: () => now);
      scheduler.register('nightly-report', '* * * * *', () async {});
      now = now.add(const Duration(minutes: 1));
      await scheduler.tick();
      final DVSpan run = spans.spans.single;
      expect(run.name, 'cron nightly-report');
      expect(run.attributes['dartvel.schedule.name'], 'nightly-report');
    });
  });

  group('nothing sensitive leaves in a span', () {
    test('an attribute named after a sensitive field or a credential is '
        'redacted whatever its value', () {
      dvRegisterSensitiveLogFields(<String>['dateOfBirth']);
      final DVSpan span = DVTracer().startSpan('x')
        ..setAttribute('user.dateofbirth', '1990-01-01')
        ..setAttribute('http.request.header.authorization', 'Bearer abc')
        ..setAttribute('gen_ai.usage.input_tokens', 12);
      expect(span.attributes['user.dateofbirth'], isNot('1990-01-01'));
      expect(span.attributes['http.request.header.authorization'],
          isNot(contains('abc')));
      expect(span.attributes['gen_ai.usage.input_tokens'], 12,
          reason: 'a count of tokens is not a token');
      DVLogger.resetSensitiveFields();
    });

    test('a JWT in a value is struck out even under an innocent key', () {
      final DVSpan span = DVTracer().startSpan('x')
        ..setAttribute('note',
            'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlMTIzNDU2');
      expect(span.attributes['note'], isNot(contains('eyJzdWIi')));
    });

    test('attributes past the limit are dropped and counted', () {
      final DVSpan span = DVTracer().startSpan('x');
      for (int i = 0; i < DVSpan.attributeLimit + 5; i++) {
        span.setAttribute('a$i', i);
      }
      expect(span.attributes, hasLength(DVSpan.attributeLimit));
      expect(span.droppedAttributes, 5);
    });
  });

  group('code control', () {
    test('tracer.trace nests under the current span and makes itself current',
        () async {
      final DVSpan request = DVObservability.tracer.startSpan('GET');
      String? innerParent;
      await dvInSpan(request, () => DVObservability.tracer.trace('price cart',
          (DVSpan span) async {
        innerParent = dvCurrentSpan?.spanId;
      }));
      final DVSpan priced =
          spans.spans.singleWhere((DVSpan s) => s.name == 'price cart');
      expect(priced.parentSpanId, request.spanId);
      expect(innerParent, priced.spanId);
    });
  });
}
