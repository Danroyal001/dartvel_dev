// Schema Evolution: the backfill, its verification, and its throttle.
//
// The backfill copies existing rows in chunks, resumably, as an ordinary job.
// Verification hashes each chunk on both shapes -- the same chunks the
// backfill used -- because counts agree while values differ, and a single
// whole-table hash can only say something somewhere is wrong. A per-chunk
// hash names the chunk (DV-SCHEMA-004). A chunk that matched and later stops
// matching was written to one shape and not the other: a dual-write
// discrepancy (DV-SCHEMA-007). The throttle halves under load and steps back
// up, and says when it has been stuck below its floor (DV-SCHEMA-003).
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// `orders.total` is TEXT; the new shape is an INTEGER column beside it.
Future<SqliteDVDatabaseAdapter> ordersDatabase({int rows = 25}) async {
  final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
  await db.execute(
    'CREATE TABLE orders (id INTEGER PRIMARY KEY, total TEXT, total__dv_next INTEGER)',
  );
  for (int i = 1; i <= rows; i++) {
    await db.execute('INSERT INTO orders (id, total) VALUES (?, ?)', <Object?>[
      i,
      '${i * 10}',
    ]);
  }
  return db;
}

DVBackfill totalBackfill(DVDatabaseAdapter db, {int chunkSize = 10}) =>
    DVBackfill(
      database: db,
      id: 'orders.total-to-integer',
      table: 'orders',
      key: 'id',
      source: 'total',
      target: 'total__dv_next',
      convert: (Object? total) => total == null ? null : int.parse('$total'),
      chunkSize: chunkSize,
    );

