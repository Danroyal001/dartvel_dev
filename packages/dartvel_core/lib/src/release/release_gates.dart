/// The gates a rollout passes, holds or rolls back on, and how they compose.
///
/// The framework already has most of the gates a release needs, each written
/// for its own section: the error-budget hold, crash release health, the
/// protocol compatibility check, and the schema production gate. They are
/// composed here rather than reimplemented, with one rule added that none of
/// them needed on its own: **a gate whose evidence is missing holds**. An
/// empty feed read as a clean one passes exactly the release the gate exists
/// to stop.
///
/// A hold can be overridden, by a named person with a reason, and the
/// override is recorded with the evidence it overrode. A roll back cannot.
library;

import 'dart:async';

import '../alerting/service_levels.dart';
import '../crashes/release_health.dart';
import '../protocol/compatibility_check.dart';
import '../protocol/contract.dart';
import '../schema/schema_planner.dart';
import 'release_record.dart';

/// When a gate is read.
enum DVReleasePhase {
  /// Before the candidate receives any traffic.
  beforeDeploy,

  /// After a step's hold, before the candidate's weight grows.
  beforePromotion,
}

/// What a gate, or a composition of gates, decided.
enum DVGateVerdict { pass, hold, rollBack }

/// What a gate is asked about.
final class DVReleaseGateContext {
  const DVReleaseGateContext({
    required this.candidate,
    required this.previous,
    required this.phase,
    required this.percent,
    required this.stepStartedAt,
    required this.now,
  });

  final DVReleaseRecord candidate;

  /// The release being replaced, or null on a first deploy.
  final DVReleaseRecord? previous;
  final DVReleasePhase phase;

  /// The candidate's share of traffic during the step being judged.
  final int percent;

  /// When the step being judged began.
  final DateTime stepStartedAt;
  final DateTime now;
}

/// One gate's answer.
final class DVGateOutcome {
  const DVGateOutcome.pass(
    this.gate, {
    this.evidence = const <String, Object?>{},
  }) : verdict = DVGateVerdict.pass,
       reason = null,
       code = null,
       overridable = false,
       flagsToTurnOff = const <String>[];

  const DVGateOutcome.hold(
    this.gate,
    String this.reason, {
    this.code,
    this.overridable = true,
    this.flagsToTurnOff = const <String>[],
    this.evidence = const <String, Object?>{},
  }) : verdict = DVGateVerdict.hold;

  const DVGateOutcome.rollBack(
    this.gate,
    String this.reason, {
    this.code,
    this.flagsToTurnOff = const <String>[],
    this.evidence = const <String, Object?>{},
  }) : verdict = DVGateVerdict.rollBack,
       overridable = false;

  /// The gate's name.
  final String gate;
  final DVGateVerdict verdict;
  final String? reason;

  /// The diagnostic code behind the answer, when there is one.
  final String? code;

  /// Whether a recorded override may let this hold through.
  final bool overridable;

  /// Staged feature flags to turn off when this answer stops the rollout.
  final List<String> flagsToTurnOff;

  /// What the gate decided on, kept with any override of it.
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'gate': gate,
    'verdict': verdict.name,
    if (reason != null) 'reason': reason,
    if (code != null) 'code': code,
    if (verdict == DVGateVerdict.hold) 'overridable': overridable,
    if (flagsToTurnOff.isNotEmpty) 'flagsToTurnOff': flagsToTurnOff,
    if (evidence.isNotEmpty) 'evidence': evidence,
  };
}

/// A gate.
abstract interface class DVReleaseGate {
  /// Unique within a composition; overrides address a gate by it.
  String get name;

  /// The phases this gate is read in.
  Set<DVReleasePhase> get phases;

  FutureOr<DVGateOutcome> evaluate(DVReleaseGateContext context);
}

/// An explicit decision to let one gate's hold through.
///
/// A reason and a person are required. An override without them is a hold
/// switched off quietly, which is the thing a gate exists to prevent.
final class DVGateOverride {
  DVGateOverride({
    required this.gate,
    required String reason,
    required this.by,
    required this.at,
  }) : reason = reason.trim() {
    if (gate.trim().isEmpty) {
      throw ArgumentError.value(gate, 'gate', 'an override names its gate');
    }
    if (this.reason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'an override needs a reason');
    }
    if (by.trim().isEmpty) {
      throw ArgumentError.value(by, 'by', 'an override needs a person');
    }
  }

  final String gate;
  final String reason;
  final String by;
  final DateTime at;
}

