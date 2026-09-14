/// What a crash report is: the frames, where they came from, and the
/// breadcrumbs that led there — with nothing sensitive in any of it.
library;

import 'dart:collection';
import 'dart:math';

import '../diagnostics/diagnostics.dart';
import '../observability/logging.dart';
import '../secrets/secrets.dart';

/// How a report came about.
enum DVCrashKind {
  /// The process was going down.
  fatal,

  /// A caught error the application asked to have recorded. The only kind
  /// that is sampled.
  nonFatal,

  /// The platform thread stopped answering for longer than the threshold.
  hang,
}

/// One frame of a stack.
class DVCrashFrame {
  /// The function, method or closure, as the runtime names it.
  final String function;

  /// The library the frame is in, or null when the line could not be read.
  final String? uri;
  final int? line;
  final int? column;

  const DVCrashFrame({
    required this.function,
    this.uri,
    this.line,
    this.column,
  });

  // `#3      CheckoutController.pay (package:shop/checkout/controller.dart:88:7)`
  // The URI is matched lazily with the line and column optional after it, so
  // the colon in `package:` is not taken for the start of a line number.
  static final RegExp _vmLine =
      RegExp(r'^#\d+\s+(.*?)\s+\((.*?)(?::(\d+))?(?::(\d+))?\)\s*$');

  /// The frames of [stack], in order, innermost first.
  ///
  /// Lines the runtime writes that are not frames — `<asynchronous
  /// suspension>` — are skipped. A line that looks like a frame but cannot be
  /// read is kept with its text as the function, so a stack in a format this
  /// does not know still says something rather than nothing.
  static List<DVCrashFrame> parse(Object stack) {
    final List<DVCrashFrame> frames = <DVCrashFrame>[];
    for (final String raw in '$stack'.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty || line.startsWith('<')) continue;
      final RegExpMatch? match = _vmLine.firstMatch(line);
      if (match == null) {
        frames.add(DVCrashFrame(function: line));
        continue;
      }
      frames.add(DVCrashFrame(
        function: match.group(1)!,
        uri: match.group(2),
        line: int.tryParse(match.group(3) ?? ''),
        column: int.tryParse(match.group(4) ?? ''),
      ));
    }
    return frames;
  }

  /// Libraries whose frames are the framework's rather than the
  /// application's: they are on almost every stack, so a group named after
  /// them names nothing.
  static const List<String> frameworkPrefixes = <String>[
    'dart:',
    'package:flutter/',
    'package:flutter_test/',
    'package:dartvel_core/',
    'package:dartvel_flutter/',
    'package:dartvel_shelf/',
    'package:stack_trace/',
    'package:test_api/',
    'package:matcher/',
  ];

  /// Whether this frame is in the framework rather than the application.
  bool get isFramework {
    final String? library = uri;
    if (library == null) return false;
    for (final String prefix in frameworkPrefixes) {
      if (library.startsWith(prefix)) return true;
    }
    return false;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'function': function,
        if (uri != null) 'uri': uri,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
      };

  static DVCrashFrame fromJson(Map<String, Object?> json) => DVCrashFrame(
        function: json['function']! as String,
        uri: json['uri'] as String?,
        line: json['line'] as int?,
        column: json['column'] as int?,
      );
}

/// Where a crash's group comes from.
abstract final class DVCrashFingerprint {
  /// How many application frames name a group.
  static const int frames = 5;

  /// The frames that are the application's own. When none are — a crash
  /// entirely inside the framework — every frame is.
  static List<DVCrashFrame> applicationFrames(List<DVCrashFrame> stack) {
    final List<DVCrashFrame> own = <DVCrashFrame>[
      for (final DVCrashFrame frame in stack)
        if (!frame.isFramework) frame,
    ];
    return own.isEmpty ? stack : own;
  }

