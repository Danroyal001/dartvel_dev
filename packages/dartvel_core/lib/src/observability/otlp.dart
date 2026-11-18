/// OTLP over HTTP: traces, metrics and logs encoded as a collector reads them
/// (protobuf or JSON), batched on bounded queues, and sent so that nothing
/// being measured ever waits for the sending.
///
/// Written here rather than taken from a package, for the reasons the
/// OpenTelemetry docs page gives in full: this file is on the import path of
/// every Dartvel target, the web included, and the Dart OpenTelemetry SDKs on
/// pub.dev bring gRPC and protobuf runtimes with them; the three OTLP messages
/// Dartvel sends are a few hundred lines of a stable, versioned wire format.
library dartvel.observability.otlp;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'logging.dart';
import 'metrics.dart';
import 'observability.dart' show DVObservability;
import 'open_telemetry_config.dart';
import 'tracing.dart';

/// The tag the exporter's own log records carry. The log exporter drops
/// records with it: a collector that is down would otherwise be told so
/// through itself, and each failure to say so would be another record.
const String dvOtelLogTag = 'opentelemetry';

/// What a collector answered.
class DVOtlpResponse {
  const DVOtlpResponse(this.status, {this.retryAfter});
  final int status;

  /// The collector's `Retry-After`, when it sent one.
  final Duration? retryAfter;
}

/// Sends one OTLP body. Throws when nothing answered.
typedef DVOtlpSend = Future<DVOtlpResponse> Function(
    Uri url, Map<String, String> headers, List<int> body);

/// Exports traces, metrics and logs to one collector.
///
/// [spans] is a [DVTraceExporter] and [logs] a [DVLogSink], so each plugs
/// into the tracer and the logger as any other destination does. Both only
/// enqueue: a span ends and a line is logged in the time it takes to add to a
/// list, whatever the collector is doing.
class DVOtlpExporter {
  DVOtlpExporter({
    required this.config,
    Map<String, String> headers = const <String, String>{},
    Map<String, Object> resource = const <String, Object>{},
    DVOtlpSend? send,
    Future<void> Function(Duration delay)? sleep,
  })  : _headers = <String, String>{...config.headers, ...headers},
        _resource = <String, Object>{
          'service.name': config.serviceName ?? 'unknown_service:dartvel',
          if (config.serviceVersion != null)
            'service.version': config.serviceVersion!,
          'telemetry.sdk.name': 'dartvel',
          'telemetry.sdk.language': 'dart',
          ...resource,
          ...config.resourceAttributes,
        },
        _send = send ?? _httpSend(config.exportTimeout),
        _sleep = sleep ?? ((Duration d) => Future<void>.delayed(d)) {
    _spans = _DVSignalQueue<DVSpan>(this, DVOtelSignal.traces);
    _records = _DVSignalQueue<DVLogRecord>(this, DVOtelSignal.logs);
  }

  /// Attempts per batch before it is dropped.
  static const int maxAttempts = 5;

  final DVOpenTelemetryConfig config;
  final Map<String, String> _headers;
  final Map<String, Object> _resource;
  final DVOtlpSend _send;
  final Future<void> Function(Duration delay) _sleep;
  late final _DVSignalQueue<DVSpan> _spans;
  late final _DVSignalQueue<DVLogRecord> _records;
  final Map<DVOtelSignal, int> _dropped = <DVOtelSignal, int>{};
  final Map<DVOtelSignal, DateTime> _lastWarned = <DVOtelSignal, DateTime>{};

  /// The resource every export carries.
  Map<String, Object> get resource => Map<String, Object>.unmodifiable(_resource);

  /// The span destination.
  late final DVTraceExporter spans = _DVOtlpSpans(this);

  /// The log destination.
  late final DVLogSink logs = _DVOtlpLogs(this);

  /// Items of [signal] that will never be sent: refused by a full queue, or in
  /// a batch the collector would not take.
  int dropped(DVOtelSignal signal) => _dropped[signal] ?? 0;