/// An override that let a hold through: what to write where overrides are
/// kept.
final class DVGateOverrideRecord {
  const DVGateOverrideRecord({
    required this.gate,
    required this.code,
    required this.reason,
    required this.by,
    required this.at,
    required this.overrode,
    required this.evidence,
  });

  final String gate;
  final String? code;
  final String reason;
  final String by;
  final DateTime at;

  /// The hold's own reason.
  final String overrode;
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'gate': gate,
    if (code != null) 'code': code,
    'reason': reason,
    'by': by,
    'at': at.toUtc().toIso8601String(),
    'overrode': overrode,
    'evidence': evidence,
  };
}

/// What a composition of gates decided.
final class DVGateDecision {
  const DVGateDecision({
    required this.verdict,
    required this.outcomes,
    required this.overrides,
    required this.flagsToTurnOff,
  });

  final DVGateVerdict verdict;

  /// Every gate's own answer, overridden or not.
  final List<DVGateOutcome> outcomes;

  /// The overrides that let a hold through.
  final List<DVGateOverrideRecord> overrides;

  /// Flags named by the answers that stopped the rollout.
  final List<String> flagsToTurnOff;

  bool get proceed => verdict == DVGateVerdict.pass;

  /// The reasons the rollout did not proceed.
  List<String> get reasons => <String>[
    for (final DVGateOutcome o in outcomes)
      if (o.verdict != DVGateVerdict.pass &&
          !overrides.any((DVGateOverrideRecord r) => r.gate == o.gate))
        '${o.gate}: ${o.reason}',
  ];
}