  /// The group a crash of [errorType] at [frames] belongs to.
  ///
  /// Taken from the type and the top application frames — library and
  /// function — and deliberately not from the message or the line. A message
  /// carries ids and values, so grouping on it splits one bug into as many
  /// groups as there were orders; and it is often the same text for unrelated
  /// failures, so it merges bugs too. A line moves every release, and a group
  /// has to survive a release to say "this regressed in 1.4.0".
  ///
  /// [override] replaces the default where it is wrong: one crash site reached
  /// from twenty callers, or twenty sites behind one shared helper.
  static String of({
    required String errorType,
    required List<DVCrashFrame> frames,
    String? override,
  }) {
    if (override != null) return _hash('override\n$override');
    final Iterable<DVCrashFrame> top =
        applicationFrames(frames).take(DVCrashFingerprint.frames);
    return _hash(<String>[
      errorType,
      for (final DVCrashFrame frame in top) '${frame.uri ?? ''}#${frame.function}',
    ].join('\n'));
  }

  /// Two FNV-1a passes with different offsets: stable across Dart versions,
  /// which a group id has to be, and wide enough not to merge groups.
  static String _hash(String text) {
    int a = 0x811c9dc5;
    int b = 0x01234567;
    for (final int unit in text.codeUnits) {
      a = ((a ^ (unit & 0xff)) * 0x01000193) & 0xffffffff;
      a = ((a ^ (unit >> 8)) * 0x01000193) & 0xffffffff;
      b = ((b ^ (unit & 0xff)) * 0x01000193) & 0xffffffff;
      b = ((b ^ (unit >> 8)) * 0x01000193) & 0xffffffff;
    }
    return a.toRadixString(16).padLeft(8, '0') +
        b.toRadixString(16).padLeft(8, '0');
  }
}

/// Something that happened before a crash.
class DVCrashBreadcrumb {
  final DateTime time;

  /// `navigation`, `backend`, `lifecycle`, `log`.
  final String category;
  final String message;
  final Map<String, Object?> data;

  const DVCrashBreadcrumb({
    required this.time,
    required this.category,
    required this.message,
    this.data = const <String, Object?>{},
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'time': time.toUtc().toIso8601String(),
        'category': category,
        'message': message,
        if (data.isNotEmpty) 'data': data,
      };

  static DVCrashBreadcrumb fromJson(Map<String, Object?> json) =>
      DVCrashBreadcrumb(
        time: DateTime.parse(json['time']! as String),
        category: json['category']! as String,
        message: json['message']! as String,
        data: (json['data'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
}

/// The last [capacity] breadcrumbs, redacted on the way in.
///
/// A ring buffer with a declared size, so a long session costs what a short
/// one does. Redaction happens when a breadcrumb is added rather than when a
/// report is written: the report is written by a handler in a process that is
/// going down, which is no place to be walking maps.
class DVCrashBreadcrumbs {
  DVCrashBreadcrumbs({
    this.capacity = 64,
    Set<String> sensitive = const <String>{},
    DateTime Function()? clock,
  })  : _sensitive = <String>{
          for (final String name in sensitive) name.toLowerCase(),
        },
        _clock = clock ?? DateTime.now;

  /// How many breadcrumbs are kept.
  final int capacity;

  /// Field names declared sensitive, lowercased. Matched exactly, where the
  /// logger's own list is matched as substrings — a model field named
  /// `number` is not every key that contains `number`.
  final Set<String> _sensitive;
  final DateTime Function() _clock;
  final ListQueue<DVCrashBreadcrumb> _buffer = ListQueue<DVCrashBreadcrumb>();

  void add(
    String category,
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (capacity <= 0) return;
    if (_buffer.length >= capacity) _buffer.removeFirst();
    _buffer.add(DVCrashBreadcrumb(
      time: _clock(),
      category: category,
      message: dvRedactSecrets(message),
      data: redactMap(data),
    ));
  }

  /// The breadcrumbs, oldest first.
  List<DVCrashBreadcrumb> get snapshot =>
      List<DVCrashBreadcrumb>.unmodifiable(_buffer);

  void clear() => _buffer.clear();

  /// [data] with every sensitive value replaced by the logger's marker, at
  /// any depth, and reduced to what JSON can carry.
  ///
  /// Two tests: a key the logger redacts (`token`, `password`, ...) as a
  /// substring, and a field declared sensitive as an exact name. Strings pass
  /// the resolved-secret redaction too, which catches a password inside a URL
  /// under a key nobody thought to list.
  Map<String, Object?> redactMap(Map<String, Object?> data) {
    if (data.isEmpty) return const <String, Object?>{};
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in data.entries)
        entry.key: _isSensitive(entry.key)
            ? DVLogger.redactedValue
            : _encodable(entry.value),
    };
  }

  bool _isSensitive(String key) {
    final String lower = key.toLowerCase();
    if (_sensitive.contains(lower)) return true;
    for (final String needle in DVLogger.defaultRedactedKeys) {
      if (lower.contains(needle)) return true;
    }
    return false;
  }

  Object? _encodable(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return dvRedactSecrets(value);
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _isSensitive('${entry.key}')
              ? DVLogger.redactedValue
              : _encodable(entry.value),
      };
    }
    if (value is Iterable) {
      return <Object?>[for (final Object? item in value) _encodable(item)];
    }
    return dvRedactSecrets('$value');
  }
}

