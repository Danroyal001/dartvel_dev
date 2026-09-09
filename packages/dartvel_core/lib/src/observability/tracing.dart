/// Traces: spans, W3C context propagation, and sampling.
///
/// Dartvel listed OpenTelemetry as an inspiration and traces as built in, and
/// had neither. Middleware is specified to propagate trace IDs and job
/// handlers to run with trace context; there was nothing to propagate.
///
/// The wire format is W3C Trace Context rather than a Dartvel one, because the
/// point of a trace ID is that something else recognises it.
library dartvel.observability.tracing;

import 'dart:async';
import 'dart:math';

import '../secrets/secrets.dart';

/// The zone key the current span hangs on.
///
/// A zone rather than a parameter threaded through every function: a query
/// three calls deep has to be able to hang a child span off the request's
/// without each function in between taking a span it does not otherwise use.
/// That threading is exactly the boilerplate that stops people instrumenting
/// anything.
///
/// It lives here rather than beside the HTTP middleware that first set it,
/// because logging needs to read it too and a log line that cannot name the
/// trace it happened inside is half of an investigation.
const Object dvSpanZoneKey = #dartvelSpan;

/// The span the current call is inside, if any.
DVSpan? get dvCurrentSpan => Zone.current[dvSpanZoneKey] as DVSpan?;

/// Runs [body] with [span] as the ambient span.
R dvInSpan<R>(DVSpan span, R Function() body) =>
    runZoned(body, zoneValues: <Object, Object?>{dvSpanZoneKey: span});

/// The trace a request belongs to, as it travels between services.
///
/// Serialised as a `traceparent` header:
/// `00-<32 hex trace id>-<16 hex span id>-<2 hex flags>`.
class DVTraceContext {
  const DVTraceContext({
    required this.traceId,
    required this.parentSpanId,
    required this.sampled,
  });

  final String traceId;
  final String parentSpanId;

  /// Whether the trace is being recorded.
  ///
  /// Carried rather than re-decided downstream: a service that rolls its own
  /// dice drops the middle out of a trace someone else chose to keep.
  final bool sampled;

  static final Random _random = Random.secure();

  /// Reads a `traceparent`, or null if it is not one.
  ///
  /// Null rather than an exception: this arrives from outside, and turning
  /// someone else's misconfiguration into a 500 here is worse than starting a
  /// new trace.
  static DVTraceContext? parse(String? header) {
    if (header == null) return null;
    final List<String> parts = header.trim().toLowerCase().split('-');
    // Exactly four: a trailing field belongs to a version this does not know,
    // whose layout may differ.
    if (parts.length != 4) return null;

    final String version = parts[0];
    if (version.length != 2 || !_isHex(version)) return null;
    // ff is reserved as invalid, and any other unknown version may lay the
    // fields out differently -- read as this one it yields a plausible wrong
    // id, which is worse than no id.
    if (version != '00') return null;

    final String traceId = parts[1];
    final String spanId = parts[2];
    final String flags = parts[3];
    if (traceId.length != 32 || !_isHex(traceId)) return null;
    if (spanId.length != 16 || !_isHex(spanId)) return null;
    if (flags.length != 2 || !_isHex(flags)) return null;

    // All-zero ids are invalid by the specification. Accepting them puts every
    // service that sends one into a single shared trace.
    if (traceId == '0' * 32) return null;
    if (spanId == '0' * 16) return null;

    return DVTraceContext(
      traceId: traceId,
      parentSpanId: spanId,
      sampled: int.parse(flags, radix: 16) & 0x01 == 0x01,
    );
  }

  String toHeader() =>
      '00-$traceId-$parentSpanId-${sampled ? '01' : '00'}';

  static String newTraceId() => _hex(16);
  static String newSpanId() => _hex(8);

  static String _hex(int bytes) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < bytes; i += 1) {
      out.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    final String value = out.toString();
    // An all-zero id is invalid, and while the odds are negligible the check
    // is one comparison against emitting an id every consumer rejects.
    return int.parse(value.substring(0, 8), radix: 16) == 0 &&
            value == '0' * value.length
        ? _hex(bytes)
        : value;
  }

  static bool _isHex(String value) {
    for (final int unit in value.codeUnits) {
      final bool digit = unit >= 0x30 && unit <= 0x39;
      final bool lower = unit >= 0x61 && unit <= 0x66;
      if (!digit && !lower) return false;
    }
    return value.isNotEmpty;
  }
}

