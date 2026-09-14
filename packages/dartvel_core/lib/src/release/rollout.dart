/// The rollout: a release moving through its plan's steps under the gates.
///
/// Driven by a clock rather than by timers of its own, so the caller -- a
/// deploy command, a job, a test -- decides when it is looked at, and every
/// decision is made on a `now` somebody passed in.
///
/// The weight on the platform is the thing a rollout is judged by, so it is
/// only ever one of the plan's steps, it moves one step at a time, and it is
/// read back before anything is promoted on top of it. A platform reporting a
/// weight nobody planned holds the rollout rather than being corrected quietly.
library;

import 'dart:async';

import '../flags/flags.dart';
import 'release_diagnostics.dart';
import 'release_gates.dart';
import 'release_plan.dart';
import 'release_record.dart';

/// Where a rollout is.
enum DVRolloutState {
  /// Not yet routed any traffic; the deploy gates have not passed.
  waiting,

  /// Holding at one of the plan's steps.
  stepping,

  /// A gate tripped and the route back has not been confirmed.
  rollingBack,

  /// Promoted to all traffic and recorded in the history.
  completed,

  /// All traffic is back on the previous release.
  rolledBack,
}

enum DVRolloutEventKind { started, held, promoted, routeFailed, completed, rolledBack }

/// Something that happened to a rollout.
final class DVRolloutEvent {
  const DVRolloutEvent({
    required this.at,
    required this.kind,
    required this.percent,
    this.reasons = const <String>[],
    this.overrides = const <DVGateOverrideRecord>[],
  });

  final DateTime at;
  final DVRolloutEventKind kind;

  /// The candidate's planned share of traffic after the event.
  final int percent;
  final List<String> reasons;

  /// Overrides that let this event happen.
  final List<DVGateOverrideRecord> overrides;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'percent': percent,
    if (reasons.isNotEmpty) 'reasons': reasons,
    if (overrides.isNotEmpty)
      'overrides': <Object?>[
        for (final DVGateOverrideRecord o in overrides) o.toJson(),
      ],
  };
}

/// Turning staged flags off.
abstract final class DVReleaseFlags {
  /// [rules] with every flag in [keys] given a single rule that answers
  /// `false` for every context, and the rules version moved on.
  ///
  /// A rule rather than a removal: removing a flag's rules falls back to its
  /// compiled default, and the default of a flag staged to turn a feature on
  /// is very often on.
  static DVFlagRules turnOff(DVFlagRules? rules, Iterable<String> keys) {
    final Map<String, List<DVFlagRule>> flags = <String, List<DVFlagRule>>{
      ...?rules?.flags,
    };
    for (final String key in keys) {
      flags[key] = const <DVFlagRule>[DVFlagRule(value: false)];
    }
    return DVFlagRules(
      rulesVersion: (rules?.rulesVersion ?? 0) + 1,
      flags: flags,
    );
  }
}

/// Holds a rollout whose serving release has no provenance record: a roll
/// back from it could not name what it restores.
final class _PreviousProvenanceGate implements DVReleaseGate {
  const _PreviousProvenanceGate(this.serving);

  final DVDeployedRelease serving;

  @override
  String get name => 'previous-provenance';

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforeDeploy,
  };

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) => DVGateOutcome.hold(
    name,
    'release ${serving.id} is serving with no provenance record '
    '(DV-RELEASE-006), so a roll back from ${context.candidate.id} could not '
    'name what it restores',
  );
}

/// One release rolling out.
final class DVReleaseRollout {
  DVReleaseRollout({
    required this.plan,
    required this.adapter,
    required DVReleaseGates gates,
    required this.candidate,
    required this.history,
    FutureOr<void> Function(List<String> flags)? turnOffFlags,
    DVReleaseDiagnosticSink? onDiagnostic,
  }) : _turnOffFlags = turnOffFlags,
       _diagnose = onDiagnostic ?? dvLogReleaseDiagnostic,
       _serving = history.current,
       _gates = history.current != null && history.current!.provenance == null
           ? DVReleaseGates(<DVReleaseGate>[
               ...gates.gates,
               _PreviousProvenanceGate(history.current!),
             ], timeout: gates.timeout)
           : gates {
    if (plan.adapter != adapter.name) {
      throw ArgumentError.value(
        plan.adapter,
        'plan',
        'was made for ${plan.adapter}, not ${adapter.name}',
      );
    }
    if (plan.steps.length > 1 && !adapter.canWeightTraffic) {
      throw ArgumentError.value(
        plan.steps,
        'plan',
        '${adapter.name} cannot weight traffic',
      );
    }
    if (history.find(candidate.id) != null) {
      throw ArgumentError.value(
        candidate.id,
        'candidate',
        'has been deployed before; restoring it is a roll back, not a rollout',
      );
    }
  }