/// Gates read together.
final class DVReleaseGates {
  DVReleaseGates(
    Iterable<DVReleaseGate> gates, {
    this.timeout = const Duration(seconds: 30),
  }) : gates = List<DVReleaseGate>.unmodifiable(gates) {
    final Set<String> names = <String>{};
    for (final DVReleaseGate gate in this.gates) {
      if (!names.add(gate.name)) {
        throw ArgumentError.value(
          gate.name,
          'gates',
          'two gates share a name, so an override could not say which it means',
        );
      }
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  /// The name a hold carries when no gate applies to the phase.
  static const String noGates = 'no-gates';

  final List<DVReleaseGate> gates;

  /// How long one gate may take. A gate that never answers holds, so the
  /// rollout says why it is not moving.
  final Duration timeout;

  Future<DVGateDecision> evaluate(
    DVReleaseGateContext context, {
    Iterable<DVGateOverride> overrides = const <DVGateOverride>[],
  }) async {
    final Map<String, DVGateOverride> byGate = <String, DVGateOverride>{};
    for (final DVGateOverride override in overrides) {
      if (byGate.containsKey(override.gate)) {
        throw ArgumentError.value(
          override.gate,
          'overrides',
          'the gate is overridden twice; which reason is recorded?',
        );
      }
      byGate[override.gate] = override;
    }

    final List<DVReleaseGate> applicable = <DVReleaseGate>[
      for (final DVReleaseGate gate in gates)
        if (gate.phases.contains(context.phase)) gate,
    ];
    final List<DVGateOutcome> outcomes = applicable.isEmpty
        ? <DVGateOutcome>[
            DVGateOutcome.hold(
              noGates,
              'no gate is read ${_phase(context.phase)}, so nothing was checked',
            ),
          ]
        : await Future.wait(<Future<DVGateOutcome>>[
            for (final DVReleaseGate gate in applicable) _read(gate, context),
          ]);

    bool rollBack = false;
    bool held = false;
    final List<DVGateOverrideRecord> used = <DVGateOverrideRecord>[];
    final List<String> flags = <String>[];
    for (final DVGateOutcome outcome in outcomes) {
      switch (outcome.verdict) {
        case DVGateVerdict.pass:
          break;
        case DVGateVerdict.rollBack:
          rollBack = true;
          _addFlags(flags, outcome.flagsToTurnOff);
        case DVGateVerdict.hold:
          final DVGateOverride? override = byGate[outcome.gate];
          if (override != null && outcome.overridable) {
            used.add(
              DVGateOverrideRecord(
                gate: outcome.gate,
                code: outcome.code,
                reason: override.reason,
                by: override.by,
                at: override.at,
                overrode: outcome.reason!,
                evidence: outcome.evidence,
              ),
            );
          } else {
            held = true;
            _addFlags(flags, outcome.flagsToTurnOff);
          }
      }
    }
    return DVGateDecision(
      verdict: rollBack
          ? DVGateVerdict.rollBack
          : held
          ? DVGateVerdict.hold
          : DVGateVerdict.pass,
      outcomes: List<DVGateOutcome>.unmodifiable(outcomes),
      overrides: List<DVGateOverrideRecord>.unmodifiable(used),
      flagsToTurnOff: List<String>.unmodifiable(flags),
    );
  }

  Future<DVGateOutcome> _read(
    DVReleaseGate gate,
    DVReleaseGateContext context,
  ) async {
    final DVGateOutcome outcome;
    try {
      final FutureOr<DVGateOutcome> answer = gate.evaluate(context);
      outcome = answer is Future<DVGateOutcome>
          ? await answer.timeout(timeout)
          : answer;
    } on TimeoutException {
      return DVGateOutcome.hold(
        gate.name,
        'gate ${gate.name} did not answer within ${timeout.inMilliseconds} ms',
      );
    } catch (error) {
      return DVGateOutcome.hold(
        gate.name,
        'gate ${gate.name} could not be read: $error',
      );
    }
    if (outcome.gate != gate.name) {
      return DVGateOutcome.hold(
        gate.name,
        'gate ${gate.name} answered as ${outcome.gate}',
      );
    }
    return outcome;
  }

  static void _addFlags(List<String> into, List<String> flags) {
    for (final String flag in flags) {
      if (!into.contains(flag)) into.add(flag);
    }
  }

  static String _phase(DVReleasePhase phase) => switch (phase) {
    DVReleasePhase.beforeDeploy => 'before deploy',
    DVReleasePhase.beforePromotion => 'before promotion',
  };
}

/// Alerting's error-budget hold, read before a deploy and before each
/// promotion.
final class DVErrorBudgetReleaseGate implements DVReleaseGate {
  DVErrorBudgetReleaseGate(this.gate, {this.name = 'error-budget'});

  final DVErrorBudgetGate gate;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => DVReleasePhase.values.toSet();

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) {
    final List<DVServiceLevel> levels = gate.levels.levels;
    if (levels.isEmpty) {
      return DVGateOutcome.hold(
        name,
        'no service level is declared, so there is no budget to read',
      );
    }
    // DVErrorBudgetGate reads a level with no samples, or no requests in its
    // window, as not exhausted, which is right for an alert and wrong for a
    // rollout.
    final List<String> unsampled = <String>[];
    final List<String> quiet = <String>[];
    for (final DVServiceLevel level in levels) {
      final DVServiceLevelStatus status =
          gate.levels.status(level.name, now: context.now);
      if (status.hasData) continue;
      (status.requests == null ? unsampled : quiet).add(level.name);
    }
    if (unsampled.isNotEmpty || quiet.isNotEmpty) {
      return DVGateOutcome.hold(
        name,
        '${<String>[
          if (unsampled.isNotEmpty)
            'service level ${unsampled.join(', ')} has no samples',
          if (quiet.isNotEmpty)
            'service level ${quiet.join(', ')} saw no requests in its window',
        ].join('; ')}; an unread budget is not an unspent one',
        evidence: <String, Object?>{
          'unread': <String>[...unsampled, ...quiet],
          if (quiet.isNotEmpty) 'noTraffic': quiet,
        },
      );
    }
    final DVErrorBudgetDecision decision = gate.evaluate(now: context.now);
    if (decision.hold) {
      return DVGateOutcome.hold(
        name,
        'the error budget is exhausted for ${decision.exhausted.join(', ')}',
        evidence: <String, Object?>{'exhausted': decision.exhausted},
      );
    }
    return DVGateOutcome.pass(name);
  }
}

/// Crash release health, read before each promotion.
final class DVCrashHealthReleaseGate implements DVReleaseGate {
  DVCrashHealthReleaseGate({
    required this.gate,
    required this.health,
    this.release,
    this.patch,
    this.name = 'crash-health',
  });