enum DVSpanStatus { unset, ok, error }

/// One unit of work inside a trace.
class DVSpan {
  DVSpan._({
    required this.name,
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.sampled,
    required DVTraceExporter? exporter,
  })  : _exporter = exporter,
        startedAt = DateTime.now(),
        _stopwatch = Stopwatch()..start();

  final String name;
  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final bool sampled;
  final DateTime startedAt;

  final Map<String, String> attributes = <String, String>{};
  DVSpanStatus status = DVSpanStatus.unset;

  final DVTraceExporter? _exporter;
  final Stopwatch _stopwatch;
  bool _ended = false;

  Duration? get duration => _ended ? _stopwatch.elapsed : null;

  /// The context a call made inside this span should send.
  ///
  /// Names this span, not its parent: sending the parent's id would make every
  /// downstream span a sibling of this one rather than its child, and the
  /// trace renders flat.
  DVTraceContext get context => DVTraceContext(
        traceId: traceId,
        parentSpanId: spanId,
        sampled: sampled,
      );

  /// Records [value] against [key], with any resolved secret struck out.
  ///
  /// Spans usually leave the building. A log file at least sits on
  /// infrastructure the operator runs, while traces go to a hosted backend,
  /// so a database URL carrying its password into `db.url` is a credential
  /// handed to a third party and then to everyone who can read that account.
  void setAttribute(String key, String value) =>
      attributes[key] = dvRedactSecrets(value);

  /// The span as a trace view reads it.
  ///
  /// Duration in milliseconds rather than the `Duration` object, because this
  /// crosses a process boundary as JSON and a reader on the other side has no
  /// Dart types.
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'traceId': traceId,
        'spanId': spanId,
        if (parentSpanId != null) 'parentSpanId': parentSpanId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (duration != null)
          'durationMs': duration!.inMicroseconds / 1000,
        'status': status.name,
        if (attributes.isNotEmpty) 'attributes': attributes,
      };

  void recordError(Object error, [StackTrace? stackTrace]) {
    status = DVSpanStatus.error;
    // Through setAttribute rather than straight into the map, because an
    // upstream client quoting the rejected key back at you is one of the
    // commonest ways a credential ends up in an error string.
    setAttribute('error', '$error');
    if (stackTrace != null) setAttribute('error.stack', '$stackTrace');
  }

  /// Finishes the span and exports it.
  ///
  /// Ending twice is a no-op. A span ended in both a finally and an error
  /// handler is ordinary, and a duplicate export doubles every count computed
  /// from spans.
  void end() {
    if (_ended) return;
    _ended = true;
    _stopwatch.stop();
    if (status == DVSpanStatus.unset) status = DVSpanStatus.ok;
    if (sampled) _exporter?.export(this);
  }
}

/// Decides whether a trace is recorded.
class DVTraceSampler {
  const DVTraceSampler._(this._ratio);

  factory DVTraceSampler.always() => const DVTraceSampler._(1);
  factory DVTraceSampler.never() => const DVTraceSampler._(0);

  /// Samples [ratio] of traces, deterministically per trace id.
  factory DVTraceSampler.ratio(double ratio) {
    if (ratio < 0 || ratio > 1) {
      throw ArgumentError.value(
        ratio,
        'ratio',
        'a sampling ratio is between 0 and 1',
      );
    }
    return DVTraceSampler._(ratio);
  }

  final double _ratio;

  /// Whether [traceId] is sampled.
  ///
  /// A function of the trace id alone, and that is what makes a distributed
  /// trace whole. If each service rolls its own dice a request is sampled by
  /// all of them with probability p to the power of the number of services --
  /// at 10% across four that is one in ten thousand, and tracing appears to be
  /// on and finding nothing.
  bool shouldSample(String traceId) {
    if (_ratio >= 1) return true;
    if (_ratio <= 0) return false;
    // The low 7 hex digits, which is 28 bits: enough resolution for any
    // realistic ratio and small enough to stay exact in a double on every
    // platform, JavaScript included.
    final int value =
        int.parse(traceId.substring(traceId.length - 7), radix: 16);
    return value / 0x10000000 < _ratio;
  }
}

