// The rollout: steps, holds, promotion and roll back, driven by the gates.
//
// A rollout is judged by the weight it leaves on the platform. The quiet
// failures: a hold that nonetheless moves the weight on; a promotion after a
// hold that skips a step; a platform that reports a weight other than the one
// planned, promoted anyway; a roll back whose route failed, reported as done;
// and a hold that names staged flags and turns none of them off.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 11, 14);
const Duration hold = Duration(minutes: 10);
DateTime at(int holds, [int extraMinutes = 0]) =>
    t0.add(hold * holds + Duration(minutes: extraMinutes));

DVReleaseRecord record(String id) => DVReleaseRecord(
  id: id,
  commit: 'commit-$id',
  artifact: 'sha256:$id',
  protocolVersion: 3,
  migrationPlan: null,
  releasedBy: 'daniel',
  releasedAt: t0,
);

class _Platform implements DVReleaseAdapter {
  _Platform({this.canWeightTraffic = true});

  @override
  String get name => 'fake-platform';

  @override
  final bool canWeightTraffic;

  final List<int> routed = <int>[];
  int weight = 0;

  /// What the platform claims, when it disagrees with what it was told.
  int? reports;
  bool readable = true;
  int failRoutes = 0;

  @override
  Future<void> route({
    required String candidate,
    required String? previous,
    required int percent,
  }) async {
    if (failRoutes > 0) {
      failRoutes--;
      throw StateError('platform refused the weight');
    }
    routed.add(percent);
    weight = percent;
  }

  @override
  Future<int?> weightOf(String release) async =>
      readable ? (reports ?? weight) : null;
}

/// A gate whose answer the test sets.
class _Scripted implements DVReleaseGate {
  _Scripted(this.name, this.phases);

  @override
  final String name;

  @override
  final Set<DVReleasePhase> phases;

  DVGateOutcome Function(DVReleaseGateContext) answer = (
    DVReleaseGateContext c,
  ) => throw StateError('unset');
  final List<DVReleaseGateContext> asked = <DVReleaseGateContext>[];

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) {
    asked.add(context);
    return answer(context);
  }

  void pass() => answer = (_) => DVGateOutcome.pass(name);
  void holdWith(String reason, {List<String> flags = const <String>[]}) =>
      answer = (_) =>
          DVGateOutcome.hold(name, reason, flagsToTurnOff: flags);
  void rollBack(String reason) =>
      answer = (_) => DVGateOutcome.rollBack(name, reason);
}

class _Fixture {
  _Fixture({
    bool canWeight = true,
    DVDeployStrategy strategy = DVDeployStrategy.canary,
    bool firstDeploy = false,
    bool previousHasRecord = true,
  }) : platform = _Platform(canWeightTraffic: canWeight) {
    if (!firstDeploy) {
      history.deployed(
        'r1',
        provenance: previousHasRecord ? record('r1') : null,
        at: t0.subtract(const Duration(days: 1)),
      );
    }
    deploy
      ..pass()
      ..answer = (_) => const DVGateOutcome.pass('deploy');
    health.pass();
    rollout = DVReleaseRollout(
      plan: DVReleasePlanner.plan(
        DVDeployConfig(
          strategy: strategy,
          canary: const DVCanaryConfig(
            steps: <int>[5, 25, 50, 100],
            hold: hold,
          ),
        ),
        platform,
        onDiagnostic: (_, _) {},
      ),
      adapter: platform,
      gates: DVReleaseGates(<DVReleaseGate>[deploy, health]),
      candidate: record('r2'),
      history: history,
      turnOffFlags: (List<String> flags) => turnedOff.add(flags),
      onDiagnostic: (String code, _) => codes.add(code),
    );
  }

  final _Platform platform;
  final DVReleaseHistory history = DVReleaseHistory(onDiagnostic: (_, _) {});
  final _Scripted deploy = _Scripted('deploy', <DVReleasePhase>{
    DVReleasePhase.beforeDeploy,
  });
  final _Scripted health = _Scripted('health', <DVReleasePhase>{
    DVReleasePhase.beforePromotion,
  });
  final List<List<String>> turnedOff = <List<String>>[];
  final List<String> codes = <String>[];
  late final DVReleaseRollout rollout;
}

