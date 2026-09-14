// The gates a rollout passes, holds or rolls back on, composed.
//
// Every failure worth testing here is a rollout that proceeds. A health gate
// whose traffic source returned nothing, read as no failures. A first deploy
// with nothing to compare against, read as a pass. A stage the source forgot
// to report, read as zero refusals. An error budget with no samples, read as
// unspent. A gate that never answers, so the rollout neither moves nor says
// why. And an override with no reason, which is a hold switched off quietly.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 11, 14);
final DateTime t1 = t0.add(const Duration(minutes: 10));

DVReleaseRecord record(String id, {int protocol = 3}) => DVReleaseRecord(
  id: id,
  commit: 'commit-$id',
  artifact: 'sha256:$id',
  protocolVersion: protocol,
  migrationPlan: null,
  releasedBy: 'daniel',
  releasedAt: t0,
);

const Map<DVRequestStage, int> quietStages = <DVRequestStage, int>{
  DVRequestStage.commit: 0,
  DVRequestStage.authorization: 0,
};

DVReleaseTraffic traffic({
  int requests = 10000,
  int failed = 10,
  Map<DVRequestStage, int> stages = quietStages,
  Duration? p95 = const Duration(milliseconds: 100),
}) => DVReleaseTraffic(
  requests: requests,
  failed: failed,
  stageFailures: stages,
  latencyP95: p95,
);

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
}

DVReleaseGateContext promotion({
  DVReleaseRecord? previous,
  bool noPrevious = false,
}) => DVReleaseGateContext(
  candidate: record('r2'),
  previous: noPrevious ? null : (previous ?? record('r1')),
  phase: DVReleasePhase.beforePromotion,
  percent: 5,
  stepStartedAt: t0,
  now: t1,
);

DVHealthComparisonGate healthGate(
  Map<String, DVReleaseTraffic?> byRelease, {
  _Diagnostics? diagnostics,
  List<(String, DateTime, DateTime)>? reads,
}) => DVHealthComparisonGate(
  thresholds: const DVReleaseThresholds(),
  source: (String release, DateTime since, DateTime until) {
    reads?.add((release, since, until));
    return byRelease[release];
  },
  onDiagnostic: (diagnostics ?? _Diagnostics()).call,
);

class _Gate implements DVReleaseGate {
  _Gate(this.name, this.answer, {Set<DVReleasePhase>? phases})
    : phases = phases ?? DVReleasePhase.values.toSet();

  @override
  final String name;

  @override
  final Set<DVReleasePhase> phases;

  final FutureOr<DVGateOutcome> Function(DVReleaseGateContext) answer;

  @override
  FutureOr<DVGateOutcome> evaluate(DVReleaseGateContext context) =>
      answer(context);
}

