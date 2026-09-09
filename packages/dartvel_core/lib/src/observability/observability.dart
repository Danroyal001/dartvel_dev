/// The process-wide metrics and health registries.
///
/// One instance each, because a scrape endpoint and a health endpoint are
/// process-wide by definition: a metric recorded into a registry nothing
/// serves is a metric nobody sees.
library dartvel.observability;

import 'health.dart';
import 'logging.dart';
import 'metrics.dart';
import 'tracing.dart';

export 'health.dart';
export 'logging.dart';
export 'metrics.dart';
export 'tracing.dart';
export 'tracing_middleware.dart';

/// `DV.ObservabilityAndLogging` is built on these.
class DVObservability {
  const DVObservability._();

  static final DVMetrics metrics = DVMetrics();
  static final DVHealth health = DVHealth();

  /// The process tracer.
  ///
  /// Sampling everything by default: a framework that silently drops traces
  /// out of the box is one where the first thing anybody debugging it does is
  /// wonder whether tracing is on. Configure a ratio for production.
  static DVTracer tracer = DVTracer(sampler: DVTraceSampler.always());

  /// Points tracing at [exporter], sampling [ratio] of traces.
  static void useTracing({
    required DVTraceExporter exporter,
    double ratio = 1,
  }) {
    tracer = DVTracer(
      exporter: exporter,
      sampler: ratio >= 1
          ? DVTraceSampler.always()
          : DVTraceSampler.ratio(ratio),
    );
  }

  /// Where recent records are kept for `GET /_dartvel/logs` and
  /// `dartvel logs`.
  ///
  /// In memory and bounded, because the alternative was what shipped before:
  /// nothing at all, and a CLI command that had to admit it had no source to
  /// read.
  static DVMemoryLogSink _buffer = DVMemoryLogSink();

  /// The process logger.
  ///
  /// Its only sink out of the box is the buffer above. The server attaches a
  /// JSON-lines sink to stdout when it starts (`dvConfigureRuntimeLogging`);
  /// a library that printed on its own would put log lines into the middle of
  /// a Flutter test's output and a CLI's machine-readable stdout.
  static DVLogger logger = _newLogger(<DVLogSink>[_buffer]);

  static DVLogger _newLogger(List<DVLogSink> sinks, {DVLogLevel? level}) {
    final DVLogger created = DVLogger(
      minimumLevel: level ?? DVLogLevel.info,
      sinks: sinks,
    );
    created.onRecord = _count;
    return created;
  }

  /// Every record is counted by level, before the level filter.
  ///
  /// So an error rate computed from `dartvel_logs_total` does not move when
  /// somebody quietens the console.
  static void _count(DVLogRecord record) {
    metrics
        .counter(
          'logs_total',
          <String, String>{'level': record.level.name},
          'Log records emitted, by level, counted before the level filter.',
        )
        .increment();
  }

  /// Replaces the logger's sinks. [keepBuffer] keeps the recent-records
  /// buffer that the diagnostics endpoint serves.
  static void useLogging({
    required List<DVLogSink> sinks,
    DVLogLevel? level,
    bool keepBuffer = true,
    int bufferCapacity = 500,
  }) {
    _buffer = DVMemoryLogSink(capacity: bufferCapacity);
    logger = _newLogger(
      <DVLogSink>[if (keepBuffer) _buffer, ...sinks],
      level: level,
    );
  }

  /// Back to the default: the buffer, and nothing else.
  static void resetLogging() {
    _buffer = DVMemoryLogSink();
    logger = _newLogger(<DVLogSink>[_buffer]);
  }

  /// The recent records, oldest first.
  static List<DVLogRecord> get recentLogs => _buffer.records;

  /// `DV.log(...)`.
  static void log(
    String message, {
    DVLogLevel level = DVLogLevel.info,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      logger.log(
        message,
        level: level,
        context: context,
        code: code,
        error: error,
        stackTrace: stackTrace,
      );

  /// `DV.ObservabilityAndLogging.event(...)`: a record a query can select by
  /// name instead of by matching the wording of a sentence.
  static void event(
    String name, [
    Map<String, Object?> attributes = const <String, Object?>{},
  ]) =>
      logger.log(name, event: name, context: attributes);

  /// Error reporting: one structured record, and one increment of the error
  /// counter that an alert can be written against.
  ///
  /// Takes the stack separately rather than reading `StackTrace.current`, so
  /// the trace points at where the failure happened and not at this line.
  static void captureError(
    Object error,
    StackTrace? stackTrace, {
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
  }) =>
      logger.error(
        message ?? error.toString(),
        error: error,
        stackTrace: stackTrace,
        context: context,
        code: code,
      );

  /// Seconds this process has been up, as a gauge.
  ///
  /// Read at render time rather than recorded on a timer: a value refreshed by
  /// a periodic task is stale by up to its interval and keeps a timer alive
  /// for the life of the process to maintain a number that can be computed.
  static void refresh() {
    metrics
        .gauge('uptime_seconds', const <String, String>{},
            'Seconds since this process started.')
        .set(health.uptime.inMilliseconds / 1000);
  }

  /// The registry in Prometheus text exposition format, with the values that
  /// are computed rather than accumulated brought up to date first.
  static String render() {
    refresh();
    return metrics.render();
  }
}