/// Where and in what a crash happened.
class DVCrashContext {
  /// The release the binary came from.
  final String release;

  /// The OTA patch applied over it, if any.
  final String? patch;
  final String? protocolVersion;
  final String? platform;

  /// `phone`, `tablet`, `desktop`, `tv`, `kiosk`.
  final String? deviceClass;
  final String? locale;

  /// An install-scoped random id — not a user and not an advertising id. It
  /// groups one device's reports and is gone when the application is
  /// reinstalled or its data is cleared.
  final String installId;

  /// The rollout cohort the device is in, so release health can be read per
  /// cohort.
  final String? cohort;

  const DVCrashContext({
    required this.release,
    required this.installId,
    this.patch,
    this.protocolVersion,
    this.platform,
    this.deviceClass,
    this.locale,
    this.cohort,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'release': release,
        'installId': installId,
        if (patch != null) 'patch': patch,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
        if (platform != null) 'platform': platform,
        if (deviceClass != null) 'deviceClass': deviceClass,
        if (locale != null) 'locale': locale,
        if (cohort != null) 'cohort': cohort,
      };

  static DVCrashContext fromJson(Map<String, Object?> json) => DVCrashContext(
        release: json['release']! as String,
        installId: json['installId']! as String,
        patch: json['patch'] as String?,
        protocolVersion: json['protocolVersion'] as String?,
        platform: json['platform'] as String?,
        deviceClass: json['deviceClass'] as String?,
        locale: json['locale'] as String?,
        cohort: json['cohort'] as String?,
      );
}

/// A crash, as written to disk by the handler and sent by the next launch.
class DVCrashReport {
  /// The on-disk format. A record in another format is not guessed at.
  static const int format = 1;

  final String id;
  final DVCrashKind kind;
  final String errorType;

  /// The error's text, with resolved secret values redacted.
  final String message;
  final List<DVCrashFrame> frames;
  final String fingerprint;
  final DVCrashContext context;
  final DateTime occurredAt;

  /// How long the session had been running, when a session was started.
  final Duration? sessionLength;

  /// The flags in force when it happened.
  final Map<String, Object?> flags;
  final List<DVCrashBreadcrumb> breadcrumbs;

  /// Whether the release's symbols were in the symbol store when the report
  /// was sent, or null when no symbol store is configured and nobody knows.
  /// A report with false says so rather than showing a frame list that is the
  /// compiler's naming.
  final bool? symbolicated;

