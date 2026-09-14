// Schema Evolution's tracker, read by Backend Release Management.
//
// The two were built apart and have to agree on two questions. Which releases
// can a rollback restore while a migration is at a given phase: a release
// that reads a column the database no longer keeps current is a rollback that
// looks fine until its first query. And whether a contract may run: a tracker
// that contracts while the release gate holds, or the reverse, leaves the
// pipeline and the database telling different stories.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String migration = 'orders.total-to-integer';
const Duration window = Duration(hours: 1);
final DateTime t0 = DateTime.utc(2026, 9, 14, 9);
DateTime t(int hours) => t0.add(Duration(hours: hours));

const DVBackfillProgress verifiedProgress = DVBackfillProgress(
  complete: true,
  chunks: <DVBackfillChunk>[
    DVBackfillChunk(
      index: 0,
      first: 1,
      last: 10,
      rows: 10,
      state: 'verified',
      everMatched: true,
    ),
  ],
);

DVReleaseRecord record(String id, DVReleaseMigrationPhase? phase) =>
    DVReleaseRecord(
      id: id,
      commit: 'commit-$id',
      artifact: 'sha256:$id',
      protocolVersion: 9,
      migrationPlan: phase == null ? null : 'plan-$id',
      releasedBy: 'daniel',
      releasedAt: t0,
      schema: <String, DVReleaseMigrationPhase>{
        if (phase != null) migration: phase,
      },
    );

/// A migration walked one step at a time, each release recorded with the
/// phase the tracker reported when it was deployed -- which is how a release's
/// provenance learns what schema it was built for.
final class _Walk {
  _Walk() {
    history.deployed('r0', provenance: record('r0', null), at: t(0));
  }

  final DVSchemaEvolutionStore store = DVSchemaEvolutionStore(
    MemoryDVDatabaseAdapter(),
  );
  final DVReleaseHistory history = DVReleaseHistory(onDiagnostic: (_, _) {});
  late DVSchemaEvolution evolution;

  Future<void> deploy(String id, int hour) async {
    await store.save(evolution);
    history.deployed(
      id,
      provenance: record(id, evolution.releasePhase),
      at: t(hour),
    );
  }

  Future<void> expect_(DVSchemaPhaseResult result) async {
    expect(
      result.allowed,
      isTrue,
      reason: '${result.reasons} ${result.findings}',
    );
    await store.save(evolution);
  }

  /// What a rollback to each earlier release would do, read through the
  /// store's phase source.
  Future<Map<String, String>> rollbacks() async {
    final Map<String, String> out = <String, String>{};
    for (final DVDeployedRelease release in history.releases) {
      if (release.id == history.current!.id) continue;
      final DVRollbackPlan plan = await DVRollbackPlanner.plan(
        history: history,
        target: DVRollbackTarget.release(release.id),
        schema: store.phaseSource,
        now: t(100),
        onDiagnostic: (_, _) {},
      );
      out[release.id] = !plan.allowed
          ? 'refused'
          : plan.reverify.isEmpty
          ? 'allowed'
          : 'allowed, reverify';
    }
    return out;
  }
}

/// The steps, in order. Each is a separate deploy unless it says otherwise.
final Map<String, Future<void> Function(_Walk)>
steps = <String, Future<void> Function(_Walk)>{
  'expand': (_Walk w) async {
    w.evolution = DVSchemaEvolution.expand(
      id: migration,
      release: 'r1',
      at: t(1),
      expandProtocol: 8,
      verificationWindow: window,
    );
    await w.deploy('r1', 1);
  },
  'dual-write': (_Walk w) async {
    await w.expect_(w.evolution.advance(release: 'r2', now: t(2)));
    await w.deploy('r2', 2);
  },
  'backfill': (_Walk w) async {
    await w.expect_(w.evolution.advance(release: 'r3', now: t(3)));
    await w.deploy('r3', 3);
  },
  'verify': (_Walk w) async {
    await w.expect_(
      w.evolution.advance(release: 'r4', now: t(4), progress: verifiedProgress),
    );
    await w.deploy('r4', 4);
  },
  // Verification is the job's result, not a deploy: r4 is still serving.
  'verified': (_Walk w) async {
    await w.expect_(w.evolution.verify(now: t(5), progress: verifiedProgress));
  },
  // A release deployed while every chunk agrees and reads have not moved.
  'a release built on verification': (_Walk w) async {
    await w.deploy('r4h', 6);
  },
  // A discrepancy takes verification away, and a later release is built
  // on the schema as it now is.
  'verification revoked': (_Walk w) async {
    w.evolution.recordDiscrepancy(t(6).add(const Duration(minutes: 1)));
    await w.store.save(w.evolution);
    await w.deploy('r4i', 7);
  },
  'verified again': (_Walk w) async {
    await w.expect_(w.evolution.verify(now: t(8), progress: verifiedProgress));
  },
  'read switch': (_Walk w) async {
    await w.expect_(
      w.evolution.switchReads(release: 'r5', progress: verifiedProgress),
    );
    await w.deploy('r5', 9);
  },
  'contract': (_Walk w) async {
    await w.expect_(
      w.evolution.advance(
        release: 'r6',
        now: t(10),
        clientProtocols: const <int>{8, 9},
      ),
    );
    await w.deploy('r6', 10);
  },
  'old shape dropped': (_Walk w) async {
    await w.expect_(
      w.evolution.dropOldShape(
        release: 'r7',
        clientProtocols: const <int>{8, 9},
      ),
    );
    await w.deploy('r7', 11);
  },
};