  final DVReleasePlan plan;
  final DVReleaseAdapter adapter;
  final DVReleaseRecord candidate;
  final DVReleaseHistory history;
  final DVReleaseGates _gates;
  final DVDeployedRelease? _serving;
  final FutureOr<void> Function(List<String> flags)? _turnOffFlags;
  final DVReleaseDiagnosticSink _diagnose;

  DVRolloutState _state = DVRolloutState.waiting;
  int _step = -1;
  int _percent = 0;
  DateTime? _stepStartedAt;
  List<String>? _rollBackReasons;
  final List<DVRolloutEvent> _events = <DVRolloutEvent>[];
  final List<DVGateOverrideRecord> _overrides = <DVGateOverrideRecord>[];
  final List<String> _flagsToTurnOff = <String>[];
  final Set<String> _flagsTurnedOff = <String>{};

  DVRolloutState get state => _state;

  /// The candidate's planned share of traffic: always 0 or one of the plan's
  /// steps.
  int get percent => _percent;

  /// The index of the step being held, or -1 before the first.
  int get step => _step;
  DateTime? get stepStartedAt => _stepStartedAt;
  List<DVRolloutEvent> get events => List<DVRolloutEvent>.unmodifiable(_events);

  /// Every override that let this rollout move.
  List<DVGateOverrideRecord> get overrides =>
      List<DVGateOverrideRecord>.unmodifiable(_overrides);

  /// Flags a hold or roll back has named.
  List<String> get flagsToTurnOff => List<String>.unmodifiable(_flagsToTurnOff);

  /// Reads the deploy gates and, when they pass, routes the first step.
  ///
  /// A held start routes nothing and can be retried, with overrides.
  Future<DVRolloutState> start({
    required DateTime now,
    Iterable<DVGateOverride> overrides = const <DVGateOverride>[],
  }) async {
    if (_state != DVRolloutState.waiting) return _state;
    final DVGateDecision decision = await _gates.evaluate(
      _context(DVReleasePhase.beforeDeploy, now, stepStartedAt: now),
      overrides: overrides,
    );
    _overrides.addAll(decision.overrides);
    if (!decision.proceed) {
      _event(now, DVRolloutEventKind.held, reasons: decision.reasons);
      await _flags(decision.flagsToTurnOff, now);
      return _state;
    }
    return _routeTo(0, now, decision.overrides);
  }

  /// Looks at the rollout as of [now]: once the step's hold is over, checks
  /// the platform's weight, reads the promotion gates, and promotes, holds or
  /// rolls back.
  Future<DVRolloutState> advance({
    required DateTime now,
    Iterable<DVGateOverride> overrides = const <DVGateOverride>[],
  }) async {
    switch (_state) {
      case DVRolloutState.waiting:
      case DVRolloutState.completed:
      case DVRolloutState.rolledBack:
        return _state;
      case DVRolloutState.rollingBack:
        return _rollBack(now, _rollBackReasons ?? const <String>[]);
      case DVRolloutState.stepping:
        break;
    }
    if (now.isBefore(_stepStartedAt!.add(plan.hold))) return _state;

    final int? reported = await _weight();
    if (reported != _percent) {
      _event(
        now,
        DVRolloutEventKind.held,
        reasons: <String>[
          'the platform reports ${reported == null ? 'no weight' : '$reported%'} '
              'for ${candidate.id} and the plan has it at $_percent%; nothing is '
              'promoted on a weight nobody planned',
        ],
      );
      return _state;
    }

    final DVGateDecision decision = await _gates.evaluate(
      _context(DVReleasePhase.beforePromotion, now, stepStartedAt: _stepStartedAt!),
      overrides: overrides,
    );
    _overrides.addAll(decision.overrides);
    switch (decision.verdict) {
      case DVGateVerdict.rollBack:
        await _flags(decision.flagsToTurnOff, now);
        return _rollBack(now, decision.reasons);
      case DVGateVerdict.hold:
        _event(now, DVRolloutEventKind.held, reasons: decision.reasons);
        await _flags(decision.flagsToTurnOff, now);
        return _state;
      case DVGateVerdict.pass:
        if (_step == plan.steps.length - 1) {
          history.deployed(candidate.id, provenance: candidate, at: now);
          _state = DVRolloutState.completed;
          _event(now, DVRolloutEventKind.completed, overrides: decision.overrides);
          return _state;
        }
        return _routeTo(_step + 1, now, decision.overrides);
    }
  }

