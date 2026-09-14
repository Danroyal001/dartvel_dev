/// The signals an alert rule reads.
///
/// There is no separate alerting agent and no second definition of what
/// "slow" means: every signal here is one another section already produces --
/// the metrics registry, the spans the tracer recorded, release health, a
/// service level's burn rate -- or one the application registers a reader for
/// because only it can measure it (queue depth on a broker, a kiosk fleet, a
/// quota breach count).
library;

import '../crashes/release_health.dart';
import '../observability/observability.dart';
import 'service_levels.dart';

/// Which figure of a trace's latency distribution a rule reads.
enum DVTraceStat { p50, p95, p99, max }

enum DVSignalKind {
  metric,
  trace,
  crashRate,
  queueDepth,
  kioskFleetHealth,
  quotaBreaches,
  errorBudgetBurn,
}

/// A reference to a measured signal.
class DVSignalRef {
  /// A counter or gauge in the metrics registry, without the `dartvel_`
  /// prefix the exposition adds.
  const DVSignalRef.metric(this.name,
      {this.labels = const <String, String>{}})
      : kind = DVSignalKind.metric,
        stat = null,
        window = null,
        shortWindow = null;

  /// A latency figure over spans named [name] that started in the trailing
  /// [window].
  const DVSignalRef.trace(this.name, DVTraceStat this.stat,
      {Duration this.window = const Duration(minutes: 5)})
      : kind = DVSignalKind.trace,
        labels = const <String, String>{},
        shortWindow = null;

  /// Crashed sessions over sessions started, for release [name].
  const DVSignalRef.crashRate(this.name)
      : kind = DVSignalKind.crashRate,
        labels = const <String, String>{},
        stat = null,
        window = null,
        shortWindow = null;

  /// Jobs waiting on queue [name]. Read through a registered reader.
  const DVSignalRef.queueDepth(this.name)
      : kind = DVSignalKind.queueDepth,
        labels = const <String, String>{},
        stat = null,
        window = null,
        shortWindow = null;

  /// The share of kiosk fleet [name] that is healthy. Read through a
  /// registered reader.
  const DVSignalRef.kioskFleetHealth(this.name)
      : kind = DVSignalKind.kioskFleetHealth,
        labels = const <String, String>{},
        stat = null,
        window = null,
        shortWindow = null;

  /// Quota breaches on meter [name]. Read through a registered reader.
  const DVSignalRef.quotaBreaches(this.name)
      : kind = DVSignalKind.quotaBreaches,
        labels = const <String, String>{},
        stat = null,
        window = null,
        shortWindow = null;

  /// Service level [name]'s burn rate, as the lower of its burn over [window]
  /// and over [shortWindow].
  ///
  /// The lower of the two, so a threshold is crossed only while both windows
  /// burn: the long one says the month is in danger, the short one says it is
  /// still happening. An alert on the long window alone keeps paging for an
  /// hour after the outage ended.
  const DVSignalRef.errorBudgetBurn(this.name,
      {Duration this.window = const Duration(hours: 1),
      Duration this.shortWindow = const Duration(minutes: 5)})
      : kind = DVSignalKind.errorBudgetBurn,
        labels = const <String, String>{},
        stat = null;

  final DVSignalKind kind;
  final String name;
  final Map<String, String> labels;
  final DVTraceStat? stat;
  final Duration? window;
  final Duration? shortWindow;

  /// [value] as a person reads this signal: a burn rate as `6.7×`, a latency
  /// in milliseconds, a crash rate or fleet health as a percentage, a count or
  /// a metric with no more decimals than it needs.
  ///
  /// Text only. What an alert writes into a timeline, a page and a
  /// notification is read by a person; a reading's number is untouched.
  String format(Object value) {
    if (value is Duration) {
      return '${_decimals(value.inMicroseconds / 1000, 1)}ms';
    }
    if (value is! num) return '$value';
    return switch (kind) {
      DVSignalKind.errorBudgetBurn =>
        '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}×',
      DVSignalKind.trace => '${_decimals(value, 1)}ms',
      DVSignalKind.crashRate ||
      DVSignalKind.kioskFleetHealth =>
        '${_decimals(value * 100, 2)}%',
      _ => _decimals(value, 2),
    };
  }

  /// At most [digits] decimals, without trailing zeros -- except that a value
  /// that is not zero is never written as `0`.
  static String _decimals(num value, int digits) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.round().toString();
    }
    String text = value.toStringAsFixed(digits);
    if (double.parse(text) == 0) text = value.toStringAsPrecision(3);
    if (text.contains('.') && !text.contains('e')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }
    return text;
  }

  /// Whether readings are durations rather than numbers.
  bool get measuresDuration => kind == DVSignalKind.trace;

  String get _key {
    final List<String> keys = labels.keys.toList()..sort();
    return '${kind.name}:$name{${keys.map((String k) => '$k=${labels[k]}').join(',')}}';
  }

  @override
  String toString() => switch (kind) {
        DVSignalKind.trace => '${stat!.name} of $name',
        DVSignalKind.metric when labels.isNotEmpty => '$name$labels',
        _ => '${kind.name} $name',
      };
}

enum DVSignalReadingStatus {
  /// A value was read.
  value,

  /// The signal exists and has nothing to say: no spans in the window, no
  /// sessions, no series for these labels yet.
  noData,

  /// Nothing by that name exists to read.
  missing,
}

/// One read of a signal.
class DVSignalReading {
  const DVSignalReading._(this.status, this.value, this.duration, this.detail);

  factory DVSignalReading.number(num value) =>
      DVSignalReading._(DVSignalReadingStatus.value, value, null, null);