  final DVReleaseHealthGate gate;
  final DVReleaseHealth health;

  /// The release name sessions are counted under; the candidate's id when
  /// null.
  final String? release;
  final String? patch;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforePromotion,
  };

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) {
    final String counted = release ?? context.candidate.id;
    final DVReleaseHealthNumbers overall = health.numbers(
      release: counted,
      patch: patch,
    );
    final int needed = gate.minimumSessions < 1 ? 1 : gate.minimumSessions;
    // Below its minimum DVReleaseHealthGate does not read the number, and so
    // does not hold: too few sessions is no evidence either way.
    if (overall.sessions < needed) {
      return DVGateOutcome.hold(
        name,
        '${overall.sessions} session(s) of $counted have started; crash '
        'health is read from $needed',
        evidence: <String, Object?>{'sessions': overall.sessions},
      );
    }
    final DVReleaseHealthDecision decision = gate.evaluate(
      health,
      release: counted,
      patch: patch,
    );
    final Map<String, Object?> evidence = <String, Object?>{
      'sessions': overall.sessions,
      'crashedSessions': overall.crashedSessions,
      'crashFreeSessions': overall.crashFreeSessions,
      if (decision.heldCohorts.isNotEmpty) 'heldCohorts': decision.heldCohorts,
    };
    if (decision.hold) {
      return DVGateOutcome.hold(
        name,
        '$counted is below its crash-free threshold'
        '${decision.heldCohorts.isEmpty ? '' : ' in ${decision.heldCohorts.join(', ')}'}',
        code: 'DV-CRASH-010',
        flagsToTurnOff: decision.flagsToTurnOff,
        evidence: evidence,
      );
    }
    return DVGateOutcome.pass(name, evidence: evidence);
  }
}

/// `dartvel compatibility-check --against production`, read before deploy.
final class DVProtocolReleaseGate implements DVReleaseGate {
  DVProtocolReleaseGate({
    required this.lock,
    this.window = const DVProtocolWindow(),
    required this.samples,
    this.name = 'protocol',
    this.onDiagnostic,
  });

  /// The candidate's protocol lock.
  final DVProtocolLock lock;
  final DVProtocolWindow window;

  /// Sessions per protocol version, from monitoring.
  final FutureOr<Iterable<DVProtocolSessionSample>> Function() samples;
  final void Function(String code, String message)? onDiagnostic;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforeDeploy,
  };

  @override
  Future<DVGateOutcome> evaluate(DVReleaseGateContext context) async {
    final int? locked = lock.current?.protocol;
    if (locked != context.candidate.protocolVersion) {
      return DVGateOutcome.hold(
        name,
        'the protocol lock is at ${locked ?? 'no version'} and release '
        '${context.candidate.id} records protocol '
        '${context.candidate.protocolVersion}; the check would be about '
        'another build',
        overridable: false,
      );
    }
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock,
      window: window,
      samples: await samples(),
      now: context.now,
      onDiagnostic: onDiagnostic,
    );
    if (!verdict.allowed) {
      return DVGateOutcome.hold(
        name,
        verdict.refusal!,
        code: verdict.stranded.isEmpty ? null : 'DV-PROTO-005',
        evidence: verdict.toJson(),
      );
    }
    return DVGateOutcome.pass(name, evidence: verdict.toJson());
  }
}

/// The schema production gate, read before deploy.
final class DVSchemaReleaseGate implements DVReleaseGate {
  DVSchemaReleaseGate({
    required this.plan,
    this.production = true,
    this.name = 'schema',
  });

  final DVSchemaPlan plan;
  final bool production;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforeDeploy,
  };

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) {
    final DVSchemaGateResult result = const DVSchemaDeployGate().check(
      plan,
      production: production,
    );
    if (result.allowed) return DVGateOutcome.pass(name);
    return DVGateOutcome.hold(
      name,
      result.findings.map((DVSchemaFinding f) => f.message).join(' '),
      code: 'DV-SCHEMA-002',
      evidence: <String, Object?>{
        'changes': <String>[
          for (final DVSchemaFinding f in result.findings)
            if (f.change != null) f.change!.description,
        ],
      },
    );
  }
}
