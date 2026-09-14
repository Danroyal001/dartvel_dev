/// The deploy gate behind `dartvel compatibility-check --against production`:
/// the candidate build's window held against the clients actually calling.
library dartvel_core.protocol.compatibility_check;

import 'dart:convert';

import 'compatibility.dart';
import 'contract.dart';

/// Sessions monitoring saw from one protocol version on one day.
class DVProtocolSessionSample {
  const DVProtocolSessionSample({
    required this.protocol,
    required this.day,
    required this.sessions,
  });

  final int protocol;
  final DateTime day;
  final int sessions;
}

/// What the gate decided, and the evidence it decided on.
class DVCompatibilityVerdict {
  const DVCompatibilityVerdict._({
    required this.candidate,
    required this.served,
    required this.threshold,
    required this.histogram,
    required this.stranded,
    required this.allowed,
    required this.overridden,
    this.refusal,
    this.overrideReason,
  });

  /// The candidate build's protocol version.
  final int candidate;

  /// The versions the candidate's window serves.
  final Set<int> served;
  final double threshold;

  /// Sessions per protocol version over the last seven days.
  final Map<int, int> histogram;

  /// Share of sessions per version outside the window and above [threshold].
  final Map<int, double> stranded;

  final bool allowed;

  /// The deploy was refused and let through on an explicit reason.
  final bool overridden;

  /// Why the deploy is refused, whether or not it was then overridden.
  final String? refusal;
  final String? overrideReason;

  /// The record to log: an override is never a quiet one, so it carries the
  /// histogram it overrode.
  Map<String, Object?> toJson() => <String, Object?>{
    'candidate': candidate,
    'served': served.toList()..sort(),
    'threshold': threshold,
    'histogram': <String, int>{
      for (final MapEntry<int, int> e in histogram.entries) '${e.key}': e.value,
    },
    'stranded': <String, double>{
      for (final MapEntry<int, double> e in stranded.entries)
        '${e.key}': e.value,
    },
    'allowed': allowed,
    'overridden': overridden,
    if (refusal != null) 'refusal': refusal,
    if (overridden) 'override': overrideReason,
  };
}

/// The deploy gate.
abstract final class DVCompatibilityCheck {
  /// Refuses [candidate] when a protocol version outside its window accounts
  /// for more than `window.strandThreshold` of the sessions in [samples] over
  /// the seven days before [now].
  ///
  /// Refuses as well when there are no sessions in that span at all: an empty
  /// histogram is a monitoring feed that returned nothing, and reading it as
  /// a fleet with nobody stranded would pass exactly the deploy the gate is
  /// for. [overrideReason] lets a refused deploy through; a blank one is not
  /// a reason.
  static DVCompatibilityVerdict evaluate({
    required DVProtocolLock candidate,
    DVProtocolWindow window = const DVProtocolWindow(),
    required Iterable<DVProtocolSessionSample> samples,
    required DateTime now,
    String? overrideReason,
    void Function(String code, String message)? onDiagnostic,
  }) {
    final DVProtocolRelease? latest = candidate.current;
    if (latest == null) {
      throw StateError('the candidate has no protocol version recorded');
    }
    final void Function(String, String) diagnose =
        onDiagnostic ?? dvLogProtocolDiagnostic;
    final Set<int> served = window.served(candidate, now: now);
    final DateTime since = now.subtract(const Duration(days: 7));

    final Map<int, int> histogram = <int, int>{};
    for (final DVProtocolSessionSample sample in samples) {
      if (sample.sessions < 0) {
        throw ArgumentError.value(
          sample.sessions,
          'sessions',
          'protocol ${sample.protocol} has a negative session count',
        );
      }
      if (sample.day.isBefore(since) || sample.day.isAfter(now)) continue;
      histogram[sample.protocol] =
          (histogram[sample.protocol] ?? 0) + sample.sessions;
    }
    final int total = histogram.values.fold(0, (int a, int b) => a + b);

    final String? reason = overrideReason?.trim();
    final bool hasReason = reason != null && reason.isNotEmpty;

    if (total == 0) {
      return DVCompatibilityVerdict._(
        candidate: latest.protocol,
        served: served,
        threshold: window.strandThreshold,
        histogram: histogram,
        stranded: const <int, double>{},
        allowed: hasReason,
        overridden: hasReason,
        refusal:
            'no client sessions in the last seven days; the histogram is '
            'no evidence that nobody would be stranded',
        overrideReason: hasReason ? reason : null,
      );
    }

    final Map<int, double> stranded = <int, double>{
      for (final MapEntry<int, int> e in histogram.entries)
        if (!served.contains(e.key) && e.value / total > window.strandThreshold)
          e.key: e.value / total,
    };
    if (stranded.isEmpty) {
      return DVCompatibilityVerdict._(
        candidate: latest.protocol,
        served: served,
        threshold: window.strandThreshold,
        histogram: histogram,
        stranded: stranded,
        allowed: true,
        overridden: false,
      );
    }

    String percent(double share) => '${(share * 100).toStringAsFixed(2)}%';
    final String refusal = <String>[
      for (final MapEntry<int, double> e in stranded.entries)
        'protocol ${e.key} carries ${percent(e.value)} of sessions',
    ].join(', ');
    final String histogramJson = jsonEncode(<String, int>{
      for (final MapEntry<int, int> e in histogram.entries) '${e.key}': e.value,
    });
    final String message =
        'deploy would strand clients above the threshold: '
        '$refusal over the last seven days, above '
        '${percent(window.strandThreshold)}, outside protocol '
        '${latest.protocol}\'s window ${(served.toList()..sort())}; '
        'histogram $histogramJson'
        '${hasReason ? '; overridden: $reason' : ''}';
    diagnose('DV-PROTO-005', message);
    return DVCompatibilityVerdict._(
      candidate: latest.protocol,
      served: served,
      threshold: window.strandThreshold,
      histogram: histogram,
      stranded: stranded,
      allowed: hasReason,
      overridden: hasReason,
      refusal: message,
      overrideReason: hasReason ? reason : null,
    );
  }
}
