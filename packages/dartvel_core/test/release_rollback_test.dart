// Rollback planning, and the contract step it has to respect.
//
// Rollback is the release's undo, and data has none. The quiet failures: a
// rollback onto a release that reads a column a contract step has already
// dropped, which looks fine until its first query; a schema phase that could
// not be read, taken as safe; a rollback across a protocol bump that strands
// every client which already upgraded; a rollback of one function, leaving a
// fleet that answers one client two ways; and a contract step that runs while
// a client inside the window still reads what it drops.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1, 12);
const Duration day = Duration(days: 1);

const String migration = 'orders.total';

DVReleaseRecord record(
  String id, {
  int protocol = 3,
  Map<String, DVReleaseMigrationPhase> schema =
      const <String, DVReleaseMigrationPhase>{},
  Set<String> functions = const <String>{'checkout', 'refund'},
}) => DVReleaseRecord(
  id: id,
  commit: 'commit-$id',
  artifact: 'sha256:$id',
  protocolVersion: protocol,
  migrationPlan: schema.isEmpty ? null : 'plan-$id',
  releasedBy: 'daniel',
  releasedAt: t0,
  functions: functions,
  schema: schema,
);

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
}

DVReleaseMigrationPhase? Function(String) live(
  Map<String, DVReleaseMigrationPhase?> phases,
) =>
    (String m) => phases[m];

DVProtocolContract contractReading({required bool total}) => DVProtocolContract(
  models: <DVProtocolModel>[
    DVProtocolModel('Order', <DVProtocolField>[
      const DVProtocolField('id', 'String'),
      if (total) const DVProtocolField('total', 'int'),
      const DVProtocolField('totalCents', 'int?'),
    ]),
  ],
);

DVProtocolLock lockUpTo(int protocol, {int readsTotalUntil = 99}) =>
    DVProtocolLock(<DVProtocolRelease>[
      for (int p = 1; p <= protocol; p++)
        DVProtocolRelease(
          protocol: p,
          shape: contractReading(total: p <= readsTotalUntil).shape,
          // Every version released in the past, in order. A version released
          // at or after `now` makes its predecessor superseded zero days ago,
          // which a window keeps by age.
          released: t0.subtract(day * (100 * (10 - p))),
          contract: contractReading(total: p <= readsTotalUntil),
        ),
    ]);

/// r1 (protocol 3), r2 (protocol 3), r3 (protocol 4), r3 serving.
DVReleaseHistory threeReleases({
  Map<String, DVReleaseMigrationPhase> r1Schema =
      const <String, DVReleaseMigrationPhase>{},
  Map<String, DVReleaseMigrationPhase> r2Schema =
      const <String, DVReleaseMigrationPhase>{},
  Map<String, DVReleaseMigrationPhase> r3Schema =
      const <String, DVReleaseMigrationPhase>{},
  bool r2HasRecord = true,
  int r2Protocol = 4,
}) => DVReleaseHistory(onDiagnostic: (_, _) {})
  ..deployed('r1', provenance: record('r1', schema: r1Schema), at: t0)
  ..deployed(
    'r2',
    provenance: r2HasRecord
        ? record('r2', protocol: r2Protocol, schema: r2Schema)
        : null,
    at: t0.add(day),
  )
  ..deployed(
    'r3',
    provenance: record('r3', protocol: 4, schema: r3Schema),
    at: t0.add(day * 2),
  );

class _Platform implements DVReleaseAdapter {
  final List<(String, String?, int)> routed = <(String, String?, int)>[];
  final Map<String, int> weights = <String, int>{};
  bool confirm = true;

  @override
  String get name => 'fake-platform';

  @override
  bool get canWeightTraffic => true;

  @override
  Future<void> route({
    required String candidate,
    required String? previous,
    required int percent,
  }) async {
    routed.add((candidate, previous, percent));
    weights[candidate] = percent;
  }

  @override
  Future<int?> weightOf(String release) async =>
      confirm ? weights[release] : 0;
}

Future<DVRollbackPlan> plan(
  DVReleaseHistory history, {
  DVRollbackTarget target = const DVRollbackTarget.previous(),
  String? function,
  Map<String, DVReleaseMigrationPhase?> schema =
      const <String, DVReleaseMigrationPhase?>{},
  DVProtocolLock? lock,
  List<DVProtocolSessionSample>? samples,
  DVGateOverride? protocolOverride,
  _Diagnostics? diagnostics,
}) => DVRollbackPlanner.plan(
  history: history,
  target: target,
  function: function,
  schema: live(schema),
  lock: lock,
  window: const DVProtocolWindow(versions: 0, minimumAge: Duration.zero),
  samples: samples == null ? null : () => samples,
  protocolOverride: protocolOverride,
  now: t0.add(day * 3),
  onDiagnostic: (diagnostics ?? _Diagnostics()).call,
);

