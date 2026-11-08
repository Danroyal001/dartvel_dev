/// OTLP over HTTP: how spans reach a collector.
///
/// One exporter rather than one per vendor, because Jaeger, Tempo, Honeycomb,
/// Datadog and the OpenTelemetry Collector all accept OTLP, and an adapter per
/// vendor would be five copies of one protocol.
///
/// The JSON encoding of OTLP/HTTP, not protobuf: it is part of the same
/// specification, every OTLP/HTTP receiver that matters reads it, and it needs
/// no generated code or protobuf runtime in a package that also ships to the
/// browser.
library dartvel.observability.otlp_exporter;

import 'dart:async';
import 'dart:convert';

import '../http/transport.dart';
import 'observability.dart';

/// Batches finished spans on a bounded queue and posts them to an OTLP/HTTP
/// collector.
///
/// [export] only enqueues. It never waits on the network, so a collector that
/// is slow or down cannot add latency to the request being measured -- the
/// failure mode that gets tracing removed rather than fixed. A full queue drops
/// the span and counts it (`DV-TRACE-002`); a batch the collector will not
/// take after the declared retries is dropped and counted (`DV-TRACE-003`).
/// Each is logged once per burst rather than once per span, because a log line
/// per dropped span at volume is a second outage on top of the first.
class DVOtlpTraceExporter implements DVTraceExporter {
  DVOtlpTraceExporter({
    required Uri endpoint,
    this.serviceName = 'dartvel',
    Map<String, String> headers = const <String, String>{},
    this.queueCapacity = 2048,
    this.batchSize = 512,
    this.flushInterval = const Duration(seconds: 5),
    this.retries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    DVHttpSend? send,
  }) : endpoint = _tracesPath(endpoint),
       headers = Map<String, String>.unmodifiable(headers),
       _send = send ?? dvSendHttpRequest {
    if (queueCapacity < 1) {
      throw ArgumentError.value(
        queueCapacity,
        'queueCapacity',
        'a queue that holds nothing exports nothing',
      );
    }
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'cannot be negative');
    }
  }

  /// Where batches are posted: the configured endpoint with `/v1/traces`
  /// appended, unless it already ends with it.
  final Uri endpoint;

  /// `service.name` on every batch's resource: what a trace backend groups by.
  final String serviceName;

  /// Sent with every batch -- typically a collector's API key.
  final Map<String, String> headers;

  final int queueCapacity;
  final int batchSize;
  final Duration flushInterval;

  /// Further attempts after the first, for a network failure or a 408, 429,
  /// 502, 503 or 504. Any other refusal is not retried: the same payload would
  /// be refused again.
  final int retries;
  final Duration retryDelay;

  final DVHttpSend _send;
  final List<DVSpan> _queue = <DVSpan>[];
  Timer? _timer;
  Future<void>? _inFlight;
  bool _closed = false;
  bool _fullReported = false;

  int _exported = 0;
  int _droppedQueueFull = 0;
  int _droppedUnreachable = 0;

  /// Spans the collector accepted.
  int get exported => _exported;

  /// Spans dropped because the queue was full (`DV-TRACE-002`).
  int get droppedQueueFull => _droppedQueueFull;

  /// Spans dropped because the collector could not take them
  /// (`DV-TRACE-003`).
  int get droppedUnreachable => _droppedUnreachable;

  /// Spans waiting to be sent, not counting a batch in flight.
  int get queued => _queue.length;

  static Uri _tracesPath(Uri endpoint) {
    if (endpoint.path.endsWith('/v1/traces')) return endpoint;
    final String base = endpoint.path.endsWith('/')
        ? endpoint.path.substring(0, endpoint.path.length - 1)
        : endpoint.path;
    return endpoint.replace(path: '$base/v1/traces');
  }

  @override
  void export(DVSpan span) {
    if (_closed) return;
    if (_queue.length >= queueCapacity) {
      _droppedQueueFull += 1;
      _countDrop('queue_full');
      if (!_fullReported) {
        _fullReported = true;
        _outsideTrace(
          () => DVObservability.log(
            'DV-TRACE-002: the trace export queue is full '
            '($queueCapacity spans); spans are being dropped.',
            level: DVLogLevel.warn,
            code: 'DV-TRACE-002',
            context: <String, Object?>{
              'endpoint': '${endpoint.scheme}://${endpoint.authority}',
              'capacity': queueCapacity,
            },
          ),
        );
      }
      return;
    }
    _queue.add(span);
    if (_queue.length >= batchSize) {
      _pump();
    } else {
      _timer ??= _outsideTrace(
        () => Timer(flushInterval, () {
          _timer = null;
          _pump();
        }),
      );
    }
  }

  /// Completes when nothing is in flight. Spans still queued below a full
  /// batch stay queued; [flush] sends those too.
  Future<void> get idle async {
    while (_inFlight != null) {
      await _inFlight;
    }
  }

  /// Sends everything queued now, and waits for it.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await idle;
    while (_queue.isNotEmpty) {
      _pump(partial: true);
      await idle;
    }
  }

  /// Flushes, then accepts nothing more. For process shutdown, so the last
  /// requests' spans are not lost with the process.
  Future<void> close() async {
    await flush();
    _closed = true;
  }

  /// Starts a send unless one is in flight. One batch at a time: a collector
  /// that is down must not turn into one hanging connection per batch.
  void _pump({bool partial = false}) {
    if (_inFlight != null) return;
    if (_queue.isEmpty) return;
    if (!partial && _queue.length < batchSize && _timer != null) return;
    final List<DVSpan> batch = _queue.sublist(
      0,
      _queue.length < batchSize ? _queue.length : batchSize,
    );
    _queue.removeRange(0, batch.length);
    _inFlight = _outsideTrace(() => _sendBatch(batch)).whenComplete(() {
      _inFlight = null;
      if (_queue.length >= batchSize) {
        _pump();
      } else if (_queue.isNotEmpty && _timer == null && !_closed) {
        _timer = _outsideTrace(
          () => Timer(flushInterval, () {
            _timer = null;
            _pump();
          }),
        );
      }
    });
  }

  Future<void> _sendBatch(List<DVSpan> batch) async {
    final DVHttpRequest request = DVHttpRequest(
      url: endpoint,
      method: 'POST',
      headers: <String, String>{...headers, 'content-type': 'application/json'},
      body: utf8.encode(
        jsonEncode(dvOtlpTracesJson(batch, serviceName: serviceName)),
      ),
    );

    Object? failure;
    for (int attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0 && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay * attempt);
      }
      try {
        final DVHttpResponse response = await _send(request);
        if (response.isSuccess) {
          _exported += batch.length;
          // A queue that drained is a queue whose next overflow is news.
          _fullReported = false;
          return;
        }
        failure = 'HTTP ${response.statusCode}';
        if (!_retryable(response.statusCode)) break;
      } on Object catch (error) {
        failure = error;
      }
    }

    _droppedUnreachable += batch.length;
    _countDrop('unreachable', batch.length);
    DVObservability.log(
      'DV-TRACE-003: the trace collector did not accept ${batch.length} '
      'spans after ${retries + 1} attempts ($failure); they were dropped.',
      level: DVLogLevel.error,
      code: 'DV-TRACE-003',
      context: <String, Object?>{
        'endpoint': '${endpoint.scheme}://${endpoint.authority}',
        'spans': batch.length,
        'attempts': retries + 1,
      },
    );
  }

  static bool _retryable(int status) =>
      status == 408 ||
      status == 429 ||
      status == 502 ||
      status == 503 ||
      status == 504;

  static void _countDrop(String reason, [int count = 1]) {
    DVObservability.metrics
        .counter('trace_spans_dropped_total', <String, String>{
          'reason': reason,
        }, 'Finished spans the trace exporter dropped, by reason.')
        .increment(count.toDouble());
  }

  /// Runs [body] with no ambient span.
  ///
  /// A span ends inside the request's zone, and a timer or a send started
  /// there would inherit it: the export would log against the request's trace
  /// and an instrumented client would trace the export as part of the
  /// request it is reporting.
  static R _outsideTrace<R>(R Function() body) =>
      runZoned(body, zoneValues: <Object, Object?>{dvSpanZoneKey: null});
}

