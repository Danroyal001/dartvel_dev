/// `DV.log`: the one way application code, the framework and the platform
/// write a log record.
///
/// A call is `DV.log('message', tag: ..., context: {...})`, and each level
/// has its own method -- `DV.log.warn(...)`, `DV.log.error(...)` -- taking
/// the same shape. Where a record goes is the runtime's business: stdout as
/// JSON lines on a server, the platform log and a capped file on a device,
/// the console in a browser, and the application's backend when a project
/// turns shipping on.
library dartvel.observability.log;

import 'observability.dart';

/// What `DV.log` is.
final class DVLog {
  const DVLog();

  /// Writes one record at [level].
  ///
  /// [tag] is the record's category, [context] its fields: values a query
  /// filters on belong there rather than inside [message]. Sensitive model
  /// fields, credential-shaped values and resolved secrets are redacted
  /// before any destination sees the record.
  void call(
    String message, {
    DVLogLevel level = DVLogLevel.info,
    String? tag,
    Map<String, Object?> context = const <String, Object?>{},
    String? code,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      DVObservability.logger.log(
        message,
        level: level,
        tag: tag,
        context: context,
        code: code,
        error: error,
        stackTrace: stackTrace,
      );

  void trace(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{}}) =>
      call(message, level: DVLogLevel.trace, tag: tag, context: context);

  void debug(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{}}) =>
      call(message, level: DVLogLevel.debug, tag: tag, context: context);

  void info(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{}}) =>
      call(message, tag: tag, context: context);

  void warn(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{},
          Object? error,
          StackTrace? stackTrace}) =>
      call(message,
          level: DVLogLevel.warn,
          tag: tag,
          context: context,
          error: error,
          stackTrace: stackTrace);

  void error(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{},
          Object? error,
          StackTrace? stackTrace,
          String? code}) =>
      call(message,
          level: DVLogLevel.error,
          tag: tag,
          context: context,
          error: error,
          stackTrace: stackTrace,
          code: code);

  void fatal(String message,
          {String? tag,
          Map<String, Object?> context = const <String, Object?>{},
          Object? error,
          StackTrace? stackTrace,
          String? code}) =>
      call(message,
          level: DVLogLevel.fatal,
          tag: tag,
          context: context,
          error: error,
          stackTrace: stackTrace,
          code: code);

  /// The records this process still holds in memory, oldest first.
  List<DVLogRecord> get recent => DVObservability.recentLogs;

  /// Everything kept, oldest first, one JSON object per line: the device's
  /// log file when there is one, otherwise the in-memory records. What a
  /// person sends when they are asked for the logs.
  Future<String> export() async {
    final DVLogFile? file = DVObservability.logFile;
    if (file != null) return file.export();
    final StringBuffer out = StringBuffer();
    for (final DVLogRecord record in DVObservability.recentLogs) {
      out.writeln(record.toJsonLine());
    }
    return out.toString();
  }

  /// Removes every kept record, on disk and in memory.
  Future<void> clear() async {
    DVObservability.logFile?.clear();
    DVObservability.clearRecentLogs();
  }
}