  const DVCrashReport({
    required this.id,
    required this.kind,
    required this.errorType,
    required this.message,
    required this.frames,
    required this.fingerprint,
    required this.context,
    required this.occurredAt,
    this.sessionLength,
    this.flags = const <String, Object?>{},
    this.breadcrumbs = const <DVCrashBreadcrumb>[],
    this.symbolicated,
  });

  DVCrashReport copyWith({bool? symbolicated}) => DVCrashReport(
        id: id,
        kind: kind,
        errorType: errorType,
        message: message,
        frames: frames,
        fingerprint: fingerprint,
        context: context,
        occurredAt: occurredAt,
        sessionLength: sessionLength,
        flags: flags,
        breadcrumbs: breadcrumbs,
        symbolicated: symbolicated ?? this.symbolicated,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'v': format,
        'id': id,
        'kind': kind.name,
        'errorType': errorType,
        'message': message,
        'frames': <Object?>[for (final DVCrashFrame f in frames) f.toJson()],
        'fingerprint': fingerprint,
        'context': context.toJson(),
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (sessionLength != null)
          'sessionLengthMs': sessionLength!.inMilliseconds,
        if (flags.isNotEmpty) 'flags': flags,
        'breadcrumbs': <Object?>[
          for (final DVCrashBreadcrumb b in breadcrumbs) b.toJson(),
        ],
        if (symbolicated != null) 'symbolicated': symbolicated,
      };

  /// Reads a report, throwing [FormatException] on anything that is not a
  /// whole one — which is what a record cut short by the crash writing it
  /// looks like.
  static DVCrashReport fromJson(Map<String, Object?> json) {
    try {
      if (json['v'] != format) {
        throw FormatException('crash record format ${json['v']}');
      }
      return DVCrashReport(
        id: json['id']! as String,
        kind: DVCrashKind.values.byName(json['kind']! as String),
        errorType: json['errorType']! as String,
        message: json['message']! as String,
        frames: <DVCrashFrame>[
          for (final Object? f in json['frames']! as List<Object?>)
            DVCrashFrame.fromJson(f! as Map<String, Object?>),
        ],
        fingerprint: json['fingerprint']! as String,
        context:
            DVCrashContext.fromJson(json['context']! as Map<String, Object?>),
        occurredAt: DateTime.parse(json['occurredAt']! as String),
        sessionLength: json['sessionLengthMs'] == null
            ? null
            : Duration(milliseconds: json['sessionLengthMs']! as int),
        flags: (json['flags'] as Map<String, Object?>?) ??
            const <String, Object?>{},
        breadcrumbs: <DVCrashBreadcrumb>[
          for (final Object? b in json['breadcrumbs']! as List<Object?>)
            DVCrashBreadcrumb.fromJson(b! as Map<String, Object?>),
        ],
        symbolicated: json['symbolicated'] as bool?,
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('not a whole crash record: $error');
    }
  }
}

final Random _ids = Random();
int _idCounter = 0;

/// A report id: unique on the device without asking anything that can fail.
String dvCrashReportId(DateTime at) =>
    '${at.microsecondsSinceEpoch.toRadixString(16)}-'
    '${(_idCounter++).toRadixString(16)}-'
    '${_ids.nextInt(1 << 32).toRadixString(16)}';

final DVLogger _crashLogger = DVLogger();

/// Logs a `DV-CRASH` diagnostic at the level the registry gives it.
void dvLogCrashDiagnostic(String code, String message) {
  final String level = DVDiagnostics.all
          .where((DVDiagnostic d) => d.code == code)
          .firstOrNull
          ?.level ??
      'warning';
  _crashLogger.log(
    '$code: $message',
    level: switch (level) {
      'debug' => DVLogLevel.debug,
      'info' => DVLogLevel.info,
      'error' => DVLogLevel.error,
      _ => DVLogLevel.warn,
    },
    context: <String, Object?>{'code': code},
  );
}