  factory DVSignalReading.ofDuration(Duration value) => DVSignalReading._(
      DVSignalReadingStatus.value, value.inMicroseconds / 1000, value, null);

  factory DVSignalReading.noData([String? detail]) =>
      DVSignalReading._(DVSignalReadingStatus.noData, null, null, detail);

  factory DVSignalReading.missing(String detail) =>
      DVSignalReading._(DVSignalReadingStatus.missing, null, null, detail);

  final DVSignalReadingStatus status;

  /// The number read; milliseconds for a duration.
  final num? value;

  /// The duration read, for a trace signal.
  final Duration? duration;

  /// Why there is no value.
  final String? detail;
}

/// A finished span, as a latency signal reads it.
class DVSpanSample {
  const DVSpanSample({
    required this.name,
    required this.startedAt,
    required this.duration,
    this.error = false,
  });

  final String name;
  final DateTime startedAt;
  final Duration duration;
  final bool error;
}

/// Reads the current value of an application-measured signal; null is no
/// data.
typedef DVSignalReader = num? Function();

/// Resolves a [DVSignalRef] to a reading.
class DVSignalReaders {
  DVSignalReaders({
    DVMetrics? metrics,
    Iterable<DVSpanSample> Function()? spans,
    this.releaseHealth,
    this.serviceLevels,
  })  : metrics = metrics ?? DVObservability.metrics,
        _spans = spans ?? _recordedSpans;

  final DVMetrics metrics;
  final DVReleaseHealth? releaseHealth;
  final DVServiceLevels? serviceLevels;
  final Iterable<DVSpanSample> Function() _spans;
  final Map<String, DVSignalReader> _registered = <String, DVSignalReader>{};

  static Iterable<DVSpanSample> _recordedSpans() sync* {
    for (final DVSpan span in DVObservability.recentSpans) {
      final Duration? duration = span.duration;
      if (duration == null) continue;
      yield DVSpanSample(
        name: span.name,
        startedAt: span.startedAt,
        duration: duration,
        error: span.status == DVSpanStatus.error,
      );
    }
  }

  /// Reads [ref] through [reader], ahead of any built-in source.
  void register(DVSignalRef ref, DVSignalReader reader) {
    _registered[ref._key] = reader;
  }

  /// After this, a rule naming [ref] reads it as missing.
  void unregister(DVSignalRef ref) => _registered.remove(ref._key);

  DVSignalReading read(DVSignalRef ref, {required DateTime now}) {
    final DVSignalReader? registered = _registered[ref._key];
    if (registered != null) {
      final num? value = registered();
      return value == null
          ? DVSignalReading.noData()
          : DVSignalReading.number(value);
    }

    switch (ref.kind) {
      case DVSignalKind.metric:
        final String? type = metrics.typeOf(ref.name);
        if (type == null) {
          return DVSignalReading.missing('no metric named ${ref.name}');
        }
        if (type == 'histogram') {
          return DVSignalReading.missing(
              '${ref.name} is a histogram and has no single value; read it '
              'as a trace statistic instead');
        }
        final double? value = metrics.valueOf(ref.name, ref.labels);
        return value == null
            ? DVSignalReading.noData('no series for ${ref.labels}')
            : DVSignalReading.number(value);

      case DVSignalKind.trace:
        return _trace(ref, now);

      case DVSignalKind.crashRate:
        final DVReleaseHealth? health = releaseHealth;
        if (health == null) {
          return DVSignalReading.missing('no release health is attached');
        }
        final double? crashFree =
            health.numbers(release: ref.name).crashFreeSessions;
        return crashFree == null
            ? DVSignalReading.noData('no sessions for ${ref.name}')
            : DVSignalReading.number(1 - crashFree);

      case DVSignalKind.errorBudgetBurn:
        final DVServiceLevels? levels = serviceLevels;
        if (levels == null || !levels.has(ref.name)) {
          return DVSignalReading.missing('no service level named ${ref.name}');
        }
        final double? long = levels.burnRate(ref.name, ref.window!, now: now);
        final double? short =
            levels.burnRate(ref.name, ref.shortWindow!, now: now);
        if (long == null || short == null) return DVSignalReading.noData();
        return DVSignalReading.number(long < short ? long : short);

      case DVSignalKind.queueDepth:
      case DVSignalKind.kioskFleetHealth:
      case DVSignalKind.quotaBreaches:
        return DVSignalReading.missing('no reader is registered for $ref');
    }
  }

  DVSignalReading _trace(DVSignalRef ref, DateTime now) {
    final DateTime from = now.subtract(ref.window!);
    final List<Duration> durations = <Duration>[
      for (final DVSpanSample span in _spans())
        if (span.name == ref.name &&
            !span.startedAt.isBefore(from) &&
            !span.startedAt.isAfter(now))
          span.duration,
    ];
    if (durations.isEmpty) {
      return DVSignalReading.noData(
          'no ${ref.name} spans in the last ${ref.window!.inSeconds}s');
    }
    // Spans are recorded in the order they finish, not by how long they took.
    durations.sort();
    final int percent = switch (ref.stat!) {
      DVTraceStat.p50 => 50,
      DVTraceStat.p95 => 95,
      DVTraceStat.p99 => 99,
      DVTraceStat.max => 100,
    };
    // Nearest rank, in integers: ceil(percent * n / 100). In doubles 0.95 * 20
    // is not quite 19, and whether its ceiling is 19 or 20 depends on rounding
    // -- one sample, which on a latency alert is fire or do not.
    final int rank = (percent * durations.length + 99) ~/ 100;
    return DVSignalReading.ofDuration(durations[(rank < 1 ? 1 : rank) - 1]);
  }
}