/// Where finished spans go.
abstract class DVTraceExporter {
  void export(DVSpan span);
}

/// Keeps them in a list. For tests, and for `dartvel inspect`.
class DVMemoryTraceExporter implements DVTraceExporter {
  final List<DVSpan> spans = <DVSpan>[];

  @override
  void export(DVSpan span) => spans.add(span);

  void clear() => spans.clear();
}

/// Keeps the most recent spans and forgets the rest.
///
/// This is the one the process holds open for its whole life, so it cannot be
/// the unbounded kind: a server doing a thousand requests a second would
/// otherwise be storing every span it ever produced, and the trace buffer
/// would outgrow the application it belongs to.
class DVRecentSpansExporter implements DVTraceExporter {
  DVRecentSpansExporter({this.capacity = 200})
      : assert(capacity > 0, 'a buffer that holds nothing records nothing');

  final int capacity;
  final List<DVSpan> _spans = <DVSpan>[];

  /// Oldest first.
  List<DVSpan> get spans => List<DVSpan>.unmodifiable(_spans);

  @override
  void export(DVSpan span) {
    _spans.add(span);
    if (_spans.length > capacity) {
      _spans.removeRange(0, _spans.length - capacity);
    }
  }

  void clear() => _spans.clear();
}

/// Sends each span to every exporter, and keeps going when one throws.
///
/// Configuring a collector must not be what removes the local buffer: before
/// this, pointing tracing anywhere replaced the exporter outright, and the
/// spans a developer could read on the machine in front of them disappeared
/// the moment the application became worth tracing.
class DVFanoutTraceExporter implements DVTraceExporter {
  DVFanoutTraceExporter(this.exporters);

  final List<DVTraceExporter> exporters;

  @override
  void export(DVSpan span) {
    for (final DVTraceExporter exporter in exporters) {
      try {
        exporter.export(span);
      } on Object {
        // A collector that is down must not take the request with it, nor
        // stop the other exporters from seeing the span.
      }
    }
  }
}

/// Starts spans.
class DVTracer {
  DVTracer({DVTraceExporter? exporter, DVTraceSampler? sampler})
      : _exporter = exporter,
        _sampler = sampler ?? DVTraceSampler.always();

  final DVTraceExporter? _exporter;
  final DVTraceSampler _sampler;

  /// Begins a span.
  ///
  /// [context] is an incoming trace to join; [parent] is a span in this
  /// process. Given neither, this starts a new trace.
  DVSpan startSpan(
    String name, {
    DVSpan? parent,
    DVTraceContext? context,
  }) {
    if (parent != null) {
      return DVSpan._(
        name: name,
        traceId: parent.traceId,
        spanId: DVTraceContext.newSpanId(),
        parentSpanId: parent.spanId,
        sampled: parent.sampled,
        exporter: _exporter,
      );
    }

    if (context != null) {
      // The caller's decision, not ours: re-deciding drops the middle out of
      // a trace someone upstream chose to keep, and keeps the middle of one
      // they chose to drop.
      return DVSpan._(
        name: name,
        traceId: context.traceId,
        spanId: DVTraceContext.newSpanId(),
        parentSpanId: context.parentSpanId,
        sampled: context.sampled,
        exporter: _exporter,
      );
    }

    final String traceId = DVTraceContext.newTraceId();
    return DVSpan._(
      name: name,
      traceId: traceId,
      spanId: DVTraceContext.newSpanId(),
      parentSpanId: null,
      sampled: _sampler.shouldSample(traceId),
      exporter: _exporter,
    );
  }

  /// Runs [body] inside a span, ending it either way and recording a throw.
  Future<T> trace<T>(
    String name,
    Future<T> Function(DVSpan span) body, {
    DVSpan? parent,
    DVTraceContext? context,
  }) async {
    final DVSpan span = startSpan(name, parent: parent, context: context);
    try {
      return await body(span);
    } on Object catch (error, stack) {
      span.recordError(error, stack);
      rethrow;
    } finally {
      span.end();
    }
  }
}
