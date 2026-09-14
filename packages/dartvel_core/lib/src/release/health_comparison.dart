/// The health gate: the request lifecycle's own numbers, against the release
/// being replaced.
///
/// A `/healthz` that answers 200 while authorization refusals climb at stage
/// 12 is the reason a ping is not a health check. So the gate reads failures
/// by lifecycle stage as well as overall, and every margin is over the
/// previous release's number rather than an absolute one.
library;

import 'dart:async';

import 'deploy_config.dart';
import 'release_diagnostics.dart';
import 'release_gates.dart';

/// What one release served over a window.
final class DVReleaseTraffic {
  DVReleaseTraffic({
    required this.requests,
    required this.failed,
    Map<DVRequestStage, int> stageFailures = const <DVRequestStage, int>{},
    this.latencyP95,
  }) : stageFailures = Map<DVRequestStage, int>.unmodifiable(stageFailures) {
    if (requests < 0) {
      throw ArgumentError.value(requests, 'requests', 'is negative');
    }
    if (failed < 0 || failed > requests) {
      throw ArgumentError.value(
        failed,
        'failed',
        'must be between 0 and the $requests requests',
      );
    }
    this.stageFailures.forEach((DVRequestStage stage, int count) {
      if (count < 0 || count > requests) {
        throw ArgumentError.value(
          count,
          'stageFailures[${stage.name}]',
          'must be between 0 and the $requests requests',
        );
      }
    });
    final Duration? p95 = latencyP95;
    if (p95 != null && p95.isNegative) {
      throw ArgumentError.value(p95, 'latencyP95', 'is negative');
    }
  }

  final int requests;
  final int failed;

  /// Failures at each stage the source reports. A stage absent from the map
  /// was not reported, which is not the same as none.
  final Map<DVRequestStage, int> stageFailures;
  final Duration? latencyP95;
}

/// Reads what [release] served between [since] and [until], or null when the
/// source has nothing.
typedef DVReleaseTrafficSource =
    FutureOr<DVReleaseTraffic?> Function(
      String release,
      DateTime since,
      DateTime until,
    );

/// Promotes or rolls back on the lifecycle's numbers against the previous
/// release.
///
/// Where the previous release is not serving alongside the candidate -- blue
/// green, recreate -- the [source] answers for it from its own recorded
/// traffic; the gate asks for the same window either way.
final class DVHealthComparisonGate implements DVReleaseGate {
  DVHealthComparisonGate({
    required this.thresholds,
    required this.source,
    this.minimumRequests = 1,
    this.name = 'health',
    DVReleaseDiagnosticSink? onDiagnostic,
  }) : _diagnose = onDiagnostic ?? dvLogReleaseDiagnostic {
    if (minimumRequests < 1) {
      throw ArgumentError.value(
        minimumRequests,
        'minimumRequests',
        'a comparison needs at least one request on each side',
      );
    }
  }

  final DVReleaseThresholds thresholds;
  final DVReleaseTrafficSource source;