void main() {
  group('the backfill copies in chunks', () {
    test('every row reaches the new shape, converted', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);

      final DVBackfillRun run = await backfill.run(maxChunks: 10);

      expect(run.complete, isTrue);
      expect(run.rows, 25);
      final List<Map<String, Object?>> rows = await db.query(
        'SELECT id, total__dv_next FROM orders ORDER BY id',
      );
      for (final Map<String, Object?> row in rows) {
        expect(row['total__dv_next'], (row['id']! as int) * 10);
      }
      final DVBackfillProgress progress = await backfill.progress();
      expect(progress.complete, isTrue);
      expect(progress.chunks.map((DVBackfillChunk c) => c.rows), <int>[
        10,
        10,
        5,
      ]);
      expect(progress.chunks.first.first, 1);
      expect(progress.chunks.first.last, 10);
    });

    test(
      'a restart resumes where it stopped, not from the beginning',
      () async {
        final SqliteDVDatabaseAdapter db = await ordersDatabase();
        addTearDown(db.close);

        await totalBackfill(db).run(maxChunks: 1);
        // A value the first run already copied is changed behind the backfill's
        // back. Starting again would copy it over; resuming leaves it.
        await db.execute('UPDATE orders SET total__dv_next = -1 WHERE id = 3');

        // A new instance: nothing carried over in memory. Bounded, so a
        // backfill that forgot where it was fails here instead of looping.
        final DVBackfillRun resumed = await totalBackfill(db).run(maxChunks: 5);

        expect(resumed.rows, 15);
        expect(resumed.complete, isTrue);
        expect(
          await db.query('SELECT total__dv_next FROM orders WHERE id = 3'),
          <Map<String, Object?>>[
            <String, Object?>{'total__dv_next': -1},
          ],
        );
        expect((await totalBackfill(db).progress()).chunks, hasLength(3));
      },
    );

    test('a paused backfill copies nothing until it is resumed', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);

      await backfill.pause();
      final DVBackfillRun paused = await totalBackfill(db).run(maxChunks: 5);
      expect(paused.rows, 0);
      expect(paused.stoppedBecause, DVBackfillStop.paused);

      await backfill.resume();
      expect((await totalBackfill(db).run(maxChunks: 5)).complete, isTrue);
    });

    test('runs on the development database too', () async {
      // The in-memory adapter runs the SQL the backfill writes, so a project
      // with no database configured can rehearse one.
      final MemoryDVDatabaseAdapter memory = MemoryDVDatabaseAdapter();
      await memory.execute('CREATE TABLE orders (id, total, total__dv_next)');
      for (int i = 1; i <= 12; i++) {
        await memory.execute(
          'INSERT INTO orders (id, total) VALUES (?, ?)',
          <Object?>[i, '$i'],
        );
      }
      final DVBackfill backfill = totalBackfill(memory, chunkSize: 5);
      expect((await backfill.run(maxChunks: 5)).rows, 12);
      expect(await backfill.verify(), isEmpty);
    });

    test(
      'an identifier that is not one is refused before any SQL is built',
      () {
        expect(
          () => DVBackfill(
            database: MemoryDVDatabaseAdapter(),
            id: 'x',
            table: 'orders; DROP TABLE users',
            key: 'id',
            source: 'a',
            target: 'b',
            convert: (Object? v) => v,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('verification is per chunk', () {
    test('a backfill that agrees verifies clean', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);
      await backfill.run(maxChunks: 5);

      expect(await backfill.verify(), isEmpty);
      final DVBackfillProgress progress = await backfill.progress();
      expect(progress.verified, isTrue);
      expect(progress.mismatched, isEmpty);
    });

    test(
      'a value that differs where the count agrees names its chunk',
      () async {
        // The failure COUNT(*) cannot see: the same number of rows on both
        // shapes, one of them wrong.
        final SqliteDVDatabaseAdapter db = await ordersDatabase();
        addTearDown(db.close);
        final DVBackfill backfill = totalBackfill(db);
        await backfill.run(maxChunks: 5);
        await db.execute(
          'UPDATE orders SET total__dv_next = 999 WHERE id = 14',
        );

        final List<DVSchemaFinding> findings = await backfill.verify();

        final DVSchemaFinding finding = findings.single;
        expect(finding.code, 'DV-SCHEMA-004');
        expect(finding.level, 'error');
        expect(finding.chunk, '#1 [11..20]');
        expect(finding.message, contains('#1 [11..20]'));
        final DVBackfillProgress progress = await backfill.progress();
        expect(progress.verified, isFalse);
        expect(progress.mismatched.single.index, 1);
      },
    );

    test('the mismatched chunk is fixed and re-verified alone', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);
      await backfill.run(maxChunks: 5);
      await db.execute('UPDATE orders SET total__dv_next = 999 WHERE id = 14');
      await backfill.verify();

      await db.execute('UPDATE orders SET total__dv_next = 140 WHERE id = 14');
      expect(await backfill.verify(chunk: 1), isEmpty);
      expect((await backfill.progress()).verified, isTrue);
    });

    test(
      'a chunk that verified and then diverged is a dual-write discrepancy',
      () async {
        final SqliteDVDatabaseAdapter db = await ordersDatabase();
        addTearDown(db.close);
        final DVBackfill backfill = totalBackfill(db);
        await backfill.run(maxChunks: 5);
        expect(await backfill.verify(), isEmpty);

        // A write reached the old shape and not the new one.
        await db.execute("UPDATE orders SET total = '55' WHERE id = 2");

        final List<DVSchemaFinding> findings = await backfill.verify();
        expect(
          findings.map((DVSchemaFinding f) => f.code),
          containsAll(<String>['DV-SCHEMA-004', 'DV-SCHEMA-007']),
        );
        expect(
          findings
              .firstWhere((DVSchemaFinding f) => f.code == 'DV-SCHEMA-007')
              .chunk,
          '#0 [1..10]',
        );
      },
    );

    test(
      'a chunk that never matched is not a dual-write discrepancy',
      () async {
        final SqliteDVDatabaseAdapter db = await ordersDatabase();
        addTearDown(db.close);
        final DVBackfill backfill = totalBackfill(db);
        await backfill.run(maxChunks: 5);
        await db.execute('UPDATE orders SET total__dv_next = 999 WHERE id = 2');

        expect(
          (await backfill.verify()).map((DVSchemaFinding f) => f.code),
          <String>['DV-SCHEMA-004'],
        );
      },
    );

    test('verification is not a count', () async {
      // Swapping two values keeps every count and every sum, and still has
      // to be caught.
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);
      await backfill.run(maxChunks: 5);
      await db.execute('UPDATE orders SET total__dv_next = 20 WHERE id = 1');
      await db.execute('UPDATE orders SET total__dv_next = 10 WHERE id = 2');

      expect(
        (await backfill.verify()).map((DVSchemaFinding f) => f.chunk),
        <String>['#0 [1..10]'],
      );
    });

    test('an unbackfilled backfill is not verified', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      final DVBackfill backfill = totalBackfill(db);
      await backfill.run(maxChunks: 1);
      await backfill.verify();

      final DVBackfillProgress progress = await backfill.progress();
      expect(progress.complete, isFalse);
      expect(progress.verified, isFalse);
    });
  });

  group('throttling against the database', () {
    test('the tier sets the starting rate', () {
      expect(DVDatabaseTier.small.startingRate, 500);
      expect(DVDatabaseTier.standard.startingRate, 2000);
      expect(DVDatabaseTier.large.startingRate, 10000);
      expect(DVBackfillThrottle(const DVBackfillSettings()).rate, 2000);
    });

    test('settings are read from dartvel.database', () {
      final DVBackfillSettings settings = DVBackfillSettings.fromConfig(
        <String, Object?>{
          'tier': 'large',
          'backfill': <String, Object?>{
            'targetReplicaLag': '2s',
            'maxWriteLatencyIncrease': '25%',
          },
        },
      );
      expect(settings.tier, DVDatabaseTier.large);
      expect(settings.targetReplicaLag, const Duration(seconds: 2));
      expect(settings.maxWriteLatencyIncrease, 0.25);
    });

    test('the defaults are the specification\'s', () {
      final DVBackfillSettings settings = DVBackfillSettings.fromConfig(null);
      expect(settings.tier, DVDatabaseTier.standard);
      expect(settings.targetReplicaLag, const Duration(seconds: 5));
      expect(settings.maxWriteLatencyIncrease, 0.10);
    });

    test('a tier it does not know is refused rather than defaulted', () {
      expect(
        () => DVBackfillSettings.fromConfig(<String, Object?>{'tier': 'huge'}),
        throwsFormatException,
      );
    });

    test('halves over budget and steps back up under it', () {
      final DVBackfillThrottle throttle = DVBackfillThrottle(
        const DVBackfillSettings(),
      );
      final DateTime t = DateTime.utc(2026, 9, 14);

      throttle.observe(
        const DVBackfillLoad(replicaLag: Duration(seconds: 9)),
        t,
      );
      expect(throttle.rate, 1000);
      throttle.observe(const DVBackfillLoad(writeLatencyIncrease: 0.5), t);
      expect(throttle.rate, 500);

      throttle.observe(
        const DVBackfillLoad(
          replicaLag: Duration(seconds: 1),
          writeLatencyIncrease: 0.02,
        ),
        t,
      );
      expect(throttle.rate, greaterThan(500));
    });

    test('exactly at the budget is not over it', () {
      final DVBackfillThrottle throttle = DVBackfillThrottle(
        const DVBackfillSettings(),
      );
      throttle.observe(
        const DVBackfillLoad(replicaLag: Duration(seconds: 5)),
        DateTime.utc(2026),
      );
      expect(throttle.rate, greaterThanOrEqualTo(2000));
    });

    test('stuck below the floor past its patience is reported once', () {
      final DVBackfillThrottle throttle = DVBackfillThrottle(
        const DVBackfillSettings(
          tier: DVDatabaseTier.small,
          floorRate: 100,
          patience: Duration(minutes: 10),
        ),
      );
      const DVBackfillLoad overloaded = DVBackfillLoad(
        replicaLag: Duration(minutes: 1),
      );
      final DateTime start = DateTime.utc(2026, 9, 14, 3);

      // 500 -> 250 -> 125 -> 62.5: below the floor from the third.
      for (int i = 0; i < 3; i++) {
        expect(throttle.observe(overloaded, start), isNull);
      }
      expect(throttle.rate, lessThan(100));
      expect(
        throttle.observe(overloaded, start.add(const Duration(minutes: 9))),
        isNull,
      );

      final DVSchemaFinding? late = throttle.observe(
        overloaded,
        start.add(const Duration(minutes: 10)),
      );
      expect(late?.code, 'DV-SCHEMA-003');
      expect(late?.level, 'warning');
      expect(
        throttle.observe(overloaded, start.add(const Duration(minutes: 11))),
        isNull,
      );
    });

    test('the run backs off as soon as the database says so', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase(rows: 20);
      addTearDown(db.close);
      final List<Duration> slept = <Duration>[];
      int measured = 0;

      await totalBackfill(db).run(
        maxChunks: 5,
        throttle: DVBackfillThrottle(
          const DVBackfillSettings(tier: DVDatabaseTier.small),
        ),
        // Overloaded after the first chunk, quiet after the second.
        load: () => measured++ == 0
            ? const DVBackfillLoad(replicaLag: Duration(seconds: 30))
            : const DVBackfillLoad(replicaLag: Duration.zero),
        sleep: (Duration d) async => slept.add(d),
      );

      // Ten rows at a halved 250 rows a second, then at a stepped-up 300.
      expect(slept, <Duration>[
        const Duration(milliseconds: 40),
        const Duration(microseconds: 33333),
      ]);
    });
  });

  group('it is an ordinary job', () {
    test(
      'queued, worked to completion, and re-queued between slices',
      () async {
        final SqliteDVDatabaseAdapter db = await ordersDatabase();
        addTearDown(db.close);
        const DVQueues queues = DVQueues();
        queues.useAdapter(DVInMemoryQueueAdapter());
        final DVSchemaBackfills backfills = DVSchemaBackfills()
          ..add(totalBackfill(db))
          ..registerJobs(queues);

        await backfills.start('orders.total-to-integer', chunksPerJob: 1);
        final int worked = await queues.work(maxJobs: 10);

        // Three chunks, one a job, and a fourth job finds nothing left.
        expect(worked, 4);
        expect((await totalBackfill(db).progress()).complete, isTrue);
        expect(await queues.pending(), isEmpty);
      },
    );

    test('a paused backfill stops re-queueing itself', () async {
      final SqliteDVDatabaseAdapter db = await ordersDatabase();
      addTearDown(db.close);
      const DVQueues queues = DVQueues();
      queues.useAdapter(DVInMemoryQueueAdapter());
      final DVSchemaBackfills backfills = DVSchemaBackfills()
        ..add(totalBackfill(db))
        ..registerJobs(queues);

      await backfills.start('orders.total-to-integer', chunksPerJob: 1);
      await queues.work();
      await backfills.pause('orders.total-to-integer');
      await queues.work(maxJobs: 10);

      expect(await queues.pending(), isEmpty);
      expect((await totalBackfill(db).progress()).chunks, hasLength(1));

      await backfills.resume('orders.total-to-integer', chunksPerJob: 5);
      await queues.work(maxJobs: 10);
      expect((await totalBackfill(db).progress()).complete, isTrue);
    });

    test('an unknown backfill fails the job rather than vanishing', () async {
      const DVQueues queues = DVQueues();
      queues.useAdapter(DVInMemoryQueueAdapter());
      DVSchemaBackfills().registerJobs(queues);

      await queues.dispatch(
        const DVSchemaBackfillRequest(id: 'nobody', chunks: 1),
      );
      // Reserved and failed -- retried, then dead-lettered -- rather than
      // counted as done.
      expect(await queues.work(), 0);
    });
  });
}
