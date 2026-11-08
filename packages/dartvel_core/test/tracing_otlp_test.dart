// OTLP over HTTP: the exporter that makes spans reach a collector.
//
// Before this, spans left the process only through /_dartvel/traces. The
// parts under test are the ones that fail quietly or expensively: a payload a
// collector cannot read (spans vanish with a 200 from nowhere), an export that
// waits on the collector (tracing adds latency to what it measures), and a
// queue that grows without bound when the collector is down.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/src/http/transport.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

/// A local collector: records every POST and answers with [status].
class _FakeCollector {
  _FakeCollector._(this._server);

  final HttpServer _server;
  final List<({String path, String contentType, Map<String, Object?> body})>
  received = <({String path, String contentType, Map<String, Object?> body})>[];
  int status = 200;

  static Future<_FakeCollector> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _FakeCollector collector = _FakeCollector._(server);
    server.listen((HttpRequest request) async {
      final String text = await utf8.decoder.bind(request).join();
      collector.received.add((
        path: request.uri.path,
        contentType: request.headers.contentType?.mimeType ?? '',
        body: jsonDecode(text) as Map<String, Object?>,
      ));
      request.response.statusCode = collector.status;
      await request.response.close();
    });
    return collector;
  }

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  List<Map<String, Object?>> get spans => <Map<String, Object?>>[
    for (final r in received)
      for (final Object? resource in r.body['resourceSpans']! as List<Object?>)
        for (final Object? scope
            in (resource! as Map<String, Object?>)['scopeSpans']!
                as List<Object?>)
          for (final Object? span
              in (scope! as Map<String, Object?>)['spans']! as List<Object?>)
            span! as Map<String, Object?>,
  ];

  Future<void> close() => _server.close(force: true);
}

Map<String, Object?> _attributes(Object? list) => <String, Object?>{
  for (final Object? entry in list! as List<Object?>)
    (entry! as Map<String, Object?>)['key']! as String:
        ((entry as Map<String, Object?>)['value']! as Map<String, Object?>)
            .values
            .single,
};