/// [spans] as an OTLP `ExportTraceServiceRequest`, in the JSON mapping.
///
/// Ids are hex, as the OTLP JSON mapping requires (the protobuf JSON default
/// would be base64, and a collector reading one as the other links nothing).
/// Times are nanoseconds since the epoch, as decimal strings so a 64-bit value
/// survives a JavaScript reader.
Map<String, Object?> dvOtlpTracesJson(
  List<DVSpan> spans, {
  required String serviceName,
}) => <String, Object?>{
  'resourceSpans': <Object?>[
    <String, Object?>{
      'resource': <String, Object?>{
        'attributes': <Object?>[_attribute('service.name', serviceName)],
      },
      'scopeSpans': <Object?>[
        <String, Object?>{
          'scope': <String, Object?>{'name': 'dartvel'},
          'spans': <Object?>[for (final DVSpan span in spans) _span(span)],
        },
      ],
    },
  ],
};

Map<String, Object?> _span(DVSpan span) {
  final int start = span.startedAt.microsecondsSinceEpoch;
  final int end = start + (span.duration ?? Duration.zero).inMicroseconds;
  final String? error = span.attributes['error'];
  return <String, Object?>{
    'traceId': span.traceId,
    'spanId': span.spanId,
    if (span.parentSpanId != null) 'parentSpanId': span.parentSpanId,
    'name': span.name,
    // OTLP numbers kinds from 1; 0 is "unspecified".
    'kind': span.kind.index + 1,
    'startTimeUnixNano': '${start * 1000}',
    'endTimeUnixNano': '${end * 1000}',
    'attributes': <Object?>[
      for (final MapEntry<String, String> entry in span.attributes.entries)
        _attribute(entry.key, entry.value),
    ],
    if (span.droppedAttributes > 0)
      'droppedAttributesCount': span.droppedAttributes,
    if (span.links.isNotEmpty)
      'links': <Object?>[
        for (final DVTraceContext link in span.links)
          <String, Object?>{
            'traceId': link.traceId,
            'spanId': link.parentSpanId,
          },
      ],
    'status': <String, Object?>{
      'code': switch (span.status) {
        DVSpanStatus.unset => 0,
        DVSpanStatus.ok => 1,
        DVSpanStatus.error => 2,
      },
      if (span.status == DVSpanStatus.error && error != null) 'message': error,
    },
  };
}

Map<String, Object?> _attribute(String key, String value) => <String, Object?>{
  'key': key,
  'value': <String, Object?>{'stringValue': value},
};
