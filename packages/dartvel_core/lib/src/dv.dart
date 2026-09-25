/// `DV`: the namespace a server's code logs through.
///
/// The specification names two spellings for application logging, `DV.log`
/// and `DV.ObservabilityAndLogging`. Only the Flutter layer had them, and a
/// backend function does not import that layer -- a server build is pure
/// Dart -- so every backend function, and every file of the framework, wrote
/// `DVObservability.log`, which is neither.
library dartvel_core.dv;

import 'cache/dv_cache.dart';
import 'observability/observability.dart';

/// Logs, events, errors, metrics, health and traces, as the specification
/// names them: `DV.ObservabilityAndLogging`.
class DVObservabilityAndLogging {
  const DVObservabilityAndLogging();

  /// One line, with whatever context belongs beside it.
  void log(
    String message, {
    DVLogLevel level = DVLogLevel.info,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      DVObservability.log(
        message,
        level: level,
        context: context,
        code: code,
        error: error,
        stackTrace: stackTrace,
      );

  /// A record a query can select by name instead of by matching the wording
  /// of a sentence.
  void event(String name,
          {Map<String, Object?> fields = const <String, Object?>{}}) =>
      DVObservability.event(name, fields);

  /// One structured record and one increment of the error counter.
  void captureError(
    Object error,
    StackTrace? stackTrace, {
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
  }) =>
      DVObservability.captureError(error, stackTrace,
          message: message, context: context, code: code);

  /// What this process has counted.
  DVMetrics get metrics => DVObservability.metrics;

  /// What this process reports about itself.
  DVHealth get health => DVObservability.health;

  /// The lines this process still holds, newest last.
  List<DVLogRecord> get recentLogs => DVObservability.recentLogs;

  /// The spans this process still holds.
  List<DVSpan> get recentSpans => DVObservability.recentSpans;

  /// The tracer a request's span is opened on.
  DVTracer get tracer => DVObservability.tracer;

  /// Where lines go: the sinks beside the buffer, and the level below which
  /// nothing is written.
  void useLogging({
    required List<DVLogSink> sinks,
    DVLogLevel? level,
    bool keepBuffer = true,
    int bufferCapacity = 500,
  }) =>
      DVObservability.useLogging(
        sinks: sinks,
        level: level,
        keepBuffer: keepBuffer,
        bufferCapacity: bufferCapacity,
      );

  /// Back to the default sinks and an empty buffer. For tests.
  void resetLogging() => DVObservability.resetLogging();
}

/// The framework's namespace, on the server side of a Dartvel project.
///
/// The Flutter layer declares its own `DV` with everything an application
/// reaches for; this is what a backend function, a job or the server itself
/// can use, spelled the same way.
abstract final class DV {
  /// Logs, events, errors, metrics, health and traces.
  // ignore: non_constant_identifier_names -- the specification's spelling.
  static const DVObservabilityAndLogging ObservabilityAndLogging =
      DVObservabilityAndLogging();

  /// The cache: `get`, `set`, `has` and `delete`, with read-through, tags
  /// and bulk deletes as options on them. The same cache a page's `DV.Cache`
  /// reaches, in the store `dartvel.cache` names; `withAdapter` switches
  /// store in code.
  // ignore: non_constant_identifier_names -- the specification's spelling.
  static const DVCache Cache = DVCache();

  /// The short spelling of `DV.ObservabilityAndLogging.log`.
  static void log(
    String message, {
    DVLogLevel level = DVLogLevel.info,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      ObservabilityAndLogging.log(
        message,
        level: level,
        context: context,
        code: code,
        error: error,
        stackTrace: stackTrace,
      );
}