  DVReleaseGateContext _context(
    DVReleasePhase phase,
    DateTime now, {
    required DateTime stepStartedAt,
  }) => DVReleaseGateContext(
    candidate: candidate,
    previous: _serving?.provenance,
    phase: phase,
    percent: _percent,
    stepStartedAt: stepStartedAt,
    now: now,
  );

  Future<DVRolloutState> _routeTo(
    int index,
    DateTime now,
    List<DVGateOverrideRecord> overrides,
  ) async {
    final int target = plan.steps[index];
    try {
      await adapter.route(
        candidate: candidate.id,
        previous: _serving?.id,
        percent: target,
      );
    } catch (error) {
      _event(
        now,
        DVRolloutEventKind.routeFailed,
        reasons: <String>['${adapter.name} did not take $target%: $error'],
      );
      return _state;
    }
    _step = index;
    _percent = target;
    _stepStartedAt = now;
    _state = DVRolloutState.stepping;
    _event(
      now,
      index == 0 ? DVRolloutEventKind.started : DVRolloutEventKind.promoted,
      overrides: overrides,
    );
    return _state;
  }

  Future<DVRolloutState> _rollBack(DateTime now, List<String> reasons) async {
    _state = DVRolloutState.rollingBack;
    _rollBackReasons ??= reasons;
    try {
      await adapter.route(
        candidate: candidate.id,
        previous: _serving?.id,
        percent: 0,
      );
    } catch (error) {
      _event(
        now,
        DVRolloutEventKind.routeFailed,
        reasons: <String>['${adapter.name} did not take the roll back: $error'],
      );
      return _state;
    }
    final int? reported = await _weight();
    if (reported != 0) {
      _event(
        now,
        DVRolloutEventKind.held,
        reasons: <String>[
          'after the roll back the platform reports '
              '${reported == null ? 'no weight' : '$reported%'} for '
              '${candidate.id}; the roll back is not confirmed',
        ],
      );
      return _state;
    }
    _percent = 0;
    _state = DVRolloutState.rolledBack;
    _event(now, DVRolloutEventKind.rolledBack, reasons: _rollBackReasons!);
    _diagnose(
      'DV-RELEASE-001',
      'the health gate tripped for ${candidate.id} and the rollout was rolled '
          'back to ${_serving?.id ?? 'no release'}: '
          '${_rollBackReasons!.join('; ')}',
    );
    return _state;
  }

  Future<int?> _weight() async {
    try {
      return await adapter.weightOf(candidate.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _flags(List<String> flags, DateTime now) async {
    for (final String flag in flags) {
      if (!_flagsToTurnOff.contains(flag)) _flagsToTurnOff.add(flag);
    }
    final FutureOr<void> Function(List<String>)? turnOff = _turnOffFlags;
    if (turnOff == null) return;
    final List<String> pending = <String>[
      for (final String flag in _flagsToTurnOff)
        if (!_flagsTurnedOff.contains(flag)) flag,
    ];
    if (pending.isEmpty) return;
    try {
      await turnOff(pending);
      _flagsTurnedOff.addAll(pending);
    } catch (error) {
      _event(
        now,
        DVRolloutEventKind.held,
        reasons: <String>[
          'flags ${pending.join(', ')} could not be turned off: $error',
        ],
      );
    }
  }

  void _event(
    DateTime at,
    DVRolloutEventKind kind, {
    List<String> reasons = const <String>[],
    List<DVGateOverrideRecord> overrides = const <DVGateOverrideRecord>[],
  }) {
    _events.add(
      DVRolloutEvent(
        at: at,
        kind: kind,
        percent: _percent,
        reasons: List<String>.unmodifiable(reasons),
        overrides: List<DVGateOverrideRecord>.unmodifiable(overrides),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'candidate': candidate.toJson(),
    'previous': _serving?.id,
    'adapter': adapter.name,
    'strategy': plan.strategy.configName,
    'steps': plan.steps,
    'state': _state.name,
    'step': _step,
    'percent': _percent,
    'events': <Object?>[for (final DVRolloutEvent e in _events) e.toJson()],
    'overrides': <Object?>[
      for (final DVGateOverrideRecord o in _overrides) o.toJson(),
    ],
    'flagsToTurnOff': _flagsToTurnOff,
    'flagsTurnedOff': _flagsTurnedOff.toList(),
  };
}
