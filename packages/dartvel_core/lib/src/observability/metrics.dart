/// Metrics, in the format a scraper actually reads.
///
/// Dartvel documented a Prometheus endpoint and had no metrics at all. This is
/// the registry behind it: counters, gauges and histograms, rendered in the
/// Prometheus text exposition format.
///
/// Small on purpose. The exposition format has a handful of rules that are
/// easy to get subtly wrong -- a repeated TYPE line, a non-cumulative
/// histogram bucket, an unescaped label value -- and each of them produces
/// output that looks right and either fails the whole scrape or computes every
/// quantile wrong.
library dartvel.observability.metrics;

/// Every series Dartvel exports carries this prefix, so an application's own
/// metrics and the framework's never collide in one registry.
const String dvMetricPrefix = 'dartvel_';

enum _DVMetricKind { counter, gauge, histogram }

/// A monotonically increasing count.
class DVCounter {
  DVCounter._(this._series);
  final _DVSeries _series;

  double get value => _series.value;

  /// Adds [amount], which must not be negative.
  ///
  /// Prometheus computes rates from the assumption that a counter only rises;
  /// a counter that falls reads as a process restart and the rate spikes.
  void increment([double amount = 1]) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'a counter cannot decrease',
      );
    }
    _series.value += amount;
  }
}

/// A value that goes up and down.
class DVGauge {
  DVGauge._(this._series);
  final _DVSeries _series;

  double get value => _series.value;

  void set(double value) => _series.value = value;
  void increment([double amount = 1]) => _series.value += amount;
  void decrement([double amount = 1]) => _series.value -= amount;
}

/// A distribution, bucketed.
class DVHistogram {
  DVHistogram._(this._series);
  final _DVSeries _series;

  /// The default ladder, in seconds, which is what request durations are
  /// measured in. Chosen to straddle the range a web request actually spans:
  /// a millisecond to ten seconds.
  static const List<double> defaultBuckets = <double>[
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10,
  ];

  void observe(double value) {
    final List<double> counts = _series.buckets!;
    for (int i = 0; i < defaultBuckets.length; i += 1) {
      // Cumulative: le="0.5" means "at most 0.5", which includes everything
      // in the smaller buckets. Incrementing only the bucket a value lands in
      // renders a histogram that looks plausible and computes every quantile
      // wrong.
      if (value <= defaultBuckets[i]) counts[i] += 1;
    }
    _series.value += value;
    _series.count += 1;
  }
}

class _DVSeries {
  _DVSeries(this.kind, this.labels)
      : buckets = kind == _DVMetricKind.histogram
            ? List<double>.filled(DVHistogram.defaultBuckets.length, 0)
            : null;

  final _DVMetricKind kind;
  final Map<String, String> labels;
  double value = 0;
  double count = 0;
  final List<double>? buckets;
}

/// A registry of metrics, rendered on demand.
class DVMetrics {
  final Map<String, _DVMetricKind> _kinds = <String, _DVMetricKind>{};
  final Map<String, String> _help = <String, String>{};
  final Map<String, Map<String, _DVSeries>> _series =
      <String, Map<String, _DVSeries>>{};

  DVCounter counter(
    String name, [
    Map<String, String> labels = const <String, String>{},
    String? help,
  ]) =>
      DVCounter._(_seriesFor(name, _DVMetricKind.counter, labels, help));

  DVGauge gauge(
    String name, [
    Map<String, String> labels = const <String, String>{},
    String? help,
  ]) =>
      DVGauge._(_seriesFor(name, _DVMetricKind.gauge, labels, help));

  DVHistogram histogram(
    String name, [
    Map<String, String> labels = const <String, String>{},
    String? help,
  ]) =>
      DVHistogram._(_seriesFor(name, _DVMetricKind.histogram, labels, help));

  /// Forgets everything. For tests, which must not see each other's counts.
  void reset() {
    _kinds.clear();
    _help.clear();
    _series.clear();
  }

  _DVSeries _seriesFor(
    String name,
    _DVMetricKind kind,
    Map<String, String> labels,
    String? help,
  ) {
    final _DVMetricKind? existing = _kinds[name];
    if (existing != null && existing != kind) {
      // Two kinds under one name renders two TYPE lines for it, which is a
      // parse error that takes out the whole scrape rather than one metric.
      throw StateError(
        'Metric "$name" is already registered as a ${existing.name} and '
        'cannot also be a ${kind.name}.',
      );
    }
    _kinds[name] = kind;
    if (help != null) _help[name] = help;

    final Map<String, _DVSeries> byLabels =
        _series.putIfAbsent(name, () => <String, _DVSeries>{});
    return byLabels.putIfAbsent(
      _key(labels),
      () => _DVSeries(kind, Map<String, String>.unmodifiable(labels)),
    );
  }

  /// Labels in a stable order, so `{a:1,b:2}` and `{b:2,a:1}` are one series
  /// rather than two that never add up.
  static String _key(Map<String, String> labels) {
    if (labels.isEmpty) return '';
    final List<String> keys = labels.keys.toList()..sort();
    return keys.map((String k) => '$k=${labels[k]}').join(',');
  }

  /// The registry in Prometheus text exposition format.
  String render() {
    final StringBuffer out = StringBuffer();
    final List<String> names = _series.keys.toList()..sort();

    for (final String name in names) {
      final Map<String, _DVSeries> byLabels = _series[name]!;
      if (byLabels.isEmpty) continue;
      final String full = '$dvMetricPrefix$name';
      final _DVMetricKind kind = _kinds[name]!;

      // Once per name, however many label series it has: a repeated HELP or
      // TYPE is a parse error.
      final String? help = _help[name];
      if (help != null) out.writeln('# HELP $full ${_escapeHelp(help)}');
      out.writeln('# TYPE $full ${kind.name}');

      final List<String> keys = byLabels.keys.toList()..sort();
      for (final String key in keys) {
        final _DVSeries series = byLabels[key]!;
        if (kind == _DVMetricKind.histogram) {
          double cumulative = 0;
          for (int i = 0; i < DVHistogram.defaultBuckets.length; i += 1) {
            cumulative = series.buckets![i];
            out.writeln('${full}_bucket'
                '${_labels(series.labels, le: _number(DVHistogram.defaultBuckets[i]))} '
                '${_number(cumulative)}');
          }
          out.writeln('${full}_bucket${_labels(series.labels, le: '+Inf')} '
              '${_number(series.count)}');
          out.writeln('${full}_sum${_labels(series.labels)} '
              '${_number(series.value)}');
          out.writeln('${full}_count${_labels(series.labels)} '
              '${_number(series.count)}');
        } else {
          out.writeln('$full${_labels(series.labels)} ${_number(series.value)}');
        }
      }
    }
    return out.toString();
  }

  static String _labels(Map<String, String> labels, {String? le}) {
    final List<String> parts = <String>[
      for (final String key in labels.keys.toList()..sort())
        '$key="${_escapeLabel(labels[key]!)}"',
      if (le != null) 'le="$le"',
    ];
    return parts.isEmpty ? '' : '{${parts.join(',')}}';
  }

  /// A label value carrying a quote, a backslash or a newline breaks the
  /// exposition format, and Prometheus rejects the whole scrape -- so one bad
  /// route name silently takes out every metric on the instance.
  static String _escapeLabel(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');

  static String _escapeHelp(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');

  /// Whole numbers without a trailing `.0`, and no exponent notation, which
  /// some scrapers reject.
  static String _number(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    // Trimmed, so a float sum does not render as 0.30300000000000005.
    String text = value.toStringAsFixed(6);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }
}
