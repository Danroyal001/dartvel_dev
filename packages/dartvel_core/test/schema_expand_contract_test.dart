// Schema Evolution: the five phases, and the gates between them.
//
// Each phase is a separate deploy, because a phase boundary is where a
// rollback is still cheap and an expand/contract compressed into one release
// is the outage it was meant to avoid. Verification needs three things at
// once: every chunk backfilled, every chunk verified, and the dual-write
// discrepancy counter at zero for the whole verification window. Reads then
// move in a release of their own, while both shapes are still written. The
// contract stops writing the old shape, and is refused while a client inside
// the protocol window still reads it (DV-SCHEMA-005) or while the release
// being replaced does.
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
const DVBackfillProgress mismatchedChunk = DVBackfillProgress(
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

DVSchemaEvolution verifiedAtVerify() {
  final DVSchemaEvolution evolution = atVerify();
  final DVSchemaPhaseResult result = evolution.verify(
    now: t0.add(window),
    progress: verified,
  );
  expect(result.allowed, isTrue, reason: '${result.reasons}');
  return evolution;
}

DVSchemaEvolution switched() {
  final DVSchemaEvolution evolution = verifiedAtVerify();
  final DVSchemaPhaseResult result = evolution.switchReads(
    release: 'r5',
    progress: verified,
  );
  expect(result.allowed, isTrue, reason: '${result.reasons}');
  return evolution;
}

DVSchemaEvolution contracted() {
  final DVSchemaEvolution evolution = switched();
  final DVSchemaPhaseResult result = evolution.advance(
    release: 'r6',
    now: t0.add(window),
    clientProtocols: const <int>{8},
  );
  expect(result.allowed, isTrue, reason: '${result.reasons}');
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

  group('verification', () {
    DVSchemaPhaseResult verify(
      DVSchemaEvolution evolution, {
      DateTime? now,
      DVBackfillProgress progress = verified,
    }) => evolution.verify(now: now ?? t0.add(window), progress: progress);

    test('with everything agreeing, the migration is verified and reads have '
        'not moved', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = verify(evolution);
      expect(result.allowed, isTrue, reason: '${result.reasons}');
      expect(evolution.verified, isTrue);
      expect(evolution.readsSwitched, isFalse);
      expect(evolution.phase, DVSchemaPhase.verify);
    });

    test('is not a phase before verify', () {
      final DVSchemaEvolution evolution = started()
        ..advance(release: 'r2', now: t0)
        ..advance(release: 'r3', now: t0);
      expect(verify(evolution).allowed, isFalse);
      expect(evolution.verified, isFalse);
    });

    test('a chunk not yet verified refuses it', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = verify(
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
      expect(evolution.verified, isFalse);
    });

    test('a mismatched chunk refuses it and is named', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = verify(
        evolution,
        progress: mismatchedChunk,
      );
      expect(result.allowed, isFalse);
      final DVSchemaFinding finding = result.findings.single;
      expect(finding.code, 'DV-SCHEMA-004');
      expect(finding.chunk, '#1 [11..20]');
      expect(evolution.phase, DVSchemaPhase.verify);
    });

    test('an incomplete backfill refuses it even with clean chunks', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = verify(
        evolution,
        progress: const DVBackfillProgress(
          complete: false,
          chunks: <DVBackfillChunk>[clean0, clean1],
        ),
      );
      expect(result.allowed, isFalse);
    });

    test('the verification window has to have passed', () {
      final DVSchemaPhaseResult early = verify(
        atVerify(),
        now: t0.add(window).subtract(const Duration(seconds: 1)),
      );
      expect(early.allowed, isFalse);
      expect(verify(atVerify()).allowed, isTrue);
    });

    test('a discrepancy inside the window refuses it', () {
      final DVSchemaEvolution evolution = atVerify()
        ..recordDiscrepancy(t0.add(const Duration(minutes: 50)));

      final DVSchemaPhaseResult result = verify(
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
      expect(verify(evolution, now: at.add(window)).allowed, isTrue);
    });

    test('verification findings feed the discrepancy counter', () {
      final DVSchemaEvolution evolution = atVerify();
      final DateTime at = t0.add(const Duration(minutes: 30));
      evolution.recordFindings(<DVSchemaFinding>[
        DVSchemaFinding('DV-SCHEMA-004', 'mismatch', chunk: '#0 [1..10]'),
        DVSchemaFinding('DV-SCHEMA-007', 'diverged', chunk: '#0 [1..10]'),
      ], at);
      expect(evolution.discrepancies, 1);
      expect(verify(evolution).allowed, isFalse);
    });

    test('a discrepancy after verification takes it away', () {
      final DVSchemaEvolution evolution = verifiedAtVerify()
        ..recordDiscrepancy(t0.add(window).add(const Duration(minutes: 1)));
      expect(evolution.verified, isFalse);
      expect(
        evolution.switchReads(release: 'r5', progress: verified).allowed,
        isFalse,
      );
    });
  });

  group('the read switch', () {
    test('is refused until verified', () {
      final DVSchemaEvolution evolution = atVerify();
      final DVSchemaPhaseResult result = evolution.switchReads(
        release: 'r5',
        progress: verified,
      );
      expect(result.allowed, isFalse);
      expect(result.reasons.single, contains('not verified'));
      expect(evolution.readsSwitched, isFalse);
    });

    test('moves reads in a release of its own, needing no client histogram, '
        'because both shapes are still written', () {
      final DVSchemaEvolution evolution = verifiedAtVerify();
      final DVSchemaPhaseResult result = evolution.switchReads(
        release: 'r5',
        progress: verified,
      );
      expect(result.allowed, isTrue, reason: '${result.reasons}');
      expect(evolution.readsSwitched, isTrue);
      expect(evolution.phase, DVSchemaPhase.verify);
    });

    test('checks the chunks again', () {
      final DVSchemaPhaseResult result = verifiedAtVerify().switchReads(
        release: 'r5',
        progress: mismatchedChunk,
      );
      expect(result.allowed, isFalse);
      expect(result.findings.single.code, 'DV-SCHEMA-004');
    });

    test('not in the release that entered verify', () {
      expect(
        verifiedAtVerify()
            .switchReads(release: 'r4', progress: verified)
            .allowed,
        isFalse,
      );
    });

    test('only once', () {
      expect(
        switched().switchReads(release: 'r9', progress: verified).allowed,
        isFalse,
      );
    });
  });

  group('the contract', () {
    DVSchemaPhaseResult contract(
      DVSchemaEvolution evolution, {
      String release = 'r6',
      Set<int>? clients = const <int>{8, 9},
    }) => evolution.advance(
      release: release,
      now: t0.add(window),
      clientProtocols: clients,
    );

    test('with reads switched in an earlier release, dual-write stops', () {
      final DVSchemaEvolution evolution = switched();
      final DVSchemaPhaseResult result = contract(evolution);
      expect(result.allowed, isTrue, reason: '${result.reasons}');
      expect(evolution.phase, DVSchemaPhase.contract);
    });

    test('is refused while the release being replaced still reads the old '
        'shape, verified or not', () {
      for (final DVSchemaEvolution evolution in <DVSchemaEvolution>[
        atVerify(),
        verifiedAtVerify(),
      ]) {
        final DVSchemaPhaseResult result = contract(evolution);
        expect(result.allowed, isFalse);
        expect(
          result.reasons.single,
          contains('r4, the release being replaced'),
        );
        expect(evolution.phase, DVSchemaPhase.verify);
      }
    });

    test('not in the release that switched reads', () {
      expect(contract(switched(), release: 'r5').allowed, isFalse);
    });

    test('a client inside the window that reads the old shape refuses it', () {
      // Protocol 7 predates the expand, which raised it to 8.
      final DVSchemaPhaseResult result = contract(
        switched(),
        clients: const <int>{7, 8, 9},
      );
      expect(result.allowed, isFalse);
      final DVSchemaFinding finding = result.findings.single;
      expect(finding.code, 'DV-SCHEMA-005');
      expect(finding.message, contains('7'));
    });

    test('with no client histogram at all, it is not assumed empty', () {
      final DVSchemaPhaseResult result = contract(switched(), clients: null);
      expect(result.allowed, isFalse);
      expect(result.reasons.single, contains('client'));
    });
  });

  group('the old shape is dropped in a later release', () {
    test('not in the release that contracted', () {
      final DVSchemaEvolution evolution = contracted();
      expect(
        evolution
            .dropOldShape(release: 'r6', clientProtocols: const <int>{8})
            .allowed,
        isFalse,
      );
      expect(evolution.oldShapeDropped, isFalse);
    });

    test('in the next one', () {
      final DVSchemaEvolution evolution = contracted();
      expect(
        evolution
            .dropOldShape(release: 'r7', clientProtocols: const <int>{8, 9})
            .allowed,
        isTrue,
      );
      expect(evolution.oldShapeDropped, isTrue);
    });

    test('not while an old client still calls', () {
      final DVSchemaEvolution evolution = contracted();
      final DVSchemaPhaseResult result = evolution.dropOldShape(
        release: 'r7',
        clientProtocols: const <int>{6, 8},
      );
      expect(result.allowed, isFalse);
      expect(result.findings.single.code, 'DV-SCHEMA-005');
    });

    test('and not before the contract at all', () {
      expect(
        switched()
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
    // its own enum and reads it through a caller-supplied source. The tracker
    // is that source.
    test('each step maps to what release management calls it', () {
      expect(started().releasePhase, DVReleaseMigrationPhase.expanded);

      final DVSchemaEvolution dual = started()..advance(release: 'r2', now: t0);
      expect(dual.releasePhase, DVReleaseMigrationPhase.dualWriting);

      // Copying is still dual-writing: not a row is known to be backfilled
      // until the gate into verify has seen the backfill complete.
      final DVSchemaEvolution copying = dual..advance(release: 'r3', now: t0);
      expect(copying.releasePhase, DVReleaseMigrationPhase.dualWriting);

      expect(atVerify().releasePhase, DVReleaseMigrationPhase.backfilled);
      expect(verifiedAtVerify().releasePhase, DVReleaseMigrationPhase.verified);
      expect(switched().releasePhase, DVReleaseMigrationPhase.readSwitched);
      // The contract stops writing the old shape: a release reading it can no
      // longer be restored, dropped or not.
      expect(contracted().releasePhase, DVReleaseMigrationPhase.contracted);

      final DVSchemaEvolution dropped = contracted()
        ..dropOldShape(release: 'r7', clientProtocols: const <int>{8});
      expect(dropped.releasePhase, DVReleaseMigrationPhase.contracted);
    });

    test('a revoked verification reads as backfilled again', () {
      final DVSchemaEvolution evolution = verifiedAtVerify()
        ..recordDiscrepancy(t0.add(window));
      expect(evolution.releasePhase, DVReleaseMigrationPhase.backfilled);
    });

    test('the store is a migration phase source', () async {
      final DVSchemaEvolutionStore store = DVSchemaEvolutionStore(
        MemoryDVDatabaseAdapter(),
      );
      final DVSchemaEvolution evolution = atVerify();
      await store.save(evolution);

      final DVMigrationPhaseSource source = store.phaseSource;
      expect(
        await source('orders.total-to-integer'),
        DVReleaseMigrationPhase.backfilled,
      );
      evolution.verify(now: t0.add(window), progress: verified);
      await store.save(evolution);
      expect(
        await source('orders.total-to-integer'),
        DVReleaseMigrationPhase.verified,
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

    test('verification and the read switch are kept', () {
      final DVSchemaEvolution restored = DVSchemaEvolution.fromJson(
        switched().toJson(),
      );
      expect(restored.verified, isTrue);
      expect(restored.readsSwitched, isTrue);
      expect(restored.releasePhase, DVReleaseMigrationPhase.readSwitched);
      // r5 switched reads, so it cannot run the contract.
      expect(
        restored
            .advance(
              release: 'r5',
              now: t0.add(window),
              clientProtocols: const <int>{8},
            )
            .allowed,
        isFalse,
      );
      expect(restored.toJson(), switched().toJson());
    });

    test('a state saved before verification was recorded is not verified', () {
      final Map<String, Object?> json = verifiedAtVerify().toJson()
        ..remove('verifiedAt')
        ..remove('readsSwitchedIn');
      final DVSchemaEvolution restored = DVSchemaEvolution.fromJson(json);
      expect(restored.verified, isFalse);
      expect(restored.releasePhase, DVReleaseMigrationPhase.backfilled);
    });

    test('a dropped old shape stays dropped, with its release', () {
      final DVSchemaEvolution evolution = contracted()
        ..dropOldShape(release: 'r7', clientProtocols: const <int>{8});
      final DVSchemaEvolution restored = DVSchemaEvolution.fromJson(
        evolution.toJson(),
      );
      expect(restored.oldShapeDropped, isTrue);
      expect(restored.advance(release: 'r7', now: t0).allowed, isFalse);
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
