/// Structured logs, which the runtime did not have.
///
/// `Logs` sat in the specification's built-in list beside metrics and traces,
/// and there was no sink anywhere: a server-side `DV.log` call went nowhere,
/// so the one signal every application produces from its first day was the one
/// signal Dartvel dropped.
///
/// Records are objects with a level, a message, a context map and the trace
/// they happened inside, and they render as one JSON object per line. That
/// shape is deliberate. A log line is read three times -- by a person during
/// an incident, by a query in a log store, and increasingly by a model being
/// asked what went wrong -- and only the first of those can do anything with
/// a sentence that pastes a value into the middle of prose.
///
/// No `dart:io` here. This library is reachable from a Flutter web build
/// through the `dartvel` barrel, and an import of `dart:io` anywhere along
/// that path fails the build for the whole application.
library dartvel.observability.logging;

import 'dart:convert';

import '../secrets/secrets.dart';
import 'tracing.dart';

/// How much a record matters, in the order everyone already expects.
///
/// The names are the ones log stores index on, so `warn` rather than
/// `warning`: renaming it here would mean every saved query written against a
/// Dartvel service has to know which one it is looking at.
enum DVLogLevel {
  trace,
  debug,
  info,
  warn,
  error,

  /// The process cannot continue. Logging this does not stop it -- deciding
  /// that belongs to the caller, not to a logger.
  fatal;

  /// Whether a record at this level passes a sink set to [minimum].
  bool atLeast(DVLogLevel minimum) => index >= minimum.index;

  /// Reads a level name, falling back rather than throwing.
  ///
  /// A misspelled level in a configuration file should not take the process
  /// down on the way up, and it should not silently mean `trace` either: an
  /// unreadable value logs more than intended, which is the direction that
  /// leaks.
  static DVLogLevel parse(String name, {DVLogLevel fallback = DVLogLevel.info}) {
    final String wanted = name.trim().toLowerCase();
    for (final DVLogLevel level in DVLogLevel.values) {
      if (level.name == wanted) return level;
    }
    // The two spellings people reach for that are not the canonical names.
    if (wanted == 'warning') return DVLogLevel.warn;
    if (wanted == 'verbose') return DVLogLevel.trace;
    return fallback;
  }
}

/// One log line.
class DVLogRecord {
  DVLogRecord({
    required this.level,
    required this.message,
    DateTime? time,
    this.tag,
    this.context = const <String, Object?>{},
    this.event,
    this.code,
    this.error,
    this.stackTrace,
    this.traceId,
    this.spanId,
  }) : time = time ?? DateTime.now();

  /// Reads a record back from [toJson]'s shape: a line from the device's log
  /// file, or one a client sent to its backend.
  ///
  /// Strict about the three fields every record has, because a line that is
  /// missing one was cut short or was never a record, and reading it as one
  /// would put a plausible line with the wrong level into an export.
  factory DVLogRecord.fromJson(Map<String, Object?> json) {
    final Object? time = json['time'];
    final Object? level = json['level'];
    final Object? message = json['message'];
    if (time is! String || level is! String || message is! String) {
      throw const FormatException(
          'a log record has a time, a level and a message, each a string');
    }
    final DateTime? parsedTime = DateTime.tryParse(time);
    final DVLogLevel? parsedLevel = DVLogLevel.values
        .where((DVLogLevel candidate) => candidate.name == level)
        .firstOrNull;
    if (parsedTime == null || parsedLevel == null) {
      throw FormatException('not a log record time and level', '$time $level');
    }
    String? text(String key) {
      final Object? value = json[key];
      if (value == null) return null;
      if (value is! String) throw FormatException('$key must be a string');
      return value;
    }

    final Object? context = json['context'];
    if (context != null && context is! Map) {
      throw const FormatException('context must be a map');
    }
    return DVLogRecord(
      level: parsedLevel,
      message: message,
      time: parsedTime,
      tag: text('tag'),
      context: context == null
          ? const <String, Object?>{}
          : <String, Object?>{
              for (final MapEntry<Object?, Object?> entry
                  in (context as Map<Object?, Object?>).entries)
                '${entry.key}': entry.value,
            },
      event: text('event'),
      code: text('code'),
      error: text('error'),
      stackTrace: text('stack'),
      traceId: text('traceId'),
      spanId: text('spanId'),
    );
  }