  /// Below this many requests on either side the rates are not compared.
  final int minimumRequests;
  final DVReleaseDiagnosticSink _diagnose;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforePromotion,
  };

  @override
  Future<DVGateOutcome> evaluate(DVReleaseGateContext context) async {
    final String candidate = context.candidate.id;
    final String? previous = context.previous?.id;
    if (previous == null) {
      const String code = 'DV-RELEASE-003';
      final String message =
          'release $candidate has no previous release to compare against; the '
          'gate held the rollout rather than passing it vacuously';
      _diagnose(code, message);
      return DVGateOutcome.hold(name, message, code: code);
    }

    final _Read now = await _readTraffic(candidate, context);
    if (now.hold != null) return now.hold!;
    final _Read before = await _readTraffic(previous, context);
    if (before.hold != null) return before.hold!;
    final DVReleaseTraffic c = now.traffic!;
    final DVReleaseTraffic b = before.traffic!;

    for (final DVRequestStage stage in thresholds.stages.keys) {
      for (final (String release, DVReleaseTraffic t) in <(String, DVReleaseTraffic)>[
        (candidate, c),
        (previous, b),
      ]) {
        if (!t.stageFailures.containsKey(stage)) {
          return DVGateOutcome.hold(
            name,
            'stage ${stage.number} (${stage.name}) failures were not reported '
            'for $release, and an unreported stage is not a clean one',
          );
        }
      }
    }
    if (c.latencyP95 == null || b.latencyP95 == null) {
      return DVGateOutcome.hold(
        name,
        'p95 latency was not reported for '
        '${c.latencyP95 == null ? candidate : previous}',
      );
    }

    final List<String> regressions = <String>[];
    final double cRate = c.failed / c.requests;
    final double bRate = b.failed / b.requests;
    if (cRate - bRate > thresholds.errorRate + _epsilon) {
      regressions.add(
        'error rate ${_pct(cRate)} against ${_pct(bRate)}, over the '
        '${_pct(thresholds.errorRate)} margin',
      );
    }
    final Map<String, Object?> stages = <String, Object?>{};
    thresholds.stages.forEach((DVRequestStage stage, double margin) {
      final double cs = c.stageFailures[stage]! / c.requests;
      final double bs = b.stageFailures[stage]! / b.requests;
      stages['${stage.number}'] = <String, double>{'candidate': cs, 'previous': bs};
      if (cs - bs > margin + _epsilon) {
        regressions.add(
          'stage ${stage.number} (${stage.name}) failures ${_pct(cs)} against '
          '${_pct(bs)}, over the ${_pct(margin)} margin',
        );
      }
    });
    final int cp95 = c.latencyP95!.inMicroseconds;
    final int bp95 = b.latencyP95!.inMicroseconds;
    if (cp95 > bp95 * (1 + thresholds.latencyP95Increase) + _epsilon) {
      regressions.add(
        'p95 latency ${cp95 / 1000} ms against ${bp95 / 1000} ms, over the '
        '+${(thresholds.latencyP95Increase * 100).toStringAsFixed(0)}% margin',
      );
    }

    final Map<String, Object?> evidence = <String, Object?>{
      'candidate': candidate,
      'previous': previous,
      'requests': <String, int>{'candidate': c.requests, 'previous': b.requests},
      'errorRate': <String, double>{'candidate': cRate, 'previous': bRate},
      'stages': stages,
      'latencyP95Micros': <String, int>{'candidate': cp95, 'previous': bp95},
    };
    if (regressions.isNotEmpty) {
      return DVGateOutcome.rollBack(
        name,
        '$candidate regressed against $previous: ${regressions.join('; ')}',
        evidence: evidence,
      );
    }
    return DVGateOutcome.pass(name, evidence: evidence);
  }

  Future<_Read> _readTraffic(
    String release,
    DVReleaseGateContext context,
  ) async {
    final DVReleaseTraffic? traffic;
    try {
      traffic = await source(release, context.stepStartedAt, context.now);
    } catch (error) {
      return _Read.held(
        DVGateOutcome.hold(
          name,
          'traffic for $release could not be read: $error',
        ),
      );
    }
    if (traffic == null) {
      return _Read.held(
        DVGateOutcome.hold(
          name,
          'the traffic source has nothing for $release over the step',
        ),
      );
    }
    if (traffic.requests < minimumRequests) {
      return _Read.held(
        DVGateOutcome.hold(
          name,
          '$release served ${traffic.requests} request(s) over the step; its '
          'health is compared from $minimumRequests',
        ),
      );
    }
    return _Read(traffic);
  }

  static const double _epsilon = 1e-9;

  static String _pct(double share) => '${(share * 100).toStringAsFixed(2)}%';
}

final class _Read {
  const _Read(this.traffic) : hold = null;
  const _Read.held(DVGateOutcome this.hold) : traffic = null;

  final DVReleaseTraffic? traffic;
  final DVGateOutcome? hold;
}