void main() {
  group('choosing what to roll back to', () {
    test('by default, the previous release', () async {
      final DVRollbackPlan p = await plan(threeReleases());
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
      expect(p.from!.id, 'r3');
      expect(p.to!.id, 'r2');
    });

    test('--to a moment restores the release serving then', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(),
        target: DVRollbackTarget.at(t0.add(const Duration(hours: 5))),
        lock: lockUpTo(4),
        samples: <DVProtocolSessionSample>[
          DVProtocolSessionSample(protocol: 3, day: t0.add(day * 2), sessions: 100),
        ],
      );
      expect(p.to!.id, 'r1');
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
    });

    test('--to a release name restores that release', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(),
        target: const DVRollbackTarget.release('r2'),
      );
      expect(p.to!.id, 'r2');
    });

    test('a moment before anything was deployed is refused', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(),
        target: DVRollbackTarget.at(t0.subtract(day)),
      );
      expect(p.allowed, isFalse);
      expect(p.to, isNull);
    });

    test('rolling back one function is refused with DV-RELEASE-004, naming '
        'the release to roll back instead', () async {
      final _Diagnostics diagnostics = _Diagnostics();
      final DVRollbackPlan p = await plan(
        threeReleases(),
        function: 'checkout',
        diagnostics: diagnostics,
      );
      expect(p.allowed, isFalse);
      expect(diagnostics.codes, contains('DV-RELEASE-004'));
      expect(p.findings.map((DVReleaseFinding f) => f.code),
          contains('DV-RELEASE-004'));
      expect(p.refusals.single, contains('r3'));
    });

    test('a release with no provenance record cannot be named: DV-RELEASE-006',
        () async {
      final _Diagnostics diagnostics = _Diagnostics();
      final DVRollbackPlan p = await plan(
        threeReleases(r2HasRecord: false),
        diagnostics: diagnostics,
      );
      expect(p.allowed, isFalse);
      expect(diagnostics.codes, contains('DV-RELEASE-006'));
      // Not skipped over to r1: that is further back than anybody asked.
      expect(p.to!.id, 'r2');
    });

    test('a release a rollback took away is not restored by naming it', () async {
      final DVReleaseHistory history = threeReleases()
        ..rolledBack(to: 'r2', at: t0.add(day * 3));
      final DVRollbackPlan p = await DVRollbackPlanner.plan(
        history: history,
        target: const DVRollbackTarget.release('r3'),
        schema: live(const <String, DVReleaseMigrationPhase?>{}),
        now: t0.add(day * 4),
        onDiagnostic: (_, _) {},
      );
      expect(p.allowed, isFalse);
    });

    test('nothing deployed is nothing to roll back', () async {
      final DVRollbackPlan p = await DVRollbackPlanner.plan(
        history: DVReleaseHistory(onDiagnostic: (_, _) {}),
        schema: live(const <String, DVReleaseMigrationPhase?>{}),
        now: t0,
        onDiagnostic: (_, _) {},
      );
      expect(p.allowed, isFalse);
    });
  });

  group('the schema a rollback lands on', () {
    test('a contracted migration refuses a target that predates it', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.contracted,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.contracted,
        },
      );
      expect(p.allowed, isFalse);
      expect(p.refusals.single, contains(migration));
    });

    test('a contracted migration refuses a target that still dual-writes the '
        'dropped shape', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r2Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.readSwitched,
          },
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.contracted,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.contracted,
        },
      );
      expect(p.allowed, isFalse);
    });

    test('a phase that cannot be read refuses, rather than being taken as '
        'safe', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.contracted,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{migration: null},
      );
      expect(p.allowed, isFalse);
    });

    test('a source that throws refuses', () async {
      final DVRollbackPlan p = await DVRollbackPlanner.plan(
        history: threeReleases(
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.expanded,
          },
        ),
        schema: (String m) => throw StateError('database unreachable'),
        now: t0.add(day * 3),
        onDiagnostic: (_, _) {},
      );
      expect(p.allowed, isFalse);
      expect(p.refusals.single, contains('database unreachable'));
    });

    test('an expanded migration does not stop a rollback: the old shape still '
        'reads', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.expanded,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.expanded,
        },
      );
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
      expect(p.reverify, isEmpty);
    });

    test('a backfilled migration under a target that does not dual-write is '
        'allowed, and its backfill has to be verified again', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.verified,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.verified,
        },
      );
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
      expect(p.reverify, <String>[migration]);
    });

    test('a target that dual-writes keeps the backfill good', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r2Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.dualWriting,
          },
          r3Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.readSwitched,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.readSwitched,
        },
      );
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
      expect(p.reverify, isEmpty);
    });

    test('a target built for a schema further along than the database is '
        'refused', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(
          r2Schema: const <String, DVReleaseMigrationPhase>{
            migration: DVReleaseMigrationPhase.backfilled,
          },
        ),
        schema: const <String, DVReleaseMigrationPhase?>{
          migration: DVReleaseMigrationPhase.expanded,
        },
      );
      expect(p.allowed, isFalse);
    });
  });

  group('the clients a rollback would strand', () {
    final List<DVProtocolSessionSample> upgraded = <DVProtocolSessionSample>[
      DVProtocolSessionSample(protocol: 3, day: t0.add(day * 2), sessions: 100),
      DVProtocolSessionSample(protocol: 4, day: t0.add(day * 2), sessions: 900),
    ];

    test('crossing back over a protocol bump that clients have taken is '
        'refused with the histogram', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(r2Protocol: 3),
        lock: lockUpTo(4),
        samples: upgraded,
      );
      expect(p.allowed, isFalse);
      expect(p.findings, isEmpty);
      expect(p.refusals.single, contains('protocol 4'));
    });

    test('an override with a reason lets it through and is recorded', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(r2Protocol: 3),
        lock: lockUpTo(4),
        samples: upgraded,
        protocolOverride: DVGateOverride(
          gate: 'protocol',
          reason: 'protocol 4 clients are internal testers',
          by: 'daniel',
          at: t0.add(day * 3),
        ),
      );
      expect(p.allowed, isTrue, reason: p.refusals.join('; '));
      expect(p.overrides.single.reason, 'protocol 4 clients are internal testers');
      expect(p.overrides.single.evidence['histogram'], <String, int>{
        '3': 100,
        '4': 900,
      });
    });

    test('an empty histogram is refused', () async {
      final DVRollbackPlan p = await plan(
        threeReleases(r2Protocol: 3),
        lock: lockUpTo(4),
        samples: const <DVProtocolSessionSample>[],
      );
      expect(p.allowed, isFalse);
    });

    test('crossing a protocol with no lock or histogram to check is refused',
        () async {
      expect((await plan(threeReleases(r2Protocol: 3))).allowed, isFalse);
      expect(
        (await plan(threeReleases(r2Protocol: 3), lock: lockUpTo(4))).allowed,
        isFalse,
      );
    });

    test('the same protocol needs no histogram', () async {
      expect((await plan(threeReleases(r2Protocol: 4))).allowed, isTrue);
    });
  });

  group('executing a rollback', () {
    test('routes the target back in, confirms it, and records it', () async {
      final DVReleaseHistory history = threeReleases();
      final DVRollbackPlan p = await plan(history);
      final _Platform platform = _Platform();
      final bool done = await DVReleaseRollback.execute(
        p,
        adapter: platform,
        history: history,
        now: t0.add(day * 3),
      );
      expect(done, isTrue);
      expect(platform.routed.single, ('r2', 'r3', 100));
      expect(history.current!.id, 'r2');
      expect(history.previous()!.id, 'r1');
    });

    test('a refused plan is not executed', () async {
      final DVReleaseHistory history = threeReleases();
      final DVRollbackPlan p = await plan(history, function: 'checkout');
      final _Platform platform = _Platform();
      await expectLater(
        DVReleaseRollback.execute(
          p,
          adapter: platform,
          history: history,
          now: t0.add(day * 3),
        ),
        throwsStateError,
      );
      expect(platform.routed, isEmpty);
    });

    test('a rollback the platform does not confirm is not recorded', () async {
      final DVReleaseHistory history = threeReleases();
      final DVRollbackPlan p = await plan(history);
      final _Platform platform = _Platform()..confirm = false;
      final bool done = await DVReleaseRollback.execute(
        p,
        adapter: platform,
        history: history,
        now: t0.add(day * 3),
      );
      expect(done, isFalse);
      expect(history.current!.id, 'r3');
    });

    test('a plan made against an older history is not executed', () async {
      final DVReleaseHistory history = threeReleases();
      final DVRollbackPlan p = await plan(history);
      history.deployed('r4', provenance: record('r4', protocol: 4), at: t0.add(day * 3));
      await expectLater(
        DVReleaseRollback.execute(
          p,
          adapter: _Platform(),
          history: history,
          now: t0.add(day * 4),
        ),
        throwsStateError,
      );
    });
  });

  group('the contract step', () {
    DVReleaseGateContext contracting({
      DVReleaseMigrationPhase? previousPhase =
          DVReleaseMigrationPhase.readSwitched,
      int protocol = 5,
    }) => DVReleaseGateContext(
      candidate: record(
        'r5',
        protocol: protocol,
        schema: const <String, DVReleaseMigrationPhase>{
          migration: DVReleaseMigrationPhase.contracted,
        },
      ),
      previous: record(
        'r4',
        protocol: protocol,
        schema: <String, DVReleaseMigrationPhase>{
          if (previousPhase != null) migration: previousPhase,
        },
      ),
      phase: DVReleasePhase.beforeDeploy,
      percent: 0,
      stepStartedAt: t0,
      now: t0,
    );

    DVContractStepGate gate(DVProtocolLock lock, [_Diagnostics? d]) =>
        DVContractStepGate(
          migration: migration,
          drops: const <DVContractDrop>[DVContractDrop.field('Order', 'total')],
          lock: lock,
          window: const DVProtocolWindow(versions: 1, minimumAge: Duration.zero),
          onDiagnostic: (d ?? _Diagnostics()).call,
        );

    test('refused with DV-RELEASE-005 while a windowed client reads what it '
        'drops', () async {
      final _Diagnostics diagnostics = _Diagnostics();
      // Protocols 4 and 5 are in the window; 4 still reads Order.total.
      final DVGateOutcome outcome = await gate(
        lockUpTo(5, readsTotalUntil: 4),
        diagnostics,
      ).evaluate(contracting());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.code, 'DV-RELEASE-005');
      expect(outcome.overridable, isFalse);
      expect(outcome.reason, contains('protocol 4'));
      expect(diagnostics.codes, <String>['DV-RELEASE-005']);
    });

    test('an override does not let it through', () async {
      final DVGateDecision decision = await DVReleaseGates(<DVReleaseGate>[
        gate(lockUpTo(5, readsTotalUntil: 4)),
      ]).evaluate(
        contracting(),
        overrides: <DVGateOverride>[
          DVGateOverride(
            gate: 'contract:$migration',
            reason: 'nobody uses protocol 4',
            by: 'daniel',
            at: t0,
          ),
        ],
      );
      expect(decision.verdict, DVGateVerdict.hold);
    });

    test('allowed once no windowed client reads it and the previous release '
        'reads the new shape', () async {
      final DVGateOutcome outcome = await gate(
        lockUpTo(5, readsTotalUntil: 3),
      ).evaluate(contracting());
      expect(outcome.verdict, DVGateVerdict.pass, reason: outcome.reason);
    });

    test('refused while the release being replaced still reads the old shape',
        () async {
      for (final DVReleaseMigrationPhase? phase in <DVReleaseMigrationPhase?>[
        null,
        DVReleaseMigrationPhase.verified,
      ]) {
        final DVGateOutcome outcome = await gate(
          lockUpTo(5, readsTotalUntil: 3),
        ).evaluate(contracting(previousPhase: phase));
        expect(outcome.verdict, DVGateVerdict.hold, reason: '$phase');
        expect(outcome.overridable, isFalse);
      }
    });

    test('refused when the lock is not the release being contracted', () async {
      final DVGateOutcome outcome = await gate(
        lockUpTo(4, readsTotalUntil: 3),
      ).evaluate(contracting());
      expect(outcome.verdict, DVGateVerdict.hold);
    });

    test('a dropped model is read by any windowed version that has it', () async {
      final DVGateOutcome outcome = await DVContractStepGate(
        migration: migration,
        drops: const <DVContractDrop>[DVContractDrop.model('Order')],
        lock: lockUpTo(5, readsTotalUntil: 3),
        window: const DVProtocolWindow(versions: 1, minimumAge: Duration.zero),
        onDiagnostic: (_, _) {},
      ).evaluate(contracting());
      expect(outcome.verdict, DVGateVerdict.hold);
      expect(outcome.code, 'DV-RELEASE-005');
    });
  });
}