  final DateTime time;
  final DVLogLevel level;
  final String message;

  /// The category a record belongs to: `checkout`, `dartvel.auth`,
  /// `native.android`. A filter in a log store, in the device's console and
  /// in an export, where a message is only searchable by its wording.
  final String? tag;

  /// The structured part. Everything a query might filter on belongs here
  /// rather than interpolated into [message], because a value inside a
  /// sentence can only be found by a substring search.
  final Map<String, Object?> context;

  /// A machine-selectable name, for `DV.ObservabilityAndLogging.event`.
  final String? event;

  /// A `DV-...` diagnostic code, which `dartvel explain` can look up.
  final String? code;

  final String? error;
  final String? stackTrace;

  /// The trace this happened inside, when there was one.
  ///
  /// This is the field that makes logs and traces one story rather than two:
  /// without it, finding the log lines belonging to a slow request means
  /// guessing from timestamps.
  final String? traceId;
  final String? spanId;

  Map<String, Object?> toJson() => <String, Object?>{
        'time': time.toUtc().toIso8601String(),
        'level': level.name,
        'message': message,
        if (tag != null) 'tag': tag,
        if (event != null) 'event': event,
        if (code != null) 'code': code,
        if (context.isNotEmpty) 'context': context,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stack': stackTrace,
      };

  /// The record as a single line.
  ///
  /// One line, always: every line-oriented log collector there is splits on
  /// newlines, so a record that wraps arrives as several broken ones -- which
  /// is exactly what happens to a stack trace pasted in raw.
  String toJsonLine() => jsonEncode(toJson());

  @override
  String toString() => toJsonLine();
}

/// Where records go.
abstract class DVLogSink {
  void write(DVLogRecord record);
}

/// Keeps the most recent records, and only those.
///
/// Bounded on purpose. An unbounded in-process buffer is a memory leak with a
/// respectable name: the longer a server stays up -- which is to say, the
/// healthier it is -- the closer it gets to being killed by the diagnostics
/// that were supposed to explain why it died.
class DVMemoryLogSink implements DVLogSink {
  DVMemoryLogSink({this.capacity = 500})
      : assert(capacity > 0, 'a buffer that holds nothing records nothing');

  final int capacity;
  final List<DVLogRecord> _records = <DVLogRecord>[];

  /// Oldest first.
  List<DVLogRecord> get records => List<DVLogRecord>.unmodifiable(_records);

  @override
  void write(DVLogRecord record) {
    _records.add(record);
    if (_records.length > capacity) {
      _records.removeRange(0, _records.length - capacity);
    }
  }

  void clear() => _records.clear();
}

/// Writes one JSON object per line wherever [_write] points.
///
/// Takes a function rather than a stream so this file needs no `dart:io`: the
/// server passes `stdout.writeln`, a test passes a list's `add`.
class DVJsonLinesSink implements DVLogSink {
  const DVJsonLinesSink(this._write);

  final void Function(String line) _write;

  @override
  void write(DVLogRecord record) => _write(record.toJsonLine());
}

/// Sends every record on to each of [sinks], and keeps going when one throws.
class DVFanoutLogSink implements DVLogSink {
  DVFanoutLogSink(this.sinks);

  final List<DVLogSink> sinks;

  @override
  void write(DVLogRecord record) {
    for (final DVLogSink sink in sinks) {
      try {
        sink.write(record);
      } on Object {
        // Swallowed deliberately, and this is the one place it is right to.
        // A sink that throws -- a full disk, a closed pipe -- must not take
        // out the request that logged, and must not stop the other sinks
        // from getting the record either.
      }
    }
  }
}

/// Every `@DVModel.sensitiveField()` name in the application, registered by
/// the generated `registerDartvelModels()` on the client and the server.
///
/// Added to rather than replaced, because a module's generated client
/// registers its own models in the same process.
void dvRegisterSensitiveLogFields(Iterable<String> names) =>
    DVLogger._sensitiveFields.addAll(<String>[
      for (final String name in names) name.toLowerCase(),
    ]);

