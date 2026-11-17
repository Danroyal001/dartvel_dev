// OTLP export: traces, metrics and logs, encoded the way a collector reads
// them and sent so that nothing being measured ever waits for the sending.
//
// The protobuf assertions decode the bytes with a reader written here from the
// wire format, not with the encoder under test, and check field numbers taken
// from opentelemetry-proto. A swapped field number still produces bytes, still
// gets a 200 from some collectors, and puts the span id in the trace id's
// place -- which is the silent kind of wrong this file exists for.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

/// A collector that records what it was sent and answers from [statuses].
class _Collector {
  _Collector([List<int>? statuses]) : _statuses = statuses ?? <int>[];
  final List<int> _statuses;
  final List<({Uri url, Map<String, String> headers, List<int> body})> sent =
      <({Uri url, Map<String, String> headers, List<int> body})>[];
  Completer<void>? hold;

  Future<DVOtlpResponse> send(
      Uri url, Map<String, String> headers, List<int> body) async {
    sent.add((url: url, headers: headers, body: body));
    if (hold != null) await hold!.future;
    final int status = _statuses.isEmpty ? 200 : _statuses.removeAt(0);
    if (status == 0) throw StateError('connection refused');
    return DVOtlpResponse(status);
  }
}

// --- a protobuf reader, from the wire format ------------------------------

class _Field {
  _Field(this.number, this.wire, this.value);
  final int number;
  final int wire;
  final Object value; // int for varint/fixed, List<int> for length-delimited
  List<int> get bytes => value as List<int>;
  String get text => utf8.decode(bytes);
  int get integer => value as int;
}

