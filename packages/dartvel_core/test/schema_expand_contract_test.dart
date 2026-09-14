// Schema Evolution: the five phases, and the gates between them.
//
// Each phase is a separate deploy, because a phase boundary is where a
// rollback is still cheap and an expand/contract compressed into one release
// is the outage it was meant to avoid. The read switch needs three things at
// once: every chunk backfilled, every chunk verified, and the dual-write
// discrepancy counter at zero for the whole verification window. The contract
// is refused while a client inside the protocol window still reads the old
// shape (DV-SCHEMA-005).
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 14, 9);
const Duration window = Duration(hours: 1);

const DVBackfillChunk clean0 = DVBackfillChunk(
  index: 0,
  first: 1,
  last: 10,
  rows: 10,
  state: 'verified',
  everMatched: true,
);
const DVBackfillChunk clean1 = DVBackfillChunk(
  index: 1,
  first: 11,
  last: 20,
  rows: 10,
  state: 'verified',
  everMatched: true,
);
const DVBackfillProgress verified = DVBackfillProgress(
  complete: true,
  chunks: <DVBackfillChunk>[clean0, clean1],
);

DVSchemaEvolution started() => DVSchemaEvolution.expand(
  id: 'orders.total-to-integer',
  release: 'r1',
  at: t0,
  expandProtocol: 8,
  verificationWindow: window,
);

/// Walks to the verify phase, one release a phase.
DVSchemaEvolution atVerify() {
  final DVSchemaEvolution evolution = started();
  expect(evolution.advance(release: 'r2', now: t0).allowed, isTrue);
  expect(
    evolution.advance(release: 'r3', now: t0, progress: verified).allowed,
    isTrue,
  );
  expect(
    evolution.advance(release: 'r4', now: t0, progress: verified).allowed,
    isTrue,
  );
  expect(evolution.phase, DVSchemaPhase.verify);
  return evolution;
}

DVSchemaEvolution contracted() {
  final DVSchemaEvolution evolution = atVerify();
  expect(
    evolution
        .advance(
          release: 'r5',
          now: t0.add(window),
          progress: verified,
          clientProtocols: const <int>{8},
        )
        .allowed,
    isTrue,
  );
  return evolution;
}