/// The thing application code calls.
class DVLogger {
  DVLogger({
    this.minimumLevel = DVLogLevel.info,
    List<DVLogSink>? sinks,
    Set<String>? redactedKeys,
  })  : sinks = sinks ?? <DVLogSink>[],
        redactedKeys = redactedKeys ?? defaultRedactedKeys;

  /// Records below this are dropped.
  DVLogLevel minimumLevel;

  final List<DVLogSink> sinks;

  /// Context keys whose values never reach a sink.
  ///
  /// Matched as substrings of the lowercased key, which over-redacts a little
  /// -- `tokenCount` goes too. That is the right way to be wrong: a redacted
  /// number is an inconvenience, and a bearer token sitting in a log store
  /// that half the company can read is an incident.
  Set<String> redactedKeys;

  static const Set<String> defaultRedactedKeys = <String>{
    'password',
    'passwd',
    'secret',
    'token',
    'authorization',
    'apikey',
    'api_key',
    'cookie',
    'session',
    'creditcard',
    'credit_card',
    'cvv',
    'ssn',
  };

  /// The application's sensitive model field names, lowercased.
  ///
  /// Matched exactly, where [redactedKeys] is matched as substrings: a model
  /// field named `number` is not every key containing `number`. Shared by
  /// every logger in the process, because the declaration is the
  /// application's and not one logger's.
  static final Set<String> _sensitiveFields = <String>{};

  /// The sensitive field names registered so far.
  static Set<String> get sensitiveFields =>
      Set<String>.unmodifiable(_sensitiveFields);

  /// Forgets every registered sensitive field. For tests.
  static void resetSensitiveFields() => _sensitiveFields.clear();

  /// What a redacted value is replaced with. Present rather than removed, so
  /// a reader can tell the difference between a secret that was there and a
  /// field that was never set.
  ///
  /// The same marker [dvRedactSecrets] uses, deliberately: two spellings
  /// would mean an operator searching their log store for redactions finds
  /// only half of them.
  static const String redactedValue = dvRedactedMarker;