List<_Field> _decode(List<int> data) {
  final List<_Field> out = <_Field>[];
  int i = 0;
  int varint() {
    int result = 0;
    int shift = 0;
    while (true) {
      final int b = data[i++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  while (i < data.length) {
    final int key = varint();
    final int number = key >> 3;
    final int wire = key & 7;
    switch (wire) {
      case 0:
        out.add(_Field(number, wire, varint()));
      case 1:
        final ByteData view =
            ByteData.sublistView(Uint8List.fromList(data.sublist(i, i + 8)));
        out.add(_Field(number, wire, view.getUint64(0, Endian.little)));
        i += 8;
      case 2:
        final int length = varint();
        out.add(_Field(number, wire, data.sublist(i, i + length)));
        i += length;
      case 5:
        final ByteData view =
            ByteData.sublistView(Uint8List.fromList(data.sublist(i, i + 4)));
        out.add(_Field(number, wire, view.getUint32(0, Endian.little)));
        i += 4;
      default:
        throw StateError('wire type $wire at $i');
    }
  }
  return out;
}

_Field _one(List<_Field> fields, int number) =>
    fields.singleWhere((_Field f) => f.number == number);
List<_Field> _all(List<_Field> fields, int number) =>
    fields.where((_Field f) => f.number == number).toList();

String _hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// KeyValue list -> map of key to the decoded AnyValue field.
Map<String, _Field> _attributes(List<_Field> fields, int number) => <String, _Field>{
      for (final _Field kv in _all(fields, number))
        _one(_decode(kv.bytes), 1).text:
            _decode(_one(_decode(kv.bytes), 2).bytes).single,
    };

DVOpenTelemetryConfig _config({
  DVOtlpProtocol protocol = DVOtlpProtocol.httpProtobuf,
  int queue = 2048,
  int batch = 512,
}) =>
    DVOpenTelemetryConfig(
      enabled: true,
      endpoint: 'http://collector:4318',
      protocol: protocol,
      serviceName: 'shop',
      maxQueueSize: queue,
      maxExportBatchSize: batch,
      scheduleDelay: const Duration(milliseconds: 1),
    );

DVSpan _finishedSpan(DVTracer tracer) {
  final DVSpan parent = tracer.startSpan('GET /orders/:id', kind: DVSpanKind.server);
  final DVSpan span = tracer.startSpan('SELECT orders',
      parent: parent, kind: DVSpanKind.client)
    ..setAttribute('db.system.name', 'sqlite')
    ..setAttribute('http.response.status_code', 200)
    ..setAttribute('ratio', 0.5)
    ..setAttribute('cached', true);
  span.recordError(StateError('boom'));
  span.end();
  return span;
}

void main() {
  final List<Duration> slept = <Duration>[];
  Future<void> sleep(Duration d) async => slept.add(d);

  setUp(() {
    slept.clear();
    DVObservability.metrics.reset();
  });

  group('traces as protobuf', () {
    test('one span carries the ids, kind, times, typed attributes, status and '
        'the exception event, at the field numbers opentelemetry-proto gives',
        () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      final DVSpan span =
          _finishedSpan(DVTracer(exporter: exporter.spans));
      await exporter.forceFlush();

      final sent = collector.sent.single;
      expect(sent.url.toString(), 'http://collector:4318/v1/traces');
      expect(sent.headers['content-type'], 'application/x-protobuf');

      // ExportTraceServiceRequest.resource_spans = 1
      final List<_Field> resourceSpans = _decode(_one(_decode(sent.body), 1).bytes);
      // ResourceSpans.resource = 1 -> Resource.attributes = 1
      final Map<String, _Field> resource =
          _attributes(_decode(_one(resourceSpans, 1).bytes), 1);
      expect(resource['service.name']!.text, 'shop');
      expect(resource['telemetry.sdk.name']!.text, 'dartvel');
      expect(resource['telemetry.sdk.language']!.text, 'dart');

      // ResourceSpans.scope_spans = 2 -> ScopeSpans.scope = 1, spans = 2
      final List<_Field> scopeSpans = _decode(_one(resourceSpans, 2).bytes);
      expect(_one(_decode(_one(scopeSpans, 1).bytes), 1).text, 'dartvel');
      final List<_Field> spans = _all(scopeSpans, 2);
      expect(spans, hasLength(1),
          reason: 'only the ended span is exported; the parent never ended');
      final List<_Field> wire = _decode(spans.single.bytes);

      expect(_hex(_one(wire, 1).bytes), span.traceId); // trace_id
      expect(_hex(_one(wire, 2).bytes), span.spanId); // span_id
      expect(_hex(_one(wire, 4).bytes), span.parentSpanId); // parent_span_id
      expect(_one(wire, 5).text, 'SELECT orders'); // name
      expect(_one(wire, 6).integer, 3); // kind: SPAN_KIND_CLIENT
      final int start = _one(wire, 7).integer; // fixed64
      final int end = _one(wire, 8).integer;
      expect(_one(wire, 7).wire, 1, reason: 'times are fixed64');
      expect(start, span.startTimeUnixNano);
      expect(end, greaterThanOrEqualTo(start));
      expect(start ~/ 1000000000,
          closeTo(DateTime.now().millisecondsSinceEpoch ~/ 1000, 5),
          reason: 'nanoseconds since the epoch, not micro- or milliseconds');

      final Map<String, _Field> attributes = _attributes(wire, 9);
      expect(attributes['db.system.name']!.number, 1); // string_value
      expect(attributes['db.system.name']!.text, 'sqlite');
      expect(attributes['http.response.status_code']!.number, 3); // int_value
      expect(attributes['http.response.status_code']!.integer, 200);
      expect(attributes['ratio']!.number, 4); // double_value
      expect(attributes['cached']!.number, 2); // bool_value

      // events = 11: the exception, as the semantic conventions name it.
      final List<_Field> event = _decode(_one(wire, 11).bytes);
      expect(_one(event, 2).text, 'exception');
      final Map<String, _Field> exception = _attributes(event, 3);
      expect(exception['exception.type']!.text, 'StateError');
      expect(exception['exception.message']!.text, contains('boom'));

      // status = 15: code = 3 is ERROR (2)
      final List<_Field> status = _decode(_one(wire, 15).bytes);
      expect(_one(status, 3).integer, 2);
      // flags = 16, fixed32, sampled bit set
      expect(_one(wire, 16).wire, 5);
      expect(_one(wire, 16).integer & 0x01, 1);
    });
  });

  group('traces as JSON', () {
    test('ids are hex strings, nanoseconds are decimal strings, enums are '
        'numbers, as the OTLP JSON mapping says', () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(protocol: DVOtlpProtocol.httpJson),
          send: collector.send,
          sleep: sleep);
      final DVSpan span = _finishedSpan(DVTracer(exporter: exporter.spans));
      await exporter.forceFlush();

      final sent = collector.sent.single;
      expect(sent.headers['content-type'], 'application/json');
      final Map<String, Object?> body =
          jsonDecode(utf8.decode(sent.body)) as Map<String, Object?>;
      final Map<String, Object?> json = (((body['resourceSpans'] as List).single
                  as Map)['scopeSpans'] as List)
              .single['spans']
              .single as Map<String, Object?>;
      expect(json['traceId'], span.traceId);
      expect(json['spanId'], span.spanId);
      expect(json['parentSpanId'], span.parentSpanId);
      expect(json['kind'], 3);
      expect(json['startTimeUnixNano'], '${span.startTimeUnixNano}');
      expect((json['status'] as Map)['code'], 2);
      final List<Object?> attributes = json['attributes'] as List<Object?>;
      expect(
        attributes,
        contains(equals(<String, Object?>{
          'key': 'http.response.status_code',
          'value': <String, Object?>{'intValue': '200'},
        })),
      );
    });
  });

  group('metrics', () {
    test('a counter is a cumulative monotonic sum, a gauge a gauge, and a '
        'histogram carries per-bucket counts rather than Prometheus\'s '
        'cumulative ones', () async {
      final DVMetrics metrics = DVMetrics();
      metrics.counter('http_requests_total', <String, String>{'method': 'GET'},
          'Requests.').increment(3);
      metrics.gauge('http.server.active_requests').set(2);
      metrics
          .counter('http_requests_total',
              <String, String>{'method': 'GET', 'http.response.status_code': '200'})
          .increment();
      metrics.setUnit('http.server.request.duration', 's');
      final DVHistogram histogram = metrics.histogram(
          'http.server.request.duration',
          <String, String>{'http.route': '/orders/:id'});
      histogram.observe(0.004); // first bucket (<= 0.005)
      histogram.observe(0.02); // third bucket (<= 0.025)
      histogram.observe(60); // overflow

      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      await exporter.exportMetrics(metrics.collect());

      final sent = collector.sent.single;
      expect(sent.url.path, '/v1/metrics');
      final List<_Field> scope = _decode(
          _one(_decode(_one(_decode(sent.body), 1).bytes), 2).bytes);
      final Map<String, List<_Field>> byName = <String, List<_Field>>{
        for (final _Field metric in _all(scope, 2))
          _one(_decode(metric.bytes), 1).text: _decode(metric.bytes),
      };

      expect(byName.keys, containsAll(<String>[
        'dartvel.http_requests_total',
        'http.server.active_requests',
        'http.server.request.duration',
      ]), reason: 'framework names keep a dartvel. prefix; dotted OTel names '
          'are exported as registered');

      final List<_Field> sum = _decode(_one(byName['dartvel.http_requests_total']!, 7).bytes);
      expect(_one(sum, 2).integer, 2, reason: 'AGGREGATION_TEMPORALITY_CUMULATIVE');
      expect(_one(sum, 3).integer, 1, reason: 'is_monotonic');
      final List<_Field> point = _all(sum, 1)
          .map((_Field f) => _decode(f.bytes))
          .singleWhere((List<_Field> p) =>
              !_attributes(p, 7).containsKey('http.response.status_code'));

      final ByteData asDouble = ByteData(8)..setUint64(0, _one(point, 4).integer, Endian.little);
      expect(asDouble.getFloat64(0, Endian.little), 3);
      expect(_attributes(point, 7)['method']!.text, 'GET');
      // A status code is an int in the conventions, in a metric as in a span;
      // the registry keeps labels as text, so the exporter types it back.
      final List<_Field> labelled = _all(sum, 1)
          .map((_Field f) => _decode(f.bytes))
          .singleWhere((List<_Field> p) =>
              _attributes(p, 7).containsKey('http.response.status_code'));
      expect(_attributes(labelled, 7)['http.response.status_code']!.number, 3);
      expect(_attributes(labelled, 7)['http.response.status_code']!.integer, 200);


      expect(_all(byName['http.server.active_requests']!, 5), hasLength(1),
          reason: 'gauge = 5');

      final List<_Field> duration = byName['http.server.request.duration']!;
      expect(_one(duration, 3).text, 's');
      final List<_Field> hist = _decode(_one(duration, 9).bytes);
      final List<_Field> hp = _decode(_one(hist, 1).bytes);
      expect(_one(hp, 4).integer, 3); // count
      // bucket_counts = 6, packed fixed64
      final List<int> packed = _one(hp, 6).bytes;
      final ByteData view = ByteData.sublistView(Uint8List.fromList(packed));
      final List<int> counts = <int>[
        for (int i = 0; i < packed.length; i += 8) view.getUint64(i, Endian.little),
      ];
      expect(counts, hasLength(DVHistogram.defaultBuckets.length + 1));
      expect(counts[0], 1);
      expect(counts[1], 0);
      expect(counts[2], 1);
      expect(counts.last, 1, reason: 'the overflow bucket');
      expect(counts.reduce((int a, int b) => a + b), 3,
          reason: 'per-bucket counts add up to the count');
    });
  });

  group('logs', () {
    test('a record carries its severity, body, attributes and the trace it '
        'happened in, already redacted', () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[exporter.logs]);
      final DVSpan span = DVTracer().startSpan('checkout');
      dvInSpan(span, () {
        logger.warn('card declined',
            context: <String, Object?>{'orderId': 'o-1', 'password': 'hunter2'});
      });
      await exporter.forceFlush();

      final sent = collector.sent.single;
      expect(sent.url.path, '/v1/logs');
      final List<_Field> scopeLogs = _decode(
          _one(_decode(_one(_decode(sent.body), 1).bytes), 2).bytes);
      final List<_Field> record = _decode(_one(scopeLogs, 2).bytes);
      expect(_one(record, 2).integer, 13, reason: 'SEVERITY_NUMBER_WARN');
      expect(_one(record, 3).text, 'WARN');
      expect(_decode(_one(record, 5).bytes).single.text, 'card declined');
      expect(_hex(_one(record, 9).bytes), span.traceId);
      expect(_hex(_one(record, 10).bytes), span.spanId);
      expect(_one(record, 8).integer & 0x01, 1,
          reason: 'flags carry the trace\'s sampled bit, as the span does');
      final Map<String, _Field> attributes = _attributes(record, 6);
      expect(attributes['orderId']!.text, 'o-1');
      expect(attributes['password']!.text, isNot(contains('hunter2')));
    });

    test('the exporter\'s own diagnostics are not exported, or a collector '
        'that is down would be told so through itself, forever', () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      exporter.logs.write(DVLogRecord(
          level: DVLogLevel.warn, message: 'x', tag: dvOtelLogTag));
      await exporter.forceFlush();
      expect(collector.sent, isEmpty);
    });
  });

  group('never in the way of the work it measures', () {
    test('exporting a span returns at once while the collector hangs', () async {
      final _Collector collector = _Collector()..hold = Completer<void>();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(batch: 1), send: collector.send, sleep: sleep);
      final DVTracer tracer = DVTracer(exporter: exporter.spans);
      final Stopwatch clock = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        tracer.startSpan('s$i').end();
      }
      clock.stop();
      expect(clock.elapsedMilliseconds, lessThan(200));
      collector.hold!.complete();
      await exporter.shutdown();
    });

    test('a full queue drops and counts, rather than growing', () async {
      final _Collector collector = _Collector()..hold = Completer<void>();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(queue: 10, batch: 5), send: collector.send, sleep: sleep);
      final DVTracer tracer = DVTracer(exporter: exporter.spans);
      for (int i = 0; i < 30; i++) {
        tracer.startSpan('s$i').end();
      }
      expect(exporter.dropped(DVOtelSignal.traces), greaterThanOrEqualTo(15));
      expect(
        DVObservability.metrics.valueOf('otel_dropped_total',
            <String, String>{'signal': 'traces', 'reason': 'queue_full'}),
        exporter.dropped(DVOtelSignal.traces),
      );
      collector.hold!.complete();
      await exporter.shutdown();
    });

    test('a 503 is retried with growing backoff and the batch is delivered',
        () async {
      final _Collector collector = _Collector(<int>[503, 503, 200]);
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      DVTracer(exporter: exporter.spans).startSpan('s').end();
      await exporter.forceFlush();
      expect(collector.sent, hasLength(3));
      expect(slept, hasLength(2));
      expect(slept[1], greaterThan(slept[0]));
      expect(exporter.dropped(DVOtelSignal.traces), 0);
    });

    test('a collector that stays down: retried, then dropped with a count',
        () async {
      final _Collector collector = _Collector(List<int>.filled(20, 0));
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      final DVTracer tracer = DVTracer(exporter: exporter.spans);
      tracer.startSpan('a').end();
      tracer.startSpan('b').end();
      await exporter.forceFlush();
      expect(collector.sent.length, DVOtlpExporter.maxAttempts);
      expect(exporter.dropped(DVOtelSignal.traces), 2);
      expect(
        DVObservability.metrics.valueOf('otel_dropped_total',
            <String, String>{'signal': 'traces', 'reason': 'export_failed'}),
        2,
      );
    });

    test('a 400 is not retried: the collector has said the batch is wrong',
        () async {
      final _Collector collector = _Collector(<int>[400]);
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      DVTracer(exporter: exporter.spans).startSpan('s').end();
      await exporter.forceFlush();
      expect(collector.sent, hasLength(1));
      expect(exporter.dropped(DVOtelSignal.traces), 1);
    });

    test('headers from the environment and resolved secrets are sent', () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
        config: _config(),
        headers: <String, String>{'x-honeycomb-team': 'k3y'},
        send: collector.send,
        sleep: sleep,
      );
      DVTracer(exporter: exporter.spans).startSpan('s').end();
      await exporter.forceFlush();
      expect(collector.sent.single.headers['x-honeycomb-team'], 'k3y');
    });

    test('an unsampled span is not exported', () async {
      final _Collector collector = _Collector();
      final DVOtlpExporter exporter = DVOtlpExporter(
          config: _config(), send: collector.send, sleep: sleep);
      DVTracer(exporter: exporter.spans, sampler: DVTraceSampler.never())
          .startSpan('s')
          .end();
      await exporter.forceFlush();
      expect(collector.sent, isEmpty);
    });
  });
}
