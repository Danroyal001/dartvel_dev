// The tenant travels with a job.
//
// DVJobEnvelope had no tenant, and no queue adapter stored one. A job
// dispatched during acme's request ran later as whatever the worker process
// happened to be set to -- writing rows that belong to nobody, or reading
// globex's. Nothing threw: the handler ran, the query returned rows, and the
// rows were somebody else's.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class ReadOrders {
  const ReadOrders(this.label);
  final String label;
}

final DVJobPayloadCodec<ReadOrders> readOrdersCodec =
    DVJobPayloadCodec<ReadOrders>(
      name: 'read_orders',
      encode: (ReadOrders job) => <String, Object?>{'label': job.label},
      decode: (Map<String, Object?> json) =>
          ReadOrders(json['label']! as String),
    );

void main() {
  setUp(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
    const DVJobPayloadCodecs().clear();
    const DVJobPayloadCodecs().register(readOrdersCodec);
  });

  tearDown(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
    const DVJobPayloadCodecs().clear();
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
  });

  group('the envelope', () {
    test('records the tenant a job was dispatched under', () async {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());

      final DVJobEnvelope<ReadOrders> job = await const DVTenants().withTenant(
        'acme',
        () => const DVQueues().dispatch(const ReadOrders('a')),
      );

      expect(job.tenant, 'acme');
      expect((await const DVQueues().pending()).single.tenant, 'acme');
    });

    test('records none when no tenant is in effect', () async {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());

      final DVJobEnvelope<ReadOrders> job = await const DVQueues().dispatch(
        const ReadOrders('a'),
      );

      expect(job.tenant, isNull);
    });

    test('records the process tenant a single-tenant deployment set', () async {
      // Not a scope, and still the tenant every query of this process runs
      // as, so the job has to run as it too.
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());
      const DVTenants().currentTenant = 'acme';

      final DVJobEnvelope<ReadOrders> job = await const DVQueues().dispatch(
        const ReadOrders('a'),
      );

      expect(job.tenant, 'acme');
    });
  });

  group('the worker', () {
    test('runs each handler as the tenant its job was dispatched under, '
        'back to back', () async {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());
      final List<String> ranAs = <String>[];
      const DVQueues().register<ReadOrders>(
        (ReadOrders job) =>
            ranAs.add('${job.label}:${const DVTenants().currentTenant}'),
      );

      await const DVTenants().withTenant(
        'acme',
        () => const DVQueues().dispatch(const ReadOrders('first')),
      );
      await const DVTenants().withTenant(
        'globex',
        () => const DVQueues().dispatch(const ReadOrders('second')),
      );
      await const DVQueues().dispatch(const ReadOrders('third'));

      // The worker process itself is set to a tenant, which is exactly what
      // a job with no tenant must not pick up.
      const DVTenants().currentTenant = 'initech';
      expect(await const DVQueues().work(maxJobs: 3), 3);

      expect(ranAs, <String>[
        'first:acme',
        'second:globex',
        'third:${DVTenants.defaultTenant}',
      ]);
    });

    test('a handler that sets the process tenant does not hand it to the '
        'next job', () async {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());
      final List<String> ranAs = <String>[];
      const DVQueues().register<ReadOrders>((ReadOrders job) {
        ranAs.add(const DVTenants().currentTenant);
        const DVTenants().currentTenant = 'leaked';
      });

      await const DVTenants().withTenant(
        'acme',
        () => const DVQueues().dispatch(const ReadOrders('a')),
      );
      await const DVQueues().dispatch(const ReadOrders('b'));

      await const DVQueues().work(maxJobs: 2);

      expect(ranAs, <String>['acme', DVTenants.defaultTenant]);
    });

    test('a worker draining inside some tenant scope does not lend it to a '
        'job with none', () async {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());
      final List<String> ranAs = <String>[];
      const DVQueues().register<ReadOrders>(
        (ReadOrders job) => ranAs.add(const DVTenants().currentTenant),
      );
      await const DVQueues().dispatch(const ReadOrders('a'));

      await const DVTenants().withTenant(
        'globex',
        () => const DVQueues().work(),
      );

      expect(ranAs, <String>[DVTenants.defaultTenant]);
    });
  });

  group('what a job reads', () {
    Future<void> seed(DVDatabaseAdapter db) async {
      await db.execute(
        'CREATE TABLE orders (id INTEGER PRIMARY KEY, dv_tenant TEXT, '
        'title TEXT)',
      );
      await db.execute(
        'INSERT INTO orders (dv_tenant, title) VALUES (?, ?)',
        <Object?>['acme', 'acme order'],
      );
      await db.execute(
        'INSERT INTO orders (dv_tenant, title) VALUES (?, ?)',
        <Object?>['globex', 'globex order'],
      );
    }

    // What a generated tenant-scoped model query does: the predicate bound
    // to the tenant current when the statement runs.
    Future<List<String>> scopedTitles() async => <String>[
      for (final Map<String, Object?> row in await const DVDatabase().query(
        'SELECT title FROM orders WHERE dv_tenant = ?',
        <Object?>[const DVTenants().currentTenant],
      ))
        '${row['title']}',
    ];

    test('a job dispatched in acme reads acme and not globex, across a '
        'database queue restart', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'dartvel_job_tenant_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final String jobsPath = '${dir.path}/jobs.db';

      final SqliteDVDatabaseAdapter data = SqliteDVDatabaseAdapter.memory();
      addTearDown(data.close);
      await seed(data);
      const DVDatabase().configure(data);
      dvRegisterTenantScopedTables(<String>{'orders'});

      // The web process: one request each.
      final SqliteDVDatabaseAdapter web = SqliteDVDatabaseAdapter.file(
        jobsPath,
      );
      const DVQueues().useAdapter(DVDatabaseQueueAdapter(web));
      await const DVTenants().withTenant(
        'acme',
        () => const DVQueues().dispatch(const ReadOrders('acme')),
      );
      await const DVTenants().withTenant(
        'globex',
        () => const DVQueues().dispatch(const ReadOrders('globex')),
      );
      web.close();

      // The worker: a new process over the same file.
      final SqliteDVDatabaseAdapter worker = SqliteDVDatabaseAdapter.file(
        jobsPath,
      );
      addTearDown(worker.close);
      const DVQueues().useAdapter(DVDatabaseQueueAdapter(worker));
      final Map<String, List<String>> read = <String, List<String>>{};
      const DVQueues().register<ReadOrders>((ReadOrders job) async {
        read[job.label] = await scopedTitles();
      });

      expect(await const DVQueues().work(maxJobs: 2), 2);

      expect(read, <String, List<String>>{
        'acme': <String>['acme order'],
        'globex': <String>['globex order'],
      });
    });

    test(
      'under a database per tenant a job reaches its tenant\'s database',
      () async {
        final Map<String, MemoryDVDatabaseAdapter> opened =
            <String, MemoryDVDatabaseAdapter>{};
        const DVTenants().configure(
          isolation: DVTenantIsolation.databasePerTenant,
        );
        const DVDatabase().configureTenantDatabases(
          (String tenant) =>
              opened.putIfAbsent(tenant, MemoryDVDatabaseAdapter.new),
        );
        for (final String tenant in <String>['acme', 'globex']) {
          await const DVTenants().withTenant(tenant, () async {
            await const DVDatabase().execute(
              'CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)',
            );
            await const DVDatabase().execute(
              'INSERT INTO notes (id, body) VALUES (?, ?)',
              <Object?>[1, '$tenant note'],
            );
          });
        }

        final SqliteDVDatabaseAdapter jobs = SqliteDVDatabaseAdapter.memory();
        addTearDown(jobs.close);
        const DVQueues().useAdapter(DVDatabaseQueueAdapter(jobs));
        final List<String> read = <String>[];
        const DVQueues().register<ReadOrders>((ReadOrders job) async {
          for (final Map<String, Object?> row in await const DVDatabase().query(
            'SELECT body FROM notes',
          )) {
            read.add('${job.label}:${row['body']}');
          }
        });

        await const DVTenants().withTenant(
          'globex',
          () => const DVQueues().dispatch(const ReadOrders('globex')),
        );
        await const DVTenants().withTenant(
          'acme',
          () => const DVQueues().dispatch(const ReadOrders('acme')),
        );
        await const DVQueues().work(maxJobs: 2);

        expect(read, <String>['globex:globex note', 'acme:acme note']);
      },
    );
  });

  group('a jobs table an earlier release created', () {
    test(
      'gains the tenant column, and the jobs already in it run with none',
      () async {
        final Directory dir = Directory.systemTemp.createTempSync(
          'dartvel_job_tenant_old_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final String path = '${dir.path}/jobs.db';

        // The table exactly as the release before this one made it, holding a
        // job that release dispatched.
        final SqliteDVDatabaseAdapter old = SqliteDVDatabaseAdapter.file(path);
        await old.execute('''
        CREATE TABLE dartvel_jobs (
          id VARCHAR(255) PRIMARY KEY,
          queue TEXT NOT NULL,
          payload_name TEXT NOT NULL,
          payload TEXT NOT NULL,
          priority INTEGER NOT NULL,
          max_attempts INTEGER NOT NULL,
          backoff_ms BIGINT NOT NULL,
          created_at BIGINT NOT NULL,
          attempts INTEGER NOT NULL,
          state TEXT NOT NULL,
          last_error TEXT
        )
      ''');
        await old.execute(
          'INSERT INTO dartvel_jobs (id, queue, payload_name, payload, '
          'priority, max_attempts, backoff_ms, created_at, attempts, state, '
          'last_error) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)',
          <Object?>[
            'job-old',
            'default',
            'read_orders',
            '{"label":"old"}',
            0,
            3,
            30000,
            1,
            0,
            'queued',
          ],
        );
        old.close();

        final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(path);
        addTearDown(db.close);
        const DVQueues().useAdapter(DVDatabaseQueueAdapter(db));
        final List<String> ranAs = <String>[];
        const DVQueues().register<ReadOrders>(
          (ReadOrders job) =>
              ranAs.add('${job.label}:${const DVTenants().currentTenant}'),
        );

        await const DVTenants().withTenant(
          'acme',
          () => const DVQueues().dispatch(const ReadOrders('new')),
        );
        const DVTenants().currentTenant = 'globex';

        expect(await const DVQueues().work(maxJobs: 2), 2);
        expect(
          ranAs,
          unorderedEquals(<String>[
            'old:${DVTenants.defaultTenant}',
            'new:acme',
          ]),
        );
      },
    );
  });
}