Future<_Walk> walkTo(String last) async {
  final _Walk walk = _Walk();
  for (final MapEntry<String, Future<void> Function(_Walk)> step
      in steps.entries) {
    await step.value(walk);
    if (step.key == last) return walk;
  }
  throw ArgumentError.value(last, 'last', 'is not a step');
}

void main() {
  group('a rollback, at every phase the tracker reports', () {
    Future<void> at(
      String step, {
      required DVReleaseMigrationPhase reports,
      required Map<String, String> rollbacks,
    }) async {
      final _Walk walk = await walkTo(step);
      expect(await walk.store.phaseSource(migration), reports, reason: step);
      expect(await walk.rollbacks(), rollbacks, reason: step);
    }

    test('expand: the release before it still reads the old shape', () async {
      await at(
        'expand',
        reports: DVReleaseMigrationPhase.expanded,
        rollbacks: <String, String>{'r0': 'allowed'},
      );
    });

    test(
      'dual-write and backfill: every earlier release reads the old shape',
      () async {
        await at(
          'dual-write',
          reports: DVReleaseMigrationPhase.dualWriting,
          rollbacks: <String, String>{'r0': 'allowed', 'r1': 'allowed'},
        );
        // Copying is still dual-writing: no row is known to be backfilled until
        // the gate into verify has seen the backfill complete.
        await at(
          'backfill',
          reports: DVReleaseMigrationPhase.dualWriting,
          rollbacks: <String, String>{
            'r0': 'allowed',
            'r1': 'allowed',
            'r2': 'allowed',
          },
        );
      },
    );

    test('verify: backfilled, and a release that does not dual-write leaves '
        'the backfill to verify again', () async {
      await at(
        'verify',
        reports: DVReleaseMigrationPhase.backfilled,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
        },
      );
    });

    test('verified is its own state: reads have not moved, so every release '
        'before it is still a target', () async {
      await at(
        'verified',
        reports: DVReleaseMigrationPhase.verified,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
        },
      );
      await at(
        'a release built on verification',
        reports: DVReleaseMigrationPhase.verified,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
          'r4': 'allowed',
        },
      );
    });

    test('a discrepancy revokes verified, and a release built on it is refused '
        'until the chunks verify again', () async {
      await at(
        'verification revoked',
        reports: DVReleaseMigrationPhase.backfilled,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
          'r4': 'allowed',
          'r4h': 'refused',
        },
      );
      await at(
        'verified again',
        reports: DVReleaseMigrationPhase.verified,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
          'r4': 'allowed',
          'r4h': 'allowed',
        },
      );
    });

    test('read switch: the old shape is still written, so a release reading '
        'it is still a safe target', () async {
      await at(
        'read switch',
        reports: DVReleaseMigrationPhase.readSwitched,
        rollbacks: <String, String>{
          'r0': 'allowed, reverify',
          'r1': 'allowed, reverify',
          'r2': 'allowed',
          'r3': 'allowed',
          'r4': 'allowed',
          'r4h': 'allowed',
          'r4i': 'allowed',
        },
      );
    });

    test('contract: the old shape is no longer written, so no release built '
        'before it is a target', () async {
      // r4 reads a column nobody writes any more. r5 reads the new shape and
      // would be safe until the drop, but release management has no phase for
      // "no longer written, not yet dropped", and refusing it is the side to
      // err on.
      await at(
        'contract',
        reports: DVReleaseMigrationPhase.contracted,
        rollbacks: <String, String>{
          'r0': 'refused',
          'r1': 'refused',
          'r2': 'refused',
          'r3': 'refused',
          'r4': 'refused',
          'r4h': 'refused',
          'r4i': 'refused',
          'r5': 'refused',
        },
      );
    });

    test('dropped: only the release that contracted is a target', () async {
      await at(
        'old shape dropped',
        reports: DVReleaseMigrationPhase.contracted,
        rollbacks: <String, String>{
          'r0': 'refused',
          'r1': 'refused',
          'r2': 'refused',
          'r3': 'refused',
          'r4': 'refused',
          'r4h': 'refused',
          'r4i': 'refused',
          'r5': 'refused',
          'r6': 'allowed',
        },
      );
    });
  });

  group('the tracker and the contract gate agree', () {
    // Protocols 1..9; the expand raised it to 8, so 7 and older read the old
    // shape. A window of k previous versions serves {9-k..9}, which is the
    // client list the tracker is given.
    final DVProtocolLock lock = DVProtocolLock(<DVProtocolRelease>[
      for (int p = 1; p <= 9; p++)
        DVProtocolRelease(
          protocol: p,
          shape: _contract(total: p <= 7).shape,
          released: t0.subtract(Duration(days: 100 * (10 - p))),
          contract: _contract(total: p <= 7),
        ),
    ]);

    test('for the same client list, at every phase a contract can be asked '
        'for', () async {
      for (final String step in <String>[
        'verify',
        'verified',
        'read switch',
        'contract',
      ]) {
        final _Walk walk = await walkTo(step);
        for (int k = 0; k <= 3; k++) {
          final DVProtocolWindow protocolWindow = DVProtocolWindow(
            versions: k,
            minimumAge: Duration.zero,
          );
          final Set<int> clients = protocolWindow.served(lock, now: t(20));
          expect(clients, <int>{for (int p = 9 - k; p <= 9; p++) p});

          // A copy, so an allowed contract does not move the walk on.
          final DVSchemaEvolution copy = DVSchemaEvolution.fromJson(
            walk.evolution.toJson(),
          );
          final DVSchemaPhaseResult tracker =
              copy.phase == DVSchemaPhase.contract
              ? copy.dropOldShape(release: 'next', clientProtocols: clients)
              : copy.advance(
                  release: 'next',
                  now: t(20),
                  progress: verifiedProgress,
                  clientProtocols: clients,
                );

          final DVGateOutcome gate =
              DVContractStepGate(
                migration: migration,
                drops: const <DVContractDrop>[
                  DVContractDrop.field('Order', 'total'),
                ],
                lock: lock,
                window: protocolWindow,
                onDiagnostic: (_, _) {},
              ).evaluate(
                DVReleaseGateContext(
                  candidate: record('next', DVReleaseMigrationPhase.contracted),
                  previous: walk.history.current!.provenance,
                  phase: DVReleasePhase.beforeDeploy,
                  percent: 0,
                  stepStartedAt: t(20),
                  now: t(20),
                ),
              );

          expect(
            tracker.allowed,
            gate.verdict == DVGateVerdict.pass,
            reason:
                'at $step with clients $clients: the tracker '
                '${tracker.allowed ? 'allows' : 'refuses'} '
                '(${tracker.reasons} ${tracker.findings.map((f) => f.code)}) '
                'and the gate says ${gate.verdict.name} (${gate.reason})',
          );
        }
      }
    });

    test('and the refusal for a windowed reader carries both codes for the '
        'same versions', () async {
      final _Walk walk = await walkTo('read switch');
      final DVSchemaPhaseResult tracker = walk.evolution.advance(
        release: 'next',
        now: t(20),
        clientProtocols: const <int>{7, 8, 9},
      );
      final DVGateOutcome gate =
          DVContractStepGate(
            migration: migration,
            drops: const <DVContractDrop>[
              DVContractDrop.field('Order', 'total'),
            ],
            lock: lock,
            window: const DVProtocolWindow(
              versions: 2,
              minimumAge: Duration.zero,
            ),
            onDiagnostic: (_, _) {},
          ).evaluate(
            DVReleaseGateContext(
              candidate: record('next', DVReleaseMigrationPhase.contracted),
              previous: walk.history.current!.provenance,
              phase: DVReleasePhase.beforeDeploy,
              percent: 0,
              stepStartedAt: t(20),
              now: t(20),
            ),
          );
      expect(tracker.findings.single.code, 'DV-SCHEMA-005');
      expect(tracker.findings.single.message, contains('protocol 7'));
      expect(gate.code, 'DV-RELEASE-005');
      expect(gate.reason, contains('protocol 7'));
    });
  });
}

DVProtocolContract _contract({required bool total}) => DVProtocolContract(
  models: <DVProtocolModel>[
    DVProtocolModel('Order', <DVProtocolField>[
      const DVProtocolField('id', 'String'),
      if (total) const DVProtocolField('total', 'int'),
      const DVProtocolField('totalCents', 'int?'),
    ]),
  ],
);