  /// Sends [points] now. Metrics are already aggregated, so there is nothing
  /// to batch: one request per collection.
  Future<void> exportMetrics(List<DVMetricPoint> points) async {
    if (points.isEmpty) return;
    final Uri? url = config.endpointFor(DVOtelSignal.metrics);
    if (url == null) return;
    await _deliver(DVOtelSignal.metrics, url, _encodeMetrics(points), points.length);
  }

  /// Sends everything queued, and completes when it has been sent or dropped.
  Future<void> forceFlush() async {
    await _spans.flush();
    await _records.flush();
  }

  /// Flushes and stops the timers. Call it when the process is stopping, or
  /// the last few seconds of spans go with it.
  Future<void> shutdown() async {
    await forceFlush();
    _spans.close();
    _records.close();
  }

  void _drop(DVOtelSignal signal, int count, String reason) {
    if (count <= 0) return;
    _dropped[signal] = dropped(signal) + count;
    DVObservability.metrics
        .counter(
          'otel_dropped_total',
          <String, String>{'signal': signal.name, 'reason': reason},
          'Spans, log records and metric points that were not exported, by '
              'signal and reason (queue_full, export_failed).',
        )
        .increment(count.toDouble());
    // One line a minute per signal: a collector that is down for an hour is
    // one fact, not a line per batch.
    final DateTime now = DateTime.now();
    final DateTime? last = _lastWarned[signal];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) return;
    _lastWarned[signal] = now;
    DVObservability.log(
      reason == 'queue_full'
          ? 'The OpenTelemetry ${signal.name} queue is full; $count dropped.'
          : 'The OpenTelemetry collector could not take ${signal.name}; '
              '$count dropped after $maxAttempts attempts.',
      level: reason == 'queue_full' ? DVLogLevel.warn : DVLogLevel.error,
      tag: dvOtelLogTag,
      code: reason == 'queue_full' ? 'DV-TRACE-002' : 'DV-TRACE-003',
      context: <String, Object?>{'signal': signal.name, 'dropped': count},
    );
  }

  /// Sends [body], retrying what a collector says is worth retrying, with
  /// growing backoff. Never throws.
  Future<void> _deliver(
      DVOtelSignal signal, Uri url, List<int> body, int count) async {
    final Map<String, String> headers = <String, String>{
      ..._headers,
      'content-type': config.protocol == DVOtlpProtocol.httpJson
          ? 'application/json'
          : 'application/x-protobuf',
    };
    for (int attempt = 1;; attempt++) {
      Duration? wait;
      try {
        final DVOtlpResponse response = await _send(url, headers, body);
        if (response.status >= 200 && response.status < 300) return;
        // 429 and the gateway errors are the collector saying "later"; any
        // other answer is the collector saying the batch is wrong, and
        // sending it again gets the same answer.
        const Set<int> retryable = <int>{429, 502, 503, 504};
        if (!retryable.contains(response.status)) break;
        wait = response.retryAfter;
      } on Object {
        // Nothing answered: a collector restarting, a network partition.
      }
      if (attempt >= maxAttempts) break;
      final int backoffMs = 1000 * (1 << (attempt - 1));
      await _sleep(wait ?? Duration(milliseconds: backoffMs.clamp(0, 30000)));
    }
    _drop(signal, count, 'export_failed');
  }

  static DVOtlpSend _httpSend(Duration timeout) =>
      (Uri url, Map<String, String> headers, List<int> body) async {
        final http.Response response = await http
            .post(url, headers: headers, body: body)
            .timeout(timeout);
        final int? seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return DVOtlpResponse(response.statusCode,
            retryAfter: seconds == null ? null : Duration(seconds: seconds));
      };

  // --- encoding --------------------------------------------------------------

  bool get _json => config.protocol == DVOtlpProtocol.httpJson;

  static const String _scopeName = 'dartvel';

  List<int> _encodeSpans(List<DVSpan> spans) {
    if (_json) {
      return utf8.encode(jsonEncode(<String, Object?>{
        'resourceSpans': <Object?>[
          <String, Object?>{
            'resource': <String, Object?>{'attributes': _jsonAttributes(_resource)},
            'scopeSpans': <Object?>[
              <String, Object?>{
                'scope': <String, Object?>{'name': _scopeName},
                'spans': <Object?>[for (final DVSpan s in spans) _jsonSpan(s)],
              },
            ],
          },
        ],
      }));
    }
    final _PbWriter scope = _PbWriter()
      ..message(1, _PbWriter()..string(1, _scopeName));
    for (final DVSpan span in spans) {
      scope.message(2, _pbSpan(span));
    }
    final _PbWriter resourceSpans = _PbWriter()
      ..message(1, _pbResource())
      ..message(2, scope);
    return (_PbWriter()..message(1, resourceSpans)).takeBytes();
  }

  List<int> _encodeLogs(List<DVLogRecord> records) {
    if (_json) {
      return utf8.encode(jsonEncode(<String, Object?>{
        'resourceLogs': <Object?>[
          <String, Object?>{
            'resource': <String, Object?>{'attributes': _jsonAttributes(_resource)},
            'scopeLogs': <Object?>[
              <String, Object?>{
                'scope': <String, Object?>{'name': _scopeName},
                'logRecords': <Object?>[
                  for (final DVLogRecord r in records) _jsonLog(r),
                ],
              },
            ],
          },
        ],
      }));
    }
    final _PbWriter scope = _PbWriter()
      ..message(1, _PbWriter()..string(1, _scopeName));
    for (final DVLogRecord record in records) {
      scope.message(2, _pbLog(record));
    }
    return (_PbWriter()
          ..message(1, _PbWriter()
            ..message(1, _pbResource())
            ..message(2, scope)))
        .takeBytes();
  }

  List<int> _encodeMetrics(List<DVMetricPoint> points) {
    // One OTLP metric per name, with a data point per label set.
    final Map<String, List<DVMetricPoint>> byName = <String, List<DVMetricPoint>>{};
    for (final DVMetricPoint point in points) {
      byName.putIfAbsent(point.name, () => <DVMetricPoint>[]).add(point);
    }
    final int start = DVObservability.metrics.startedAt.microsecondsSinceEpoch * 1000;
    final int now = DateTime.now().microsecondsSinceEpoch * 1000;
    if (_json) {
      return utf8.encode(jsonEncode(<String, Object?>{
        'resourceMetrics': <Object?>[
          <String, Object?>{
            'resource': <String, Object?>{'attributes': _jsonAttributes(_resource)},
            'scopeMetrics': <Object?>[
              <String, Object?>{
                'scope': <String, Object?>{'name': _scopeName},
                'metrics': <Object?>[
                  for (final MapEntry<String, List<DVMetricPoint>> metric
                      in byName.entries)
                    _jsonMetric(metric.key, metric.value, start, now),
                ],
              },
            ],
          },
        ],
      }));
    }
    final _PbWriter scope = _PbWriter()
      ..message(1, _PbWriter()..string(1, _scopeName));
    for (final MapEntry<String, List<DVMetricPoint>> metric in byName.entries) {
      scope.message(2, _pbMetric(metric.key, metric.value, start, now));
    }
    return (_PbWriter()
          ..message(1, _PbWriter()
            ..message(1, _pbResource())
            ..message(2, scope)))
        .takeBytes();
  }

  /// A metric's labels as attributes. The registry keeps every label as
  /// text, for Prometheus; the semantic conventions type a status code as an
  /// int, so a backend comparing `>= 500` works on metrics as on spans.
  static Map<String, Object> _labels(Map<String, String> labels) => <String, Object>{
        for (final MapEntry<String, String> label in labels.entries)
          label.key: label.key.endsWith('status_code') || label.key == 'server.port'
              ? (int.tryParse(label.value) ?? label.value)
              : label.value,
      };

  /// Framework metrics registered in Prometheus spelling keep a `dartvel.`

  /// prefix so they cannot be mistaken for anybody else's; a dotted name is
  /// an OpenTelemetry semantic-convention name and is exported as it is.
  static String _metricName(String name) =>
      name.contains('.') ? name : 'dartvel.$name';

  static int _kind(DVSpanKind kind) => switch (kind) {
        DVSpanKind.internal => 1,
        DVSpanKind.server => 2,
        DVSpanKind.client => 3,
        DVSpanKind.producer => 4,
        DVSpanKind.consumer => 5,
      };

  static int _statusCode(DVSpanStatus status) => switch (status) {
        DVSpanStatus.unset => 0,
        DVSpanStatus.ok => 1,
        DVSpanStatus.error => 2,
      };

  static int _severity(DVLogLevel level) => switch (level) {
        DVLogLevel.trace => 1,
        DVLogLevel.debug => 5,
        DVLogLevel.info => 9,
        DVLogLevel.warn => 13,
        DVLogLevel.error => 17,
        DVLogLevel.fatal => 21,
      };

  /// A log record's fields as OTLP attributes: its context, and what the
  /// record names besides its message.
  static Map<String, Object> _logAttributes(DVLogRecord record) => <String, Object>{
        for (final MapEntry<String, Object?> entry in record.context.entries)
          if (entry.value != null) entry.key: _attributeValue(entry.value!),
        if (record.tag != null) 'dartvel.log.tag': record.tag!,
        if (record.code != null) 'dartvel.log.code': record.code!,
        if (record.error != null) 'exception.message': record.error!,
        if (record.stackTrace != null) 'exception.stacktrace': record.stackTrace!,
      };

  /// A context value as an attribute: the scalar types as they are, anything
  /// else -- a map, a list of maps -- as its JSON. Already redacted by the
  /// logger before it got here.
  static Object _attributeValue(Object value) {
    if (value is String || value is int || value is double || value is bool) {
      return value;
    }
    if (value is List<String> || value is List<int> || value is List<double> ||
        value is List<bool>) {
      return value;
    }
    try {
      return jsonEncode(value);
    } on Object {
      return '$value';
    }
  }

  // JSON (the OTLP/JSON mapping: hex ids, int64 as decimal strings).

  static List<Object?> _jsonAttributes(Map<String, Object> attributes) => <Object?>[
        for (final MapEntry<String, Object> entry in attributes.entries)
          <String, Object?>{'key': entry.key, 'value': _jsonValue(entry.value)},
      ];

  static Map<String, Object?> _jsonValue(Object value) {
    if (value is bool) return <String, Object?>{'boolValue': value};
    if (value is int) return <String, Object?>{'intValue': '$value'};
    if (value is double) return <String, Object?>{'doubleValue': value};
    if (value is List) {
      return <String, Object?>{
        'arrayValue': <String, Object?>{
          'values': <Object?>[for (final Object item in value.cast<Object>()) _jsonValue(item)],
        },
      };
    }
    return <String, Object?>{'stringValue': '$value'};
  }

  static Map<String, Object?> _jsonSpan(DVSpan span) => <String, Object?>{
        'traceId': span.traceId,
        'spanId': span.spanId,
        if (span.parentSpanId != null) 'parentSpanId': span.parentSpanId,
        'flags': span.sampled ? 1 : 0,
        'name': span.name,
        'kind': _kind(span.kind),
        'startTimeUnixNano': '${span.startTimeUnixNano}',
        'endTimeUnixNano': '${span.endTimeUnixNano ?? span.startTimeUnixNano}',
        'attributes': _jsonAttributes(span.attributes),
        if (span.droppedAttributes > 0)
          'droppedAttributesCount': span.droppedAttributes,
        if (span.events.isNotEmpty)
          'events': <Object?>[
            for (final DVSpanEvent event in span.events)
              <String, Object?>{
                'timeUnixNano': '${event.timeUnixNano}',
                'name': event.name,
                'attributes': _jsonAttributes(event.attributes),
              },
          ],
        'status': <String, Object?>{
          'code': _statusCode(span.status),
          if (span.statusMessage != null) 'message': span.statusMessage,
        },
      };

  static Map<String, Object?> _jsonLog(DVLogRecord record) {
    final String nanos = '${record.time.microsecondsSinceEpoch * 1000}';
    return <String, Object?>{
      'timeUnixNano': nanos,
      'observedTimeUnixNano': nanos,
      'severityNumber': _severity(record.level),
      'severityText': record.level.name.toUpperCase(),
      'body': <String, Object?>{'stringValue': record.message},
      'attributes': _jsonAttributes(_logAttributes(record)),
      if (record.event != null) 'eventName': record.event,
      if (record.traceId != null) 'flags': 1,
      if (record.traceId != null) 'traceId': record.traceId,
      if (record.spanId != null) 'spanId': record.spanId,
    };
  }

  static Map<String, Object?> _jsonMetric(
      String name, List<DVMetricPoint> points, int start, int now) {
    final DVMetricPoint first = points.first;
    Map<String, Object?> numberPoint(DVMetricPoint p) => <String, Object?>{
          'attributes': _jsonAttributes(_labels(p.labels)),
          'startTimeUnixNano': '$start',
          'timeUnixNano': '$now',
          'asDouble': p.value,
        };
    return <String, Object?>{
      'name': _metricName(name),
      if (first.help != null) 'description': first.help,
      if (first.unit != null) 'unit': first.unit,
      ...switch (first.kind) {
        DVMetricKind.counter => <String, Object?>{
            'sum': <String, Object?>{
              'dataPoints': <Object?>[for (final DVMetricPoint p in points) numberPoint(p)],
              'aggregationTemporality': 2,
              'isMonotonic': true,
            },
          },
        DVMetricKind.gauge => <String, Object?>{
            'gauge': <String, Object?>{
              'dataPoints': <Object?>[for (final DVMetricPoint p in points) numberPoint(p)],
            },
          },
        DVMetricKind.histogram => <String, Object?>{
            'histogram': <String, Object?>{
              'dataPoints': <Object?>[
                for (final DVMetricPoint p in points)
                  <String, Object?>{
                    'attributes': _jsonAttributes(_labels(p.labels)),
                    'startTimeUnixNano': '$start',
                    'timeUnixNano': '$now',
                    'count': '${p.count.round()}',
                    'sum': p.value,
                    'bucketCounts': <String>[for (final int c in p.bucketCounts) '$c'],
                    'explicitBounds': p.bucketBounds,
                  },
              ],
              'aggregationTemporality': 2,
            },
          },
      },
    };
  }

  // Protobuf, field numbers from opentelemetry-proto v1.

  _PbWriter _pbResource() {
    final _PbWriter resource = _PbWriter();
    _pbAttributes(resource, 1, _resource);
    return resource;
  }

  static void _pbAttributes(_PbWriter into, int field, Map<String, Object> attributes) {
    for (final MapEntry<String, Object> entry in attributes.entries) {
      into.message(field, _PbWriter()
        ..string(1, entry.key)
        ..message(2, _pbValue(entry.value)));
    }
  }

  static _PbWriter _pbValue(Object value) {
    final _PbWriter any = _PbWriter();
    if (value is bool) {
      any.varint(2, value ? 1 : 0);
    } else if (value is int) {
      any.varint(3, value);
    } else if (value is double) {
      any.float64(4, value);
    } else if (value is List) {
      final _PbWriter array = _PbWriter();
      for (final Object item in value.cast<Object>()) {
        array.message(1, _pbValue(item));
      }
      any.message(5, array);
    } else {
      any.string(1, '$value');
    }
    return any;
  }

  static _PbWriter _pbSpan(DVSpan span) {
    final _PbWriter out = _PbWriter()
      ..bytes(1, _unhex(span.traceId))
      ..bytes(2, _unhex(span.spanId));
    if (span.parentSpanId != null) out.bytes(4, _unhex(span.parentSpanId!));
    out
      ..string(5, span.name)
      ..varint(6, _kind(span.kind))
      ..fixed64(7, span.startTimeUnixNano)
      ..fixed64(8, span.endTimeUnixNano ?? span.startTimeUnixNano);
    _pbAttributes(out, 9, span.attributes);
    if (span.droppedAttributes > 0) out.varint(10, span.droppedAttributes);
    for (final DVSpanEvent event in span.events) {
      final _PbWriter wire = _PbWriter()
        ..fixed64(1, event.timeUnixNano)
        ..string(2, event.name);
      _pbAttributes(wire, 3, event.attributes);
      out.message(11, wire);
    }
    final _PbWriter status = _PbWriter();
    if (span.statusMessage != null) status.string(2, span.statusMessage!);
    status.varint(3, _statusCode(span.status));
    out
      ..message(15, status)
      ..fixed32(16, span.sampled ? 1 : 0);
    return out;
  }

  static _PbWriter _pbLog(DVLogRecord record) {
    final int nanos = record.time.microsecondsSinceEpoch * 1000;
    final _PbWriter out = _PbWriter()
      ..fixed64(1, nanos)
      ..varint(2, _severity(record.level))
      ..string(3, record.level.name.toUpperCase())
      ..message(5, _PbWriter()..string(1, record.message));
    _pbAttributes(out, 6, _logAttributes(record));
    // Sampled, as the trace it was written in was: a record only carries a
    // trace id from a span the tracer kept or one a caller propagated.
    if (record.traceId != null) out.fixed32(8, 1);
    if (record.traceId != null) out.bytes(9, _unhex(record.traceId!));
    if (record.spanId != null) out.bytes(10, _unhex(record.spanId!));
    out.fixed64(11, nanos);
    if (record.event != null) out.string(12, record.event!);
    return out;
  }

  static _PbWriter _pbMetric(
      String name, List<DVMetricPoint> points, int start, int now) {
    final DVMetricPoint first = points.first;
    final _PbWriter out = _PbWriter()..string(1, _metricName(name));
    if (first.help != null) out.string(2, first.help!);
    if (first.unit != null) out.string(3, first.unit!);
    _PbWriter numberPoint(DVMetricPoint p) {
      final _PbWriter wire = _PbWriter()
        ..fixed64(2, start)
        ..fixed64(3, now)
        ..float64(4, p.value);
      _pbAttributes(wire, 7, _labels(p.labels));
      return wire;
    }

    switch (first.kind) {
      case DVMetricKind.counter:
        final _PbWriter sum = _PbWriter();
        for (final DVMetricPoint p in points) {
          sum.message(1, numberPoint(p));
        }
        sum
          ..varint(2, 2) // AGGREGATION_TEMPORALITY_CUMULATIVE
          ..varint(3, 1); // is_monotonic
        out.message(7, sum);
      case DVMetricKind.gauge:
        final _PbWriter gauge = _PbWriter();
        for (final DVMetricPoint p in points) {
          gauge.message(1, numberPoint(p));
        }
        out.message(5, gauge);
      case DVMetricKind.histogram:
        final _PbWriter histogram = _PbWriter();
        for (final DVMetricPoint p in points) {
          final _PbWriter wire = _PbWriter()
            ..fixed64(2, start)
            ..fixed64(3, now)
            ..fixed64(4, p.count.round())
            ..float64(5, p.value)
            ..packedFixed64(6, p.bucketCounts)
            ..packedFloat64(7, p.bucketBounds);
          _pbAttributes(wire, 9, _labels(p.labels));
          histogram.message(1, wire);
        }
        histogram.varint(2, 2);
        out.message(9, histogram);
    }
    return out;
  }

  static List<int> _unhex(String hex) => <int>[
        for (int i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
}

class _DVOtlpSpans implements DVTraceExporter {
  _DVOtlpSpans(this._exporter);
  final DVOtlpExporter _exporter;

  @override
  void export(DVSpan span) {
    if (!span.sampled) return;
    _exporter._spans.add(span);
  }
}

class _DVOtlpLogs implements DVLogSink {
  _DVOtlpLogs(this._exporter);
  final DVOtlpExporter _exporter;

  @override
  void write(DVLogRecord record) {
    if (record.tag == dvOtelLogTag) return;
    if (!record.level.atLeast(_exporter.config.logLevel)) return;
    _exporter._records.add(record);
  }
}

/// A bounded queue drained in batches by a timer or a full batch, one send in
/// flight at a time.
class _DVSignalQueue<T> {
  _DVSignalQueue(this._exporter, this._signal);

  final DVOtlpExporter _exporter;
  final DVOtelSignal _signal;
  final ListQueue<T> _items = ListQueue<T>();

  /// Resolved once: a span ends on every request, and parsing the URL again
  /// each time would be most of what adding it costs.
  late final Uri? _url = _exporter.config.endpointFor(_signal);
  Timer? _timer;
  Future<void>? _running;
  bool _closed = false;

  void add(T item) {
    final DVOpenTelemetryConfig config = _exporter.config;
    if (_closed || _url == null) return;
    if (_items.length >= config.maxQueueSize) {
      // Newest dropped, as the OpenTelemetry batch processor does: what is
      // already queued is older and closer to being sent.
      _exporter._drop(_signal, 1, 'queue_full');
      return;
    }
    _items.add(item);
    if (_items.length >= config.maxExportBatchSize) {
      _kick();
    } else {
      _timer ??= Timer(config.scheduleDelay, _kick);
    }
  }

  void _kick() {
    _timer?.cancel();
    _timer = null;
    _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    final Uri? url = _url;
    while (_items.isNotEmpty && url != null) {

      final int size = _exporter.config.maxExportBatchSize;
      final List<T> batch = <T>[];
      while (batch.length < size && _items.isNotEmpty) {
        batch.add(_items.removeFirst());
      }
      final List<int> body = _signal == DVOtelSignal.traces
          ? _exporter._encodeSpans(batch.cast<DVSpan>())
          : _exporter._encodeLogs(batch.cast<DVLogRecord>());
      await _exporter._deliver(_signal, url, body, batch.length);
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    while (_running != null || _items.isNotEmpty) {
      if (_running == null) _kick();
      await _running;
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Protobuf wire format, the subset OTLP needs.
class _PbWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  List<int> takeBytes() => _out.takeBytes();

  void _key(int field, int wire) => _rawVarint(field << 3 | wire);

  void _rawVarint(int value) {
    if (value < 0) {
      // An int64 below zero is ten bytes of two's complement. Written through
      // BigInt so it is right on the web as well, where int is a double.
      BigInt big = BigInt.from(value) + (BigInt.one << 64);
      final BigInt mask = BigInt.from(0x7f);
      while (big >= BigInt.from(0x80)) {
        _out.addByte(((big & mask).toInt()) | 0x80);
        big = big >> 7;
      }
      _out.addByte(big.toInt());
      return;
    }
    // Division rather than shifts: on the web a shift truncates to 32 bits.
    int rest = value;
    while (rest >= 0x80) {
      _out.addByte((rest % 0x80) | 0x80);
      rest = rest ~/ 0x80;
    }
    _out.addByte(rest);
  }

  void varint(int field, int value) {
    _key(field, 0);
    _rawVarint(value);
  }

  void _rawFixed64(int value) {
    final ByteData data = ByteData(8)
      ..setUint32(0, value % 0x100000000, Endian.little)
      ..setUint32(4, value ~/ 0x100000000, Endian.little);
    _out.add(data.buffer.asUint8List());
  }

  void fixed64(int field, int value) {
    _key(field, 1);
    _rawFixed64(value);
  }

  void fixed32(int field, int value) {
    _key(field, 5);
    _out.add((ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List());
  }

  void float64(int field, double value) {
    _key(field, 1);
    _out.add((ByteData(8)..setFloat64(0, value, Endian.little)).buffer.asUint8List());
  }

  void bytes(int field, List<int> value) {
    _key(field, 2);
    _rawVarint(value.length);
    _out.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, _PbWriter value) => bytes(field, value.takeBytes());

  void packedFixed64(int field, List<int> values) {
    final _PbWriter inner = _PbWriter();
    values.forEach(inner._rawFixed64);
    bytes(field, inner.takeBytes());
  }

  void packedFloat64(int field, List<double> values) {
    final ByteData data = ByteData(8 * values.length);
    for (int i = 0; i < values.length; i++) {
      data.setFloat64(8 * i, values[i], Endian.little);
    }
    bytes(field, data.buffer.asUint8List());
  }
}