void main() {
  group('starting', () {
    test('a passing deploy gate routes the first step', () async {
      final _Fixture f = _Fixture();
      expect(await f.rollout.start(now: t0), DVRolloutState.stepping);
      expect(f.platform.routed, <int>[5]);
      expect(f.rollout.percent, 5);
      expect(f.deploy.asked.single.phase, DVReleasePhase.beforeDeploy);
      expect(f.deploy.asked.single.previous!.id, 'r1');
    });

    test('a held deploy gate routes nothing, and an override with a reason '
        'starts it and is recorded', () async {
      final _Fixture f = _Fixture();
      f.deploy.holdWith('blocking migration');
      expect(await f.rollout.start(now: t0), DVRolloutState.waiting);
      expect(f.platform.routed, isEmpty);
      expect(f.rollout.events.last.kind, DVRolloutEventKind.held);
      expect(f.rollout.events.last.reasons.single, contains('blocking migration'));

      expect(
        await f.rollout.start(
          now: at(0, 1),
          overrides: <DVGateOverride>[
            DVGateOverride(
              gate: 'deploy',
              reason: 'three in the morning, everyone told',
              by: 'daniel',
              at: at(0, 1),
            ),
          ],
        ),
        DVRolloutState.stepping,
      );
      expect(f.platform.routed, <int>[5]);
      expect(f.rollout.overrides.single.reason,
          'three in the morning, everyone told');
      expect(
        f.rollout.toJson()['overrides'],
        contains(containsPair('by', 'daniel')),
      );
    });

    test('a release serving with no provenance record holds the next rollout',
        () async {
      final _Fixture f = _Fixture(previousHasRecord: false);
      expect(await f.rollout.start(now: t0), DVRolloutState.waiting);
      expect(f.platform.routed, isEmpty);
      expect(f.rollout.events.last.reasons.single, contains('r1'));
    });

    test('a plan made for another adapter is refused', () {
      final _Platform other = _Platform(canWeightTraffic: false);
      final DVReleasePlan plan = DVReleasePlanner.plan(
        const DVDeployConfig(strategy: DVDeployStrategy.canary),
        _NamedPlatform('cloud-run'),
        onDiagnostic: (_, _) {},
      );
      expect(
        () => DVReleaseRollout(
          plan: plan,
          adapter: other,
          gates: DVReleaseGates(const <DVReleaseGate>[]),
          candidate: record('r2'),
          history: DVReleaseHistory(onDiagnostic: (_, _) {}),
        ),
        throwsArgumentError,
      );
    });

    test('a candidate already serving is refused', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )..deployed('r2', provenance: record('r2'), at: t0);
      final _Platform platform = _Platform();
      expect(
        () => DVReleaseRollout(
          plan: DVReleasePlanner.plan(
            const DVDeployConfig(),
            platform,
            onDiagnostic: (_, _) {},
          ),
          adapter: platform,
          gates: DVReleaseGates(const <DVReleaseGate>[]),
          candidate: record('r2'),
          history: history,
        ),
        throwsArgumentError,
      );
    });
  });

  group('stepping', () {
    test('nothing is read or moved before the hold is over', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      await f.rollout.advance(now: at(0, 9));
      expect(f.health.asked, isEmpty);
      expect(f.platform.routed, <int>[5]);
    });

    test('the gate is read over the step, and a pass moves one step', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      await f.rollout.advance(now: at(1));
      expect(f.health.asked.single.stepStartedAt, t0);
      expect(f.health.asked.single.now, at(1));
      expect(f.health.asked.single.percent, 5);
      expect(f.platform.routed, <int>[5, 25]);
      // The next step's hold starts now, not at the start of the rollout.
      await f.rollout.advance(now: at(1, 9));
      expect(f.platform.routed, <int>[5, 25]);
      expect(f.health.asked, hasLength(1));
    });

    test('a hold keeps the weight where it is, and the promotion after it is '
        'the next step, not a later one', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.health.holdWith('not enough traffic');
      await f.rollout.advance(now: at(1));
      await f.rollout.advance(now: at(2));
      await f.rollout.advance(now: at(3));
      expect(f.platform.routed, <int>[5]);
      expect(f.rollout.percent, 5);
      f.health.pass();
      await f.rollout.advance(now: at(4));
      expect(f.platform.routed, <int>[5, 25]);
    });

    test('a full rollout routes exactly the planned steps and records the '
        'release in the history', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      for (int i = 1; i <= 4; i++) {
        await f.rollout.advance(now: at(i));
      }
      expect(f.platform.routed, <int>[5, 25, 50, 100]);
      expect(f.rollout.state, DVRolloutState.completed);
      // The last step is watched and gated too, before it counts as done.
      expect(f.health.asked, hasLength(4));
      expect(f.history.current!.id, 'r2');
      expect(f.history.current!.provenance!.commit, 'commit-r2');
    });

    test('a completed rollout does not move again', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      for (int i = 1; i <= 4; i++) {
        await f.rollout.advance(now: at(i));
      }
      await f.rollout.advance(now: at(9));
      expect(f.platform.routed, <int>[5, 25, 50, 100]);
      expect(f.health.asked, hasLength(4));
    });

    test('a platform reporting a weight other than the plan holds, and does '
        'not promote on top of it', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.platform.reports = 40;
      await f.rollout.advance(now: at(1));
      expect(f.platform.routed, <int>[5]);
      expect(f.health.asked, isEmpty);
      expect(f.rollout.events.last.kind, DVRolloutEventKind.held);
      expect(f.rollout.events.last.reasons.single, contains('40'));
      f.platform.reports = null;
      await f.rollout.advance(now: at(2));
      expect(f.platform.routed, <int>[5, 25]);
    });

    test('a weight the platform cannot report holds', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.platform.readable = false;
      await f.rollout.advance(now: at(1));
      expect(f.platform.routed, <int>[5]);
      expect(f.health.asked, isEmpty);
    });

    test('a route the platform refuses leaves the planned weight where it was',
        () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.platform.failRoutes = 1;
      await f.rollout.advance(now: at(1));
      expect(f.rollout.state, DVRolloutState.stepping);
      expect(f.rollout.percent, 5);
      expect(f.rollout.events.last.kind, DVRolloutEventKind.routeFailed);
      await f.rollout.advance(now: at(2));
      expect(f.platform.routed, <int>[5, 25]);
      expect(f.rollout.percent, 25);
    });
  });

  group('rolling back', () {
    test('a tripped gate routes everything back, reports DV-RELEASE-001, and '
        'leaves the history on the previous release', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      await f.rollout.advance(now: at(1));
      f.health.rollBack('stage 17 failures');
      expect(await f.rollout.advance(now: at(2)), DVRolloutState.rolledBack);
      expect(f.platform.routed, <int>[5, 25, 0]);
      expect(f.codes, contains('DV-RELEASE-001'));
      expect(f.history.current!.id, 'r1');
      await f.rollout.advance(now: at(5));
      expect(f.platform.routed, <int>[5, 25, 0]);
    });

    test('a roll back whose route fails is not reported as done, and is '
        'retried', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.health.rollBack('regressed');
      f.platform.failRoutes = 1;
      expect(await f.rollout.advance(now: at(1)), DVRolloutState.rollingBack);
      expect(f.codes, isNot(contains('DV-RELEASE-001')));
      expect(await f.rollout.advance(now: at(1, 1)), DVRolloutState.rolledBack);
      expect(f.platform.routed, <int>[5, 0]);
      expect(f.codes, contains('DV-RELEASE-001'));
    });

    test('a roll back the platform does not confirm stays rolling back',
        () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.health.rollBack('regressed');
      f.platform.reports = 5;
      expect(await f.rollout.advance(now: at(1)), DVRolloutState.rollingBack);
      f.platform.reports = null;
      expect(await f.rollout.advance(now: at(1, 1)), DVRolloutState.rolledBack);
    });

    test('blue-green on a platform that cannot weight switches all traffic, '
        'watches it, and switches back', () async {
      final _Fixture f = _Fixture(canWeight: false);
      await f.rollout.start(now: t0);
      expect(f.platform.routed, <int>[100]);
      f.health.rollBack('regressed');
      await f.rollout.advance(now: at(1));
      expect(f.platform.routed, <int>[100, 0]);
      expect(f.rollout.state, DVRolloutState.rolledBack);
    });
  });

  group('staged flags', () {
    test('a hold naming flags turns them off once', () async {
      final _Fixture f = _Fixture();
      await f.rollout.start(now: t0);
      f.health.holdWith('crash-free sessions fell', flags: <String>['newCheckout']);
      await f.rollout.advance(now: at(1));
      await f.rollout.advance(now: at(2));
      expect(f.turnedOff, <List<String>>[
        <String>['newCheckout'],
      ]);
    });

    test('turning a flag off is a rule every context reads as off, and '
        'leaves the other flags alone', () {
      final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
        key: 'newCheckout',
        defaultValue: true,
        owner: 'payments',
        expires: DateTime.utc(2027),
      );
      final DVFeatureFlag<bool> darkMode = DVFeatureFlag<bool>(
        key: 'darkMode',
        defaultValue: false,
        owner: 'design',
        expires: DateTime.utc(2027),
      );
      final DVFlagRules before = const DVFlagRules(
        rulesVersion: 7,
        flags: <String, List<DVFlagRule>>{
          'newCheckout': <DVFlagRule>[DVFlagRule(value: true)],
          'darkMode': <DVFlagRule>[DVFlagRule(value: true)],
        },
      );
      final DVFlagRules after = DVReleaseFlags.turnOff(before, <String>[
        'newCheckout',
      ]);
      expect(after.rulesVersion, 8);
      expect(
        DVFlags.evaluate(newCheckout, after, const DVFlagContext()).value,
        isFalse,
      );
      expect(
        DVFlags.evaluate(darkMode, after, const DVFlagContext()).value,
        isTrue,
      );
      // With no rule set synced yet, the flag is still turned off rather than
      // falling to a compiled default that says on.
      expect(
        DVFlags.evaluate(
          newCheckout,
          DVReleaseFlags.turnOff(null, <String>['newCheckout']),
          const DVFlagContext(),
        ).value,
        isFalse,
      );
    });
  });
}

class _NamedPlatform extends _Platform {
  _NamedPlatform(this._name) : super(canWeightTraffic: true);

  final String _name;

  @override
  String get name => _name;
}
