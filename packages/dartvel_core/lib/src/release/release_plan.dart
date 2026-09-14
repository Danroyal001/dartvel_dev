/// The strategy a release actually runs under, which is the adapter's answer.
///
/// A closed list in the planner cannot be taught by a new adapter, and
/// platforms differ in what they can weight. So the adapter says whether it
/// can split traffic, and where it cannot, a canary degrades to blue-green and
/// the plan says so (`DV-RELEASE-002`). Splitting by DNS is not simulated:
/// resolvers cache for as long as they like, so neither the split nor the
/// rollback would be a measurement anybody could trust.
library;

import 'deploy_config.dart';
import 'release_diagnostics.dart';

/// A deploy target, as the release pipeline drives it.
abstract interface class DVReleaseAdapter {
  /// The platform, e.g. `cloud-run`.
  String get name;

  /// Whether the platform can send a weighted share of traffic to one
  /// release: revision weights, alias weights, per-machine rollout, ingress
  /// weighting. A platform that would need DNS to do it answers false.
  bool get canWeightTraffic;

  /// Sends [percent] of traffic to [candidate] and the rest to [previous].
  ///
  /// 0 restores [previous] entirely; 100 retires it.
  Future<void> route({
    required String candidate,
    required String? previous,
    required int percent,
  });

  /// The percentage of traffic the platform reports [release] receiving, or
  /// null when it cannot be read.
  Future<int?> weightOf(String release);
}

/// The sequence a deploy will follow, before anything runs.
final class DVReleasePlan {
  const DVReleasePlan._({
    required this.adapter,
    required this.requested,
    required this.strategy,
    required this.steps,
    required this.hold,
    required this.gate,
    required this.findings,
  });

  /// The adapter that answered.
  final String adapter;

  /// What `dartvel.deploy.strategy` asked for.
  final DVDeployStrategy requested;

  /// What will run.
  final DVDeployStrategy strategy;

  /// The percentages of traffic the candidate receives, in order.
  final List<int> steps;

  /// How long each step is watched before the gate is read.
  final Duration hold;
  final DVReleaseThresholds gate;
  final List<DVReleaseFinding> findings;

  /// The requested strategy could not run on this adapter.
  bool get degraded => requested != strategy;

  /// The plan as `dartvel deploy --plan` prints it.
  String describe() {
    final StringBuffer out = StringBuffer()
      ..writeln(
        'strategy  ${strategy.configName}'
        '${degraded ? ' (requested ${requested.configName})' : ''}'
        ' on $adapter',
      )
      ..writeln(
        'steps     ${steps.map((int s) => '$s%').join(' -> ')}, '
        'holding ${_describe(hold)} at each before the gate is read',
      )
      ..writeln(
        'gate      error rate +${_points(gate.errorRate)} over the previous '
        'release',
      );
    for (final MapEntry<DVRequestStage, double> e in gate.stages.entries) {
      out.writeln(
        '          stage ${e.key.number} (${e.key.name}) '
        '+${_points(e.value)}',
      );
    }
    out.writeln(
      '          p95 latency +${(gate.latencyP95Increase * 100).toStringAsFixed(0)}%',
    );
    for (final DVReleaseFinding finding in findings) {
      out.writeln(finding);
    }
    return out.toString();
  }

  static String _points(double share) =>
      '${(share * 100).toStringAsFixed(2)} points';

  static String _describe(Duration d) => d.inSeconds % 3600 == 0
      ? '${d.inHours}h'
      : d.inSeconds % 60 == 0
      ? '${d.inMinutes}m'
      : '${d.inSeconds}s';
}

/// Plans a release against an adapter.
abstract final class DVReleasePlanner {
  static DVReleasePlan plan(
    DVDeployConfig config,
    DVReleaseAdapter adapter, {
    DVReleaseDiagnosticSink? onDiagnostic,
  }) {
    final DVReleaseDiagnosticSink diagnose =
        onDiagnostic ?? dvLogReleaseDiagnostic;
    config.canary.validate();
    final List<DVReleaseFinding> findings = <DVReleaseFinding>[];
    DVDeployStrategy strategy = config.strategy;
    if (strategy == DVDeployStrategy.canary && !adapter.canWeightTraffic) {
      strategy = DVDeployStrategy.blueGreen;
      final DVReleaseFinding finding = DVReleaseFinding(
        'DV-RELEASE-002',
        '${adapter.name} cannot weight traffic, so the canary runs as '
            'blue-green: the new release takes all traffic at once, is held '
            'for ${DVReleasePlan._describe(config.canary.hold)} under the '
            'health gate, and is switched back if the gate trips',
      );
      findings.add(finding);
      diagnose(finding.code, finding.message);
    }
    return DVReleasePlan._(
      adapter: adapter.name,
      requested: config.strategy,
      strategy: strategy,
      steps: strategy == DVDeployStrategy.canary
          ? List<int>.unmodifiable(config.canary.steps)
          : const <int>[100],
      hold: config.canary.hold,
      gate: config.gate,
      findings: List<DVReleaseFinding>.unmodifiable(findings),
    );
  }
}