void main() {
  group('the health gate compares against the release being replaced', () {
    test('a candidate within every margin passes', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(),
        'r2': traffic(failed: 20),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.pass);
    });

    test('both releases are read over the step being watched', () async {
      final List<(String, DateTime, DateTime)> reads =
          <(String, DateTime, DateTime)>[];
      await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(),
        'r2': traffic(),
      }, reads: reads).evaluate(promotion());
      expect(reads, containsAll(<(String, DateTime, DateTime)>[
        ('r1', t0, t1),
        ('r2', t0, t1),
      ]));
    });

    test('an error rate over the margin rolls back', () async {
      // Previous 0.1%, candidate 1.2%: 1.1 points over a 1-point margin.
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(failed: 10),
        'r2': traffic(failed: 120),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.rollBack);
      expect(outcome.reason, contains('error rate'));
    });

    test('the margin is relative: a high rate the previous release also had '
        'is not a regression', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(failed: 500),
        'r2': traffic(failed: 550),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.pass);
    });

    test('a failure has a place: commit failures at stage 17 roll back while '
        'the overall rate is within its margin', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(failed: 10),
        'r2': traffic(
          failed: 30,
          stages: <DVRequestStage, int>{
            DVRequestStage.commit: 20, // 0.2% against a 0.1-point margin
            DVRequestStage.authorization: 0,
          },
        ),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.rollBack);
      expect(outcome.reason, contains('stage 17'));
    });

    test('p95 latency beyond its increase rolls back', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(p95: const Duration(milliseconds: 100)),
        'r2': traffic(p95: const Duration(milliseconds: 121)),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.rollBack);
      expect(outcome.reason, contains('p95'));
    });

    test('a first deploy holds with DV-RELEASE-003 rather than passing '
        'vacuously', () async {
      final _Diagnostics diagnostics = _Diagnostics();
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r2': traffic(),
      }, diagnostics: diagnostics).evaluate(promotion(noPrevious: true));
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.code, 'DV-RELEASE-003');
      expect(diagnostics.codes, <String>['DV-RELEASE-003']);
    });

    test('a source that returns nothing holds; it is not a clean release',
        () async {
      for (final Map<String, DVReleaseTraffic?> data
          in <Map<String, DVReleaseTraffic?>>[
            <String, DVReleaseTraffic?>{'r1': traffic(), 'r2': null},
            <String, DVReleaseTraffic?>{'r1': null, 'r2': traffic()},
          ]) {
        final DVGateOutcome outcome = await healthGate(
          data,
        ).evaluate(promotion());
        expect(outcome.verdict, DVGateVerdict.hold, reason: '$data');
      }
    });

    test('a source that throws holds', () async {
      final DVGateOutcome outcome = await DVHealthComparisonGate(
        thresholds: const DVReleaseThresholds(),
        source: (String release, DateTime since, DateTime until) =>
            throw StateError('monitoring unreachable'),
        onDiagnostic: (_, _) {},
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.reason, contains('monitoring unreachable'));
    });

    test('a candidate that has served no requests holds', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(),
        'r2': traffic(requests: 0, failed: 0),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('a declared stage the source did not report holds, rather than '
        'reading as zero failures', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(),
        'r2': traffic(
          stages: const <DVRequestStage, int>{DVRequestStage.authorization: 0},
        ),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.reason, contains('stage 17'));
    });

    test('missing latency holds while a latency margin is declared', () async {
      final DVGateOutcome outcome = await healthGate(<String, DVReleaseTraffic>{
        'r1': traffic(),
        'r2': traffic(p95: null),
      }).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('impossible counts are refused', () {
      expect(
        () => DVReleaseTraffic(requests: 5, failed: 6, stageFailures: const {}),
        throwsArgumentError,
      );
      expect(
        () => DVReleaseTraffic(requests: -1, failed: 0, stageFailures: const {}),
        throwsArgumentError,
      );
    });
  });

  group('the existing gates, as release gates', () {
    test('an exhausted error budget holds', () async {
      final DVServiceLevels levels = DVServiceLevels(onDiagnostic: (_, _) {});
      const DVAppliesTo checkout = DVAppliesTo.backendFunction('checkout');
      levels.add(
        const DVServiceLevel(
          name: 'checkout',
          objective: DVObjective.successRate(0.999, over: Duration(hours: 1)),
          applies: checkout,
        ),
      );
      int total = 0;
      int failed = 0;
      levels.source(
        checkout,
        () => DVServiceLevelCounts(total: total, failed: failed),
      );
      levels.sample(t0.subtract(const Duration(hours: 1)));
      total = 1000;
      failed = 500;
      levels.sample(t1);
      final DVGateOutcome outcome = await DVErrorBudgetReleaseGate(
        DVErrorBudgetGate(levels),
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.reason, contains('checkout'));
    });

    test('an error budget with no samples holds, rather than reading as '
        'unspent', () async {
      final DVServiceLevels levels = DVServiceLevels(onDiagnostic: (_, _) {});
      levels.add(
        const DVServiceLevel(
          name: 'checkout',
          objective: DVObjective.successRate(0.999, over: Duration(hours: 1)),
          applies: DVAppliesTo.backendFunction('checkout'),
        ),
      );
      final DVGateOutcome outcome = await DVErrorBudgetReleaseGate(
        DVErrorBudgetGate(levels),
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('an error budget gate with no service levels holds', () async {
      final DVGateOutcome outcome = await DVErrorBudgetReleaseGate(
        DVErrorBudgetGate(DVServiceLevels(onDiagnostic: (_, _) {})),
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('crash health below threshold holds and names the flags to turn off',
        () async {
      final DVReleaseHealth health = DVReleaseHealth();
      for (int i = 0; i < 10; i++) {
        health.sessionStarted(
          sessionId: 's$i',
          installId: 'i$i',
          release: 'r2',
        );
      }
      health.sessionCrashed(sessionId: 's0');
      health.sessionCrashed(sessionId: 's1');
      final DVGateOutcome outcome = await DVCrashHealthReleaseGate(
        gate: DVReleaseHealthGate(
          crashFreeSessions: 0.99,
          minimumSessions: 5,
          stagedFlags: const <String>['newCheckout'],
          onDiagnostic: (_, _) {},
        ),
        health: health,
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.flagsToTurnOff, <String>['newCheckout']);
    });

    test('crash health with fewer sessions than the gate reads holds', () async {
      // DVReleaseHealthGate does not read below its minimum, which is right
      // for a number and wrong for a rollout: too few sessions is no evidence.
      final DVReleaseHealth health = DVReleaseHealth()
        ..sessionStarted(sessionId: 's0', installId: 'i0', release: 'r2');
      final DVGateOutcome outcome = await DVCrashHealthReleaseGate(
        gate: DVReleaseHealthGate(
          crashFreeSessions: 0.99,
          minimumSessions: 5,
          onDiagnostic: (_, _) {},
        ),
        health: health,
      ).evaluate(promotion());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    DVProtocolLock lock(int protocol) {
      const DVProtocolContract contract = DVProtocolContract();
      return DVProtocolLock(<DVProtocolRelease>[
        for (int p = 1; p <= protocol; p++)
          DVProtocolRelease(
            protocol: p,
            shape: contract.shape,
            released: DateTime.utc(2025, p),
            contract: contract,
          ),
      ]);
    }

    DVReleaseGateContext beforeDeploy({int protocol = 5}) =>
        DVReleaseGateContext(
          candidate: record('r2', protocol: protocol),
          previous: record('r1', protocol: protocol - 1),
          phase: DVReleasePhase.beforeDeploy,
          percent: 0,
          stepStartedAt: t0,
          now: t0,
        );

    test('the protocol gate holds a deploy that strands clients, with the '
        'histogram as evidence', () async {
      final DVGateOutcome outcome = await DVProtocolReleaseGate(
        lock: lock(5),
        window: const DVProtocolWindow(versions: 1, minimumAge: Duration.zero),
        samples: () => <DVProtocolSessionSample>[
          DVProtocolSessionSample(protocol: 1, day: t0, sessions: 500),
          DVProtocolSessionSample(protocol: 5, day: t0, sessions: 500),
        ],
        onDiagnostic: (_, _) {},
      ).evaluate(beforeDeploy());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.code, 'DV-PROTO-005');
      expect(outcome.evidence['histogram'], <String, int>{'1': 500, '5': 500});
    });

    test('the protocol gate holds on an empty histogram', () async {
      final DVGateOutcome outcome = await DVProtocolReleaseGate(
        lock: lock(5),
        samples: () => const <DVProtocolSessionSample>[],
        onDiagnostic: (_, _) {},
      ).evaluate(beforeDeploy());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('the protocol gate holds when the lock is not the release it is '
        'asked about', () async {
      final DVGateOutcome outcome = await DVProtocolReleaseGate(
        lock: lock(4),
        samples: () => <DVProtocolSessionSample>[
          DVProtocolSessionSample(protocol: 4, day: t0, sessions: 500),
        ],
        onDiagnostic: (_, _) {},
      ).evaluate(beforeDeploy(protocol: 5));
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('the schema gate holds a blocking change going to production', () async {
      final DVSchemaPlan plan = await const DVSchemaPlanner().plan(
        const <DVSchemaChange>[DVAddColumn('orders', 'note', nullable: false)],
        const DVPostgresSchemaRules(DVDatabaseServerVersion(16)),
      );
      final DVGateOutcome outcome = await DVSchemaReleaseGate(
        plan: plan,
      ).evaluate(beforeDeploy());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.code, 'DV-SCHEMA-002');
      expect(outcome.evidence['changes'], isNotEmpty);
    });
  });

  group('composing gates', () {
    test('every gate for the phase is read, and a pass needs all of them',
        () async {
      final List<String> read = <String>[];
      final DVReleaseGates gates = DVReleaseGates(<DVReleaseGate>[
        _Gate('a', (DVReleaseGateContext c) {
          read.add('a');
          return const DVGateOutcome.pass('a');
        }),
        _Gate('b', (DVReleaseGateContext c) {
          read.add('b');
          return const DVGateOutcome.hold('b', 'not yet');
        }),
        _Gate(
          'deploy-only',
          (DVReleaseGateContext c) {
            read.add('deploy-only');
            return const DVGateOutcome.pass('deploy-only');
          },
          phases: <DVReleasePhase>{DVReleasePhase.beforeDeploy},
        ),
      ]);
      final DVGateDecision decision = await gates.evaluate(promotion());
      expect(read, <String>['a', 'b']);
      expect(decision.verdict, DVGateVerdict.hold);
      expect(decision.proceed, isFalse);
    });

    test('a roll back anywhere is a roll back, whatever else passed', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate('a', (_) => const DVGateOutcome.hold('a', 'waiting')),
        _Gate('b', (_) => const DVGateOutcome.rollBack('b', 'regressed')),
      ]).evaluate(promotion());
      expect(decision.verdict, DVGateVerdict.rollBack);
    });

    test('no gate for the phase holds: nothing was checked', () async {
      final DVGateDecision decision = await DVReleaseGates(
        <DVReleaseGate>[],
      ).evaluate(promotion());
      expect(decision.verdict, DVGateVerdict.hold);
    });

    test('a gate that throws holds, naming the gate', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate('flaky', (_) => throw StateError('boom')),
      ]).evaluate(promotion());
      expect(decision.verdict, DVGateVerdict.hold);
      expect(decision.outcomes.single.reason, contains('flaky'));
    });

    test('a gate that never answers holds after its timeout', () async {
      final DVGateDecision decision = await DVReleaseGates(
        <DVReleaseGate>[
          _Gate('stuck', (_) => Completer<DVGateOutcome>().future),
        ],
        timeout: const Duration(milliseconds: 50),
      ).evaluate(promotion()).timeout(const Duration(seconds: 5));
      expect(decision.verdict, DVGateVerdict.hold);
      expect(decision.outcomes.single.reason, contains('stuck'));
    });

    test('a gate answering under another name is refused', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate('a', (_) => const DVGateOutcome.pass('b')),
      ]).evaluate(promotion());
      expect(decision.verdict, DVGateVerdict.hold);
    });

    test('an override lets a hold through and is recorded with its reason, '
        'who, when and what it overrode', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate(
          'protocol',
          (_) => const DVGateOutcome.hold(
            'protocol',
            'strands protocol 1',
            code: 'DV-PROTO-005',
            evidence: <String, Object?>{'histogram': <String, int>{'1': 9}},
          ),
        ),
        _Gate('health', (_) => const DVGateOutcome.pass('health')),
      ]).evaluate(
        promotion(),
        overrides: <DVGateOverride>[
          DVGateOverride(
            gate: 'protocol',
            reason: 'protocol 1 is the kiosk fleet, patched tonight',
            by: 'daniel',
            at: t1,
          ),
        ],
      );
      expect(decision.verdict, DVGateVerdict.pass);
      final DVGateOverrideRecord used = decision.overrides.single;
      expect(used.gate, 'protocol');
      expect(used.code, 'DV-PROTO-005');
      expect(used.reason, 'protocol 1 is the kiosk fleet, patched tonight');
      expect(used.by, 'daniel');
      expect(used.at, t1);
      expect(used.overrode, 'strands protocol 1');
      expect(used.toJson()['evidence'], <String, Object?>{
        'histogram': <String, int>{'1': 9},
      });
    });

    test('an override does not reverse a roll back', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate('health', (_) => const DVGateOutcome.rollBack('health', 'regressed')),
      ]).evaluate(
        promotion(),
        overrides: <DVGateOverride>[
          DVGateOverride(gate: 'health', reason: 'ship it', by: 'd', at: t1),
        ],
      );
      expect(decision.verdict, DVGateVerdict.rollBack);
      expect(decision.overrides, isEmpty);
    });

    test('an override for a gate that did not hold is not recorded as used',
        () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate('health', (_) => const DVGateOutcome.pass('health')),
      ]).evaluate(
        promotion(),
        overrides: <DVGateOverride>[
          DVGateOverride(gate: 'health', reason: 'just in case', by: 'd', at: t1),
        ],
      );
      expect(decision.verdict, DVGateVerdict.pass);
      expect(decision.overrides, isEmpty);
    });

    test('a hold marked not overridable stays held under an override', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        _Gate(
          'contract',
          (_) => const DVGateOutcome.hold('contract', 'drops a read column',
              overridable: false),
        ),
      ]).evaluate(
        promotion(),
        overrides: <DVGateOverride>[
          DVGateOverride(gate: 'contract', reason: 'sure', by: 'd', at: t1),
        ],
      );
      expect(decision.verdict, DVGateVerdict.hold);
      expect(decision.overrides, isEmpty);
    });

    test('an override with no reason or no author cannot be made', () {
      for (final (String reason, String by) in <(String, String)>[
        ('', 'daniel'),
        ('   ', 'daniel'),
        ('a reason', ''),
      ]) {
        expect(
          () => DVGateOverride(gate: 'protocol', reason: reason, by: by, at: t1),
          throwsArgumentError,
          reason: '"$reason" by "$by"',
        );
      }
    });

    test('flags come from the gates that stopped the rollout, not from one '
        'that was overridden', () async {
      final DVGateDecision held = await DVReleaseGates(<DVReleaseGate>[
        _Gate(
          'crashes',
          (_) => const DVGateOutcome.hold('crashes', 'crashing',
              flagsToTurnOff: <String>['newCheckout']),
        ),
      ]).evaluate(promotion());
      expect(held.flagsToTurnOff, <String>['newCheckout']);

      final DVGateDecision overridden = await DVReleaseGates(<DVReleaseGate>[
        _Gate(
          'crashes',
          (_) => const DVGateOutcome.hold('crashes', 'crashing',
              flagsToTurnOff: <String>['newCheckout']),
        ),
      ]).evaluate(
        promotion(),
        overrides: <DVGateOverride>[
          DVGateOverride(gate: 'crashes', reason: 'known crash', by: 'd', at: t1),
        ],
      );
      expect(overridden.flagsToTurnOff, isEmpty);
    });
  });
}