void main() {
  group('each phase is a separate deploy', () {
    test('the phases run in order', () {
      final DVSchemaEvolution evolution = started();
      expect(evolution.phase, DVSchemaPhase.expand);
      evolution.advance(release: 'r2', now: t0);
      expect(evolution.phase, DVSchemaPhase.dualWrite);
      evolution.advance(release: 'r3', now: t0, progress: verified);
      expect(evolution.phase, DVSchemaPhase.backfill);
    });

    test('two phases in one release are refused', () {
      final DVSchemaEvolution evolution = started();
      final DVSchemaPhaseResult result = evolution.advance(
        release: 'r1',
        now: t0,
      );

      expect(result.allowed, isFalse);
      expect(result.reasons.single, contains('r1'));
      expect(evolution.phase, DVSchemaPhase.expand);
    });

    test('a release that already ran an earlier phase is refused too', () {
      // Going r1 -> r2 -> r1 is a rollback, not a new deploy.
      final DVSchemaEvolution evolution = started();
      evolution.advance(release: 'r2', now: t0);
      expect(evolution.advance(release: 'r1', now: t0).allowed, isFalse);
    });
  });

  group('the backfill must finish before verification', () {
    test('an incomplete backfill is refused', () {
      final DVSchemaEvolution evolution = started()
        ..advance(release: 'r2', now: t0)
        ..advance(release: 'r3', now: t0);
      final DVSchemaPhaseResult result = evolution.advance(
        release: 'r4',
        now: t0,
        progress: const DVBackfillProgress(
          complete: false,
          chunks: <DVBackfillChunk>[clean0],
        ),
      );
      expect(result.allowed, isFalse);
      expect(evolution.phase, DVSchemaPhase.backfill);
    });

    test('no progress at all is not progress', () {
      final DVSchemaEvolution evolution = started()
        ..advance(release: 'r2', now: t0)
        ..advance(release: 'r3', now: t0);
      expect(evolution.advance(release: 'r4', now: t0).allowed, isFalse);
    });
  });

  group('the read switch', () {
    DVSchemaPhaseResult readSwitch(
      DVSchemaEvolution evolution, {
      DateTime? now,
      DVBackfillProgress progress = verified,
      Set<int>? clients = const <int>{8, 9},
    }) => evolution.advance(
      release: 'r5',
      now: now ?? t0.add(window),
      progress: progress,
      clientProtocols: clients,
    );

    test('with everything agreeing, reads move to the new shape', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = readSwitch(evolution);
      expect(result.allowed, isTrue, reason: '${result.reasons}');
      expect(evolution.phase, DVSchemaPhase.contract);
    });

    test('a chunk not yet verified refuses it', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = readSwitch(
        evolution,
        progress: const DVBackfillProgress(
          complete: true,
          chunks: <DVBackfillChunk>[
            clean0,
            DVBackfillChunk(
              index: 1,
              first: 11,
              last: 20,
              rows: 10,
              state: 'backfilled',
              everMatched: false,
            ),
          ],
        ),
      );
      expect(result.allowed, isFalse);
      expect(result.reasons.single, contains('#1 [11..20]'));
    });

    test('a mismatched chunk refuses it and is named', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = readSwitch(
        evolution,
        progress: const DVBackfillProgress(
          complete: true,
          chunks: <DVBackfillChunk>[
            clean0,
            DVBackfillChunk(
              index: 1,
              first: 11,
              last: 20,
              rows: 10,
              state: 'mismatched',
              everMatched: false,
            ),
          ],
        ),
      );
      expect(result.allowed, isFalse);
      final DVSchemaFinding finding = result.findings.single;
      expect(finding.code, 'DV-SCHEMA-004');
      expect(finding.chunk, '#1 [11..20]');
      expect(evolution.phase, DVSchemaPhase.verify);
    });

    test('an incomplete backfill refuses it even with clean chunks', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = readSwitch(
        evolution,
        progress: const DVBackfillProgress(
          complete: false,
          chunks: <DVBackfillChunk>[clean0, clean1],
        ),
      );
      expect(result.allowed, isFalse);
    });

    test('the verification window has to have passed', () {
      final DVSchemaPhaseResult early = readSwitch(
        atVerify(),
        now: t0.add(window).subtract(const Duration(seconds: 1)),
      );
      expect(early.allowed, isFalse);
      expect(readSwitch(atVerify()).allowed, isTrue);
    });

    test('a discrepancy inside the window refuses it', () {
      final DVSchemaEvolution evolution = atVerify()
        ..recordDiscrepancy(t0.add(const Duration(minutes: 50)));

      final DVSchemaPhaseResult result = readSwitch(
        evolution,
        now: t0.add(const Duration(minutes: 70)),
      );

      expect(result.allowed, isFalse);
      expect(result.findings.single.code, 'DV-SCHEMA-007');
      expect(evolution.discrepancies, 1);
    });

    test('and a whole clean window after it lets it through', () {
      final DateTime at = t0.add(const Duration(minutes: 50));
      final DVSchemaEvolution evolution = atVerify()..recordDiscrepancy(at);
      expect(readSwitch(evolution, now: at.add(window)).allowed, isTrue);
    });

    test('verification findings feed the discrepancy counter', () {
      final DVSchemaEvolution evolution = atVerify();
      final DateTime at = t0.add(const Duration(minutes: 30));
      evolution.recordFindings(<DVSchemaFinding>[
        DVSchemaFinding('DV-SCHEMA-004', 'mismatch', chunk: '#0 [1..10]'),
        DVSchemaFinding('DV-SCHEMA-007', 'diverged', chunk: '#0 [1..10]'),
      ], at);
      expect(evolution.discrepancies, 1);
      expect(readSwitch(evolution).allowed, isFalse);
    });

    test('a client inside the window that reads the old shape refuses it', () {
      // Protocol 7 predates the expand, which raised it to 8.
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = readSwitch(
        evolution,
        clients: const <int>{7, 8, 9},
      );
      expect(result.allowed, isFalse);
      final DVSchemaFinding finding = result.findings.single;
      expect(finding.code, 'DV-SCHEMA-005');
      expect(finding.message, contains('7'));
    });

    test('with no client histogram at all, it is not assumed empty', () {
      final DVSchemaPhaseResult result = readSwitch(atVerify(), clients: null);
      expect(result.allowed, isFalse);
      expect(result.reasons.single, contains('client'));
    });
  });

  group('the old shape is dropped in a later release', () {
    test('not in the release that contracted', () {
      final DVSchemaEvolution evolution = contracted();
      expect(
        evolution
            .dropOldShape(release: 'r5', clientProtocols: const <int>{8})
            .allowed,
        isFalse,
      );
      expect(evolution.oldShapeDropped, isFalse);
    });

    test('in the next one', () {
      final DVSchemaEvolution evolution = contracted();
      expect(
        evolution
            .dropOldShape(release: 'r6', clientProtocols: const <int>{8, 9})
            .allowed,
        isTrue,
      );
      expect(evolution.oldShapeDropped, isTrue);
    });

    test('not while an old client still calls', () {
      final DVSchemaEvolution evolution = contracted();
      final DVSchemaPhaseResult result = evolution.dropOldShape(
        release: 'r6',
        clientProtocols: const <int>{6, 8},
      );
      expect(result.allowed, isFalse);
      expect(result.findings.single.code, 'DV-SCHEMA-005');
    });

    test('and not before the contract at all', () {
      expect(
        atVerify()
            .dropOldShape(release: 'r9', clientProtocols: const <int>{8})
            .allowed,
        isFalse,
      );
    });

    test('and never past the last phase', () {
      expect(contracted().advance(release: 'r7', now: t0).allowed, isFalse);
    });
  });

  group('release management reads the phase', () {
    // Backend Release Management records where each migration stands with
    // its own, narrower enum and reads it through a caller-supplied source.
    // The tracker is that source.
    test('each phase maps to what release management calls it', () {
      expect(started().releasePhase, DVReleaseMigrationPhase.expanded);

      final DVSchemaEvolution dual = started()..advance(release: 'r2', now: t0);
      expect(dual.releasePhase, DVReleaseMigrationPhase.dualWriting);

      // Copying is still dual-writing: not a row is known to be backfilled
      // until the gate into verify has seen the backfill complete.
      final DVSchemaEvolution copying = dual..advance(release: 'r3', now: t0);
      expect(copying.releasePhase, DVReleaseMigrationPhase.dualWriting);

      expect(atVerify().releasePhase, DVReleaseMigrationPhase.backfilled);
      expect(contracted().releasePhase, DVReleaseMigrationPhase.readSwitched);

      final DVSchemaEvolution dropped = contracted()
        ..dropOldShape(release: 'r6', clientProtocols: const <int>{8});
      expect(dropped.releasePhase, DVReleaseMigrationPhase.contracted);
    });

    test('the store is a migration phase source', () async {
      final DVSchemaEvolutionStore store = DVSchemaEvolutionStore(
        MemoryDVDatabaseAdapter(),
      );
      await store.save(atVerify());

      final DVMigrationPhaseSource source = store.phaseSource;
      expect(
        await source('orders.total-to-integer'),
        DVReleaseMigrationPhase.backfilled,
      );
      // An evolution it has never seen cannot be told, which release
      // management treats as unknown rather than as not started.
      expect(await source('nothing'), isNull);
    });
  });

  group('it survives a restart', () {
    test('the state round-trips', () {
      final DVSchemaEvolution evolution = atVerify()
        ..recordDiscrepancy(t0.add(const Duration(minutes: 5)));

      final DVSchemaEvolution restored = DVSchemaEvolution.fromJson(
        evolution.toJson(),
      );

      expect(restored.phase, DVSchemaPhase.verify);
      expect(restored.discrepancies, 1);
      expect(restored.expandProtocol, 8);
      // Still refuses r4 -- the release that entered verify.
      expect(
        restored.advance(release: 'r4', now: t0.add(window)).allowed,
        isFalse,
      );
      expect(restored.toJson(), evolution.toJson());
    });

    test('a dropped old shape stays dropped, with its release', () {
      final DVSchemaEvolution evolution = contracted()
        ..dropOldShape(release: 'r6', clientProtocols: const <int>{8});
      final DVSchemaEvolution restored = DVSchemaEvolution.fromJson(
        evolution.toJson(),
      );
      expect(restored.oldShapeDropped, isTrue);
      expect(restored.advance(release: 'r6', now: t0).allowed, isFalse);
    });

    test('and is kept in the database', () async {
      final DVSchemaEvolutionStore store = DVSchemaEvolutionStore(
        MemoryDVDatabaseAdapter(),
      );
      final DVSchemaEvolution evolution = atVerify();

      await store.save(evolution);
      evolution.recordDiscrepancy(t0);
      await store.save(evolution);

      final DVSchemaEvolution? loaded = await store.load(
        'orders.total-to-integer',
      );
      expect(loaded?.phase, DVSchemaPhase.verify);
      expect(loaded?.discrepancies, 1);
      expect(await store.load('nothing'), isNull);
    });
  });
}