  /// Credentials recognisable by their shape, redacted from every string.
  ///
  /// [dvRedactSecrets] knows the values `DV.Secrets` handed out, which on a
  /// server is most of them. A device has none of those: its credentials are
  /// a session token, a bearer header quoted back by an error and a URL with
  /// a password in it, and those are caught by what they look like. The
  /// group each pattern keeps is the part that is not the credential, so a
  /// line still says which host refused the connection.
  static final List<(RegExp, String Function(Match))> _credentialShapes =
      <(RegExp, String Function(Match))>[
    // A JSON Web Token: three base64url parts, the first two starting with
    // the encoding of `{"`.
    (
      RegExp(r'eyJ[A-Za-z0-9_-]{2,}\.eyJ[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]+'),
      (Match match) => redactedValue,
    ),
    // `Bearer <token>` / `Basic <credentials>`, wherever it was quoted.
    (
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}',
          caseSensitive: false),
      (Match match) => '${match[1]} $redactedValue',
    ),
    // The password in `scheme://user:password@host`.
    (
      RegExp(r'(://[^/\s:@]+:)[^/\s@]+@'),
      (Match match) => '${match[1]}$redactedValue@',
    ),
  ];

  /// Called for every record, whether or not it passes [minimumLevel].
  ///
  /// This is how the logs counter stays honest: counting only what a sink
  /// accepted would make an error rate move when somebody changes the log
  /// level, and an alert that fires on a configuration change is an alert
  /// people learn to ignore.
  void Function(DVLogRecord record)? onRecord;

  void log(
    String message, {
    DVLogLevel level = DVLogLevel.info,
    String? tag,
    Map<String, Object?> context = const <String, Object?>{},
    String? event,
    String? code,
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
    String? spanId,
    DateTime? time,
  }) {
    final DVSpan? span = dvCurrentSpan;
    final DVLogRecord record = DVLogRecord(
      level: level,
      // Redacted before anything else touches it. The key-name list below
      // guesses where a secret might be; this matches the values DV.Secrets
      // actually handed out, which is what catches a credential inside a
      // connection string, quoted back by an upstream error, or typed into a
      // sentence by hand during an incident.
      message: _redactText(message),
      tag: tag,
      time: time,
      context: _sanitise(context),
      event: event,
      code: code,
      error: error == null ? null : _redactText(error.toString()),
      stackTrace:
          stackTrace == null ? null : _redactText(stackTrace.toString()),
      // An explicit id wins: a job replaying work on behalf of a request
      // knows the trace it belongs to, and the ambient span would put it
      // under the worker's own trace instead.
      traceId: traceId ?? span?.traceId,
      spanId: spanId ?? span?.spanId,
    );

    onRecord?.call(record);
    if (!level.atLeast(minimumLevel)) return;
    for (final DVLogSink sink in sinks) {
      sink.write(record);
    }
  }

  void trace(String message,
          {String? tag, Map<String, Object?> context = const {}}) =>
      log(message, level: DVLogLevel.trace, tag: tag, context: context);

  void debug(String message,
          {String? tag, Map<String, Object?> context = const {}}) =>
      log(message, level: DVLogLevel.debug, tag: tag, context: context);

  void info(
    String message, {
    String? tag,
    Map<String, Object?> context = const <String, Object?>{},
    String? traceId,
    String? spanId,
  }) =>
      log(message,
          tag: tag, context: context, traceId: traceId, spanId: spanId);

  void warn(String message,
          {String? tag, Map<String, Object?> context = const {}}) =>
      log(message, level: DVLogLevel.warn, tag: tag, context: context);

  void error(
    String message, {
    String? tag,
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
    String? code,
  }) =>
      log(
        message,
        level: DVLogLevel.error,
        tag: tag,
        context: context,
        error: error,
        stackTrace: stackTrace,
        code: code,
      );

  String _redactText(String text) {
    String redacted = dvRedactSecrets(text);
    for (final (RegExp shape, String Function(Match) replace)
        in _credentialShapes) {
      redacted = redacted.replaceAllMapped(shape, replace);
    }
    return redacted;
  }

  /// Redacted, and reduced to values `jsonEncode` can actually render.
  ///
  /// A `DateTime` or a model object in a context map throws inside the
  /// encoder, and the throw surfaces at the sink -- which is to say the log
  /// call that was meant to explain a failure becomes a second failure, on a
  /// line nobody was looking at.
  Map<String, Object?> _sanitise(Map<String, Object?> context) {
    if (context.isEmpty) return const <String, Object?>{};
    final Map<String, Object?> out = <String, Object?>{};
    context.forEach((String key, Object? value) {
      out[key] = _isRedacted(key) ? redactedValue : _encodable(value, 0);
    });
    return out;
  }

  bool _isRedacted(String key) {
    final String lower = key.toLowerCase();
    if (_sensitiveFields.contains(lower)) return true;
    for (final String needle in redactedKeys) {
      if (lower.contains(needle)) return true;
    }
    return false;
  }

  /// How deep a context value is followed. A model whose public form refers
  /// back to itself would otherwise recurse until the stack runs out, in the
  /// middle of reporting something else.
  static const int _maxDepth = 8;

  Object? _encodable(Object? value, int depth) {
    if (value == null || value is num || value is bool) return value;
    if (depth > _maxDepth) return '…';
    // Every string on the way to a sink passes the resolved secret values,
    // however deep in the context map it sits. A password inside a URL under
    // the key `url` is the case the key-name list will never catch.
    if (value is String) return _redactText(value);
    if (value is Iterable) {
      return value
          .map((Object? item) => _encodable(item, depth + 1))
          .toList(growable: false);
    }
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _isRedacted('${entry.key}')
              ? redactedValue
              : _encodable(entry.value, depth + 1),
      };
    }
    // A generated data model is written as its public form, which leaves out
    // its sensitive fields by construction. Its toString does not.
    final Object? public = _publicForm(value);
    if (public != null) return _encodable(public, depth + 1);
    return _redactText(value.toString());
  }

  static Object? _publicForm(Object value) {
    try {
      final Object? public = (value as dynamic).toPublicJson();
      return public is Map ? public : null;
    } on NoSuchMethodError {
      return null;
    }
  }
}