void main() {
  setUp(DVObservability.resetLogging);

  group('OTLP/HTTP JSON', () {
    late _FakeCollector collector;
    setUp(() async => collector = await _FakeCollector.start());
    tearDown(() => collector.close());

    test(
      'finished spans are posted to /v1/traces in the OTLP JSON shape',
      () async {
        final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
          endpoint: collector.endpoint,
          serviceName: 'shop-api',
        );
        final DVTracer tracer = DVTracer(exporter: exporter);
        final DVSpan root = tracer.startSpan(
          'GET /cart',
          kind: DVSpanKind.server,
        );
        root.setAttribute('http.method', 'GET');
        final DVSpan child = tracer.startSpan(
          'db SELECT carts',
          parent: root,
          kind: DVSpanKind.client,
        );
        child.recordError(StateError('lock timeout'));
        child.end();
        root.end();

        await exporter.close();

        expect(collector.received, hasLength(1));
        final r = collector.received.single;
        expect(r.path, '/v1/traces');
        expect(r.contentType, 'application/json');

        final Map<String, Object?> resource =
            ((r.body['resourceSpans']! as List<Object?>).single!
                    as Map<String, Object?>)['resource']!
                as Map<String, Object?>;
        expect(_attributes(resource['attributes'])['service.name'], 'shop-api');

        final List<Map<String, Object?>> spans = collector.spans;
        expect(spans, hasLength(2));
        final Map<String, Object?> sentRoot = spans.firstWhere(
          (s) => s['name'] == 'GET /cart',
        );
        final Map<String, Object?> sentChild = spans.firstWhere(
          (s) => s['name'] == 'db SELECT carts',
        );

        // Hex, as OTLP JSON requires -- not base64 as the protobuf mapping
        // would suggest. A collector reading base64 ids from hex gets garbage
        // ids and an unlinked trace.
        expect(sentRoot['traceId'], root.traceId);
        expect(sentRoot['spanId'], root.spanId);
        expect(sentRoot.containsKey('parentSpanId'), isFalse);
        expect(sentChild['traceId'], root.traceId);
        expect(sentChild['parentSpanId'], root.spanId);

        expect(sentRoot['kind'], 2, reason: 'SPAN_KIND_SERVER');
        expect(sentChild['kind'], 3, reason: 'SPAN_KIND_CLIENT');

        final int start = int.parse(sentRoot['startTimeUnixNano']! as String);
        final int end = int.parse(sentRoot['endTimeUnixNano']! as String);
        expect(end, greaterThanOrEqualTo(start));
        expect(
          start ~/ 1000000,
          closeTo(root.startedAt.millisecondsSinceEpoch, 1),
        );

        expect(_attributes(sentRoot['attributes'])['http.method'], 'GET');
        expect(
          (sentRoot['status']! as Map<String, Object?>)['code'],
          1,
          reason: 'STATUS_CODE_OK',
        );
        expect(
          (sentChild['status']! as Map<String, Object?>)['code'],
          2,
          reason: 'STATUS_CODE_ERROR',
        );
      },
    );

    test('an endpoint already naming /v1/traces is used as given', () async {
      final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
        endpoint: collector.endpoint.replace(path: '/otlp/v1/traces'),
      );
      DVTracer(exporter: exporter).startSpan('job').end();
      await exporter.close();
      expect(collector.received.single.path, '/otlp/v1/traces');
    });

    test(
      'a full batch is sent without waiting for the interval, in batches',
      () async {
        final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
          endpoint: collector.endpoint,
          batchSize: 3,
          flushInterval: const Duration(hours: 1),
        );
        final DVTracer tracer = DVTracer(exporter: exporter);
        for (int i = 0; i < 7; i++) {
          tracer.startSpan('span $i').end();
        }
        // Two full batches go on their own; the seventh waits for close.
        await exporter.idle;
        expect(collector.spans, hasLength(6));
        expect(
          collector.received.map((r) => _spanCount(r.body)),
          everyElement(3),
        );
        await exporter.close();
        expect(collector.spans, hasLength(7));
        expect(exporter.exported, 7);
      },
    );

    test(
      'a collector that keeps failing is retried, then dropped and counted',
      () async {
        collector.status = 503;
        final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
          endpoint: collector.endpoint,
          retries: 2,
          retryDelay: Duration.zero,
        );
        final DVTracer tracer = DVTracer(exporter: exporter);
        tracer.startSpan('a').end();
        tracer.startSpan('b').end();
        await exporter.close();

        expect(
          collector.received,
          hasLength(3),
          reason: 'one attempt and the two declared retries',
        );
        expect(exporter.droppedUnreachable, 2);
        expect(exporter.exported, 0);
        expect(
          DVObservability.recentLogs.where((l) => l.code == 'DV-TRACE-003'),
          hasLength(1),
        );
      },
    );

    test('a request the collector refuses outright is not retried', () async {
      collector.status = 400;
      final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
        endpoint: collector.endpoint,
        retries: 2,
        retryDelay: Duration.zero,
      );
      DVTracer(exporter: exporter).startSpan('a').end();
      await exporter.close();
      expect(collector.received, hasLength(1));
      expect(exporter.droppedUnreachable, 1);
    });
  });

  group('never blocks the request', () {
    test('export returns at once while the collector hangs, and a full queue '
        'drops with a count rather than growing', () async {
      final Completer<DVHttpResponse> hang = Completer<DVHttpResponse>();
      int sends = 0;
      final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
        endpoint: Uri.parse('http://collector.invalid:4318'),
        queueCapacity: 4,
        batchSize: 2,
        send: (DVHttpRequest request) {
          sends += 1;
          return hang.future;
        },
      );
      final DVTracer tracer = DVTracer(exporter: exporter);

      final Stopwatch watch = Stopwatch()..start();
      for (int i = 0; i < 50; i++) {
        tracer.startSpan('span $i').end();
      }
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(500));

      await Future<void>.delayed(Duration.zero);
      expect(
        sends,
        1,
        reason: 'one batch in flight at a time, not one per span',
      );
      expect(exporter.queued, lessThanOrEqualTo(4));
      expect(exporter.droppedQueueFull, greaterThan(0));
      expect(
        exporter.droppedQueueFull + exporter.queued + 2,
        50,
        reason: 'every span is sent, queued or counted as dropped',
      );

      // One warning for the burst, not one per dropped span: logging at
      // volume is its own outage.
      expect(
        DVObservability.recentLogs.where((l) => l.code == 'DV-TRACE-002'),
        hasLength(1),
      );

      hang.complete(const DVHttpResponse(statusCode: 200, body: ''));
      await exporter.close();
    });

    test(
      'the export is not itself traced inside the request that ended',
      () async {
        final List<DVHttpRequest> sent = <DVHttpRequest>[];
        final DVOtlpTraceExporter exporter = DVOtlpTraceExporter(
          endpoint: Uri.parse('http://collector.invalid:4318'),
          batchSize: 1,
          send: (DVHttpRequest request) async {
            sent.add(request);
            return const DVHttpResponse(statusCode: 200, body: '');
          },
        );
        final DVTracer tracer = DVTracer(exporter: exporter);
        final DVSpan request = tracer.startSpan('GET /');
        dvInSpan(
          request,
          () => tracer.startSpan('inner', parent: request).end(),
        );
        request.end();
        await exporter.close();
        expect(sent, isNotEmpty);
        expect(sent.first.headers.containsKey('traceparent'), isFalse);
      },
    );
  });
}

int _spanCount(Map<String, Object?> body) =>
    (((body['resourceSpans']! as List<Object?>).single!
                as Map<String, Object?>)['scopeSpans']!
            as List<Object?>)
        .fold<int>(
          0,
          (int sum, Object? scope) =>
              sum +
              ((scope! as Map<String, Object?>)['spans']! as List<Object?>)
                  .length,
        );
