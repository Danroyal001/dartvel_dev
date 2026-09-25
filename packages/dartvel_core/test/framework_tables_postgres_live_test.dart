// The framework's own tables on a real PostgreSQL, with real timestamps.
//
// SQLite's INTEGER is 64 bits, so a millisecond or microsecond timestamp fits
// there and every store's suite passes on it. PostgreSQL's INTEGER is 32 bits:
// the same statement creates a table that refuses every row the framework
// writes, with "value out of range for type integer". Nothing about the table
// looks wrong until the first sign-in.
//
// Needs a server: set DARTVEL_TEST_POSTGRES_PORT (and optionally
// DARTVEL_TEST_POSTGRES_HOST, _DATABASE, _USER, _PASSWORD). It skips loudly
// without one and fails -- never skips -- when the variable names a server
// that is not there, so a CI job that sets it cannot go green having checked
// nothing. The server must accept trust or md5 authentication.
@Tags(<String>['live'])
library;

import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
// DVRecordTableRemote is the framework's own: an application asks the model
// for it through Model.offlineRemote.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping(this.to);
  final String to;
}

final DVJobPayloadCodec<_Ping> _pingCodec = DVJobPayloadCodec<_Ping>(
  name: 'dv_w64_ping',
  encode: (_Ping job) => <String, Object?>{'to': job.to},
  decode: (Map<String, Object?> json) => _Ping(json['to']! as String),
);

const Entitlement _analytics = Entitlement('analytics');

const DVPurchaseProduct _pro = DVPurchaseProduct(
  'book_pro',
  billable: DVBillable.digital(play: 'book_pro'),
  entitlements: <Entitlement>{_analytics},
);

const DVPromotion _once = DVPromotion(
  id: 'once',
  code: 'ONCE',
  discount: DVDiscount.percent(10),
  stacking: DVPromotionStacking.group('coupons'),
  maxRedemptionsPerCustomer: 1,
);

/// Every table these tests create, dropped before and after each test.
const List<String> _tables = <String>[
  'dv_w64_sessions',
  'dv_w64_deletions',
  'dv_w64_jobs',
  'dv_w64_grants',
  'dv_w64_notifications',
  'dv_w64_meter_records',
  'dv_w64_meter_reports',
  'dv_w64_redemptions',
  'dv_w64_counters',
  // Names the stores below fix for themselves.
  'dv_capture_log',
  'dv_capture_state',
  'dv_capture_schemas',
  'dv_capture_checkpoints',
  'dv_capture_backfills',
  'dv_warehouse_tombstones',
  'dv_analytics_outbox',
  'dv_analytics_identity',
  'dv_analytics_events',
  'dv_consent_records',
  'dv_agreement_acceptances',
  'dv_agreement_versions',
  'dv_privacy_tombstones',
  'dv_privacy_requests',
  'dv_privacy_requests__history',
  'dv_schema_backfill_chunks',
  'dv_schema_backfill_state',
  'dv_schema_evolution',
  'dv_w64_orders',
  'dv_w64_orders__history',
  'dv_w64_device',
  'dv_w64_device__mutations',
  'dv_w64_device__server',
  'dv_w64_orders__applied',
  'dv_w64_orders__clock',
  'dv_organizations',
  'dv_organizations__history',
  'dv_org_memberships',
  'dv_org_memberships__history',
  'dv_org_invitations',
  'dv_org_domains',
  'dv_org_domains__history',
  'dv_api_keys',
  'dv_api_keys__history',
  'dv_oauth_clients',
  'dv_oauth_clients__history',
  'dv_oauth_codes',
  'dv_oauth_grants',
  'dv_oauth_grants__history',
  'dv_oauth_tokens',
  'dv_oauth_consents',
  'dv_oauth_consents__history',
  'dartvel_content_versions',
  'dartvel_content_versions__history',
];

/// Runs every statement with [schema] first on the search path, so a
/// warehouse table named after a model does not collide with the model.
class _InSchema implements DVDatabaseAdapter {
  _InSchema(this.inner, this.schema);

  final DVDatabaseAdapter inner;
  final String schema;

  Future<void> _path() => inner.execute('SET search_path TO $schema, public');

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    await _path();
    try {
      return await inner.query(sql, params);
    } finally {
      await inner.execute('SET search_path TO public');
    }
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    await _path();
    try {
      return await inner.execute(sql, params);
    } finally {
      await inner.execute('SET search_path TO public');
    }
  }
}

/// A destination that keeps what it is handed.
class _Collected implements DVCaptureSink {
  final List<DVCapturedChange> changes = <DVCapturedChange>[];

  @override
  String get name => 'collected';

  @override
  bool get deduplicates => true;

  @override
  Future<void> write(DVCaptureBatch batch) async =>
      changes.addAll(batch.changes);

  @override
  Future<void> evolve(DVCaptureSchemaChange change) async {}

  @override
  Future<void> erase(List<DVCapturedChange> changes) async {}

  @override
  Future<void> backfillComplete(
    String model,
    int throughSequence, {
    String? tenant,
  }) async {}
}

class _Step extends DVAnalyticsEvent {
  const _Step(this.name);
  @override
  final String name;
  @override
  DVConsentCategory get category => _product;
  @override
  Map<String, Object?> get properties => const <String, Object?>{'n': 1};
}

const DVConsentCategory _product = DVConsentCategory('product');

final DVConsentPolicy _policy = DVConsentPolicy(
  version: '2026-09-01',
  categories: const <DVConsentDeclaration>[
    DVConsentDeclaration(DVConsentCategory.essential, required: true),
    DVConsentDeclaration(_product),
  ],
);

final DVApiScopes _apiScopes = DVApiScopes(const <String, List<String>>{
  'orders:read': <String>['Order.view'],
});

class _Page {
  const _Page(this.route, this.title);
  final String route;
  final String title;
}

void main() {
  final String? port = io.Platform.environment['DARTVEL_TEST_POSTGRES_PORT'];
  if (port == null || port.isEmpty) {
    test(
      'framework tables on PostgreSQL (skipped: DARTVEL_TEST_POSTGRES_PORT '
      'is not set)',
      () {},
      skip:
          'Set DARTVEL_TEST_POSTGRES_PORT to a PostgreSQL with trust or md5 '
          'authentication to run these.',
    );
    return;
  }

  DVPostgresDatabaseAdapter open() => DVPostgresDatabaseAdapter(
    host: io.Platform.environment['DARTVEL_TEST_POSTGRES_HOST'] ?? '127.0.0.1',
    port: int.parse(port),
    database:
        io.Platform.environment['DARTVEL_TEST_POSTGRES_DATABASE'] ??
        'dartvel_test',
    user: io.Platform.environment['DARTVEL_TEST_POSTGRES_USER'] ?? 'postgres',
    password: io.Platform.environment['DARTVEL_TEST_POSTGRES_PASSWORD'],
    sslMode: DVSslMode.disable,
  );

  late DVPostgresDatabaseAdapter db;

  Future<void> dropAll() async {
    for (final String table in _tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  Future<Map<String, String>> columnTypes(String table) async =>
      <String, String>{
        for (final Map<String, Object?> row in await db.query(
          'SELECT column_name, data_type FROM information_schema.columns '
          'WHERE table_schema = current_schema() AND table_name = ?',
          <Object?>[table],
        ))
          '${row['column_name']}': '${row['data_type']}',
      };

  setUp(() async {
    db = open();
    await dropAll();
    const DVJobPayloadCodecs()
      ..clear()
      ..register(_pingCodec);
  });

  tearDown(() async {
    const DVJobPayloadCodecs().clear();
    const DVDatabase().unconfigure();
    await dropAll();
    await db.close();
  });

  // Now, with the milliseconds and microseconds a real clock has: a value
  // rounded to the second would still overflow, but would hide a column that
  // silently truncated.
  final DateTime now = DateTime.now().toUtc();

  test('a session is stored and read back with its timestamps', () async {
    final DVDatabaseSessionStore store = DVDatabaseSessionStore(
      db,
      table: 'dv_w64_sessions',
    );
    await store.insert(
      DVSessionRecord(
        'hash-1',
        DVSession(
          id: 's1',
          userId: 'u1',
          createdAt: now,
          lastSeenAt: now,
          mfaSatisfiedAt: now,
        ),
      ),
    );
    await store.revoke('s1', now);

    final DVSessionRecord? read = await store.byTokenHash('hash-1');
    expect(read, isNotNull);
    expect(
      read!.session.createdAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      read.session.lastSeenAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      read.session.mfaSatisfiedAt!.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      read.session.revokedAt!.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
  });

  test('an account deletion is scheduled with its dates', () async {
    final DVAccountDeletionStore store = DVAccountDeletionStore(
      db,
      table: 'dv_w64_deletions',
    );
    final DateTime due = now.add(const Duration(days: 30));
    await store.schedule('u1', requestedAt: now, dueAt: due);

    final DVAccountDeletion? read = await store.find('u1');
    expect(read, isNotNull);
    expect(
      read!.requestedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(read.dueAt.millisecondsSinceEpoch, due.millisecondsSinceEpoch);
  });

  test('a queued job keeps its creation time and a long backoff', () async {
    final DVDatabaseQueueAdapter queue = DVDatabaseQueueAdapter(
      db,
      tableName: 'dv_w64_jobs',
    );
    // 30 days is 2,592,000,000 ms: past 32 bits on its own, before any
    // timestamp is involved.
    await queue.enqueue(
      'mail',
      const _Ping('a'),
      backoff: const Duration(days: 30),
    );

    final DVJobEnvelope<dynamic>? job = await queue.reserve('mail');
    expect(job, isNotNull);
    expect(job!.backoff, const Duration(days: 30));
    expect(
      job.createdAt.difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 5)),
    );
  });

  test('a jobs table an earlier release made gains the tenant column, and '
      'keeps its jobs', () async {
    // The table exactly as the release before the tenant column made it,
    // with a job in it: a column added to the DDL alone would exist on every
    // fresh install and on no upgraded one, and the first dispatch would fail.
    await db.execute(
      'CREATE TABLE dv_w64_jobs (id VARCHAR(255) PRIMARY KEY, '
      'queue TEXT NOT NULL, payload_name TEXT NOT NULL, payload TEXT NOT NULL, '
      'priority INTEGER NOT NULL, max_attempts INTEGER NOT NULL, '
      'backoff_ms BIGINT NOT NULL, created_at BIGINT NOT NULL, '
      'attempts INTEGER NOT NULL, state TEXT NOT NULL, last_error TEXT)',
    );
    await db.execute(
      'INSERT INTO dv_w64_jobs (id, queue, payload_name, payload, priority, '
      'max_attempts, backoff_ms, created_at, attempts, state) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'job-old', 'mail', _pingCodec.name, '{"to":"old"}', 0, 3, 30000, 1,
        0, 'queued',
      ],
    );
    final DVDatabaseQueueAdapter queue = DVDatabaseQueueAdapter(
      db,
      tableName: 'dv_w64_jobs',
    );

    await queue.enqueue('mail', const _Ping('new'), tenant: 'acme');

    expect((await columnTypes('dv_w64_jobs'))['tenant'], 'text');
    final DVJobEnvelope<dynamic>? old = await queue.reserve('mail');
    final DVJobEnvelope<dynamic>? fresh = await queue.reserve('mail');
    expect(<String?>[old!.id, old.tenant], <String?>['job-old', null]);
    expect(fresh!.tenant, 'acme');
  });

  test('a purchase grant and its notification claim are stored', () async {
    final DVFakeStoreAdapter play = DVFakeStoreAdapter(
      DVStore.play,
      signingKey: 'k',
      acknowledgementWindow: const Duration(days: 3),
    );
    DVDatabasePurchaseLedger ledger() => DVDatabasePurchaseLedger(
      db,
      grantsTable: 'dv_w64_grants',
      notificationsTable: 'dv_w64_notifications',
    );
    play.issue(
      'r1',
      DVStoreTransaction(
        store: DVStore.play,
        originalTransactionId: 'otx_1',
        transactionId: 'otx_1_1',
        storeProductId: 'book_pro',
        purchasedAt: now,
        expiresAt: now.add(const Duration(days: 30)),
        signedAt: now,
      ),
    );
    await DVPurchases(
      products: const <DVPurchaseProduct>[_pro],
      stores: <DVStoreAdapter>[play],
      ledger: ledger(),
      clock: () => now,
      logger: DVLogger(),
    ).verifyPurchase(DVStore.play, 'r1', customer: 'alice');

    final DVPurchaseGrant? grant = await ledger().find(DVStore.play, 'otx_1');
    expect(grant, isNotNull);
    expect(grant!.purchasedAt, now);
    expect(await ledger().claimNotification(DVStore.play, 'n1'), isTrue);
  });

  test('a meter record and a queued report are stored', () async {
    const DVDatabase().configure(db);
    final DVMeterPeriod period = DVMeterPeriod.calendarMonth(now);
    final DVDatabaseMeterStore records = DVDatabaseMeterStore(
      table: 'dv_w64_meter_records',
    );
    expect(
      await records.add(
        DVMeterRecord(
          tenant: 't1',
          meter: 'api_calls',
          idempotencyKey: 'k1',
          amount: 1,
          at: now,
          period: period,
        ),
      ),
      isTrue,
    );
    expect(
      await records.recordsIn(tenant: 't1', meter: 'api_calls', period: period),
      hasLength(1),
    );

    // A gauge's reading as Dart holds it. REAL is four bytes on PostgreSQL,
    // which keeps seven digits and would store 16777216 for this.
    await records.add(
      DVMeterRecord(
        tenant: 't1',
        meter: 'storage_gb',
        idempotencyKey: 'k2',
        amount: 16777217.25,
        at: now,
        period: period,
      ),
    );
    expect(
      (await records.recordsIn(
        tenant: 't1',
        meter: 'storage_gb',
        period: period,
      )).single.amount,
      16777217.25,
    );

    final DVDatabaseMeterReportQueue reports = DVDatabaseMeterReportQueue(
      table: 'dv_w64_meter_reports',
    );
    // Bytes egressed in a month: a quantity, not a timestamp, and past 32
    // bits all the same.
    await reports.put(
      DVMeterReport(
        tenant: 't1',
        meter: 'egress_bytes',
        period: period,
        quantity: 5000000000,
        idempotencyKey: 'r1',
        status: DVMeterReportStatus.queued,
      ),
    );
    final List<DVMeterReport> pending = await reports.pending();
    expect(pending, hasLength(1));
    expect(pending.single.quantity, 5000000000);
    expect(pending.single.period.start, period.start);
  });

  test('a promotion redemption is stored', () async {
    final DVDatabasePromotionLedger ledger = DVDatabasePromotionLedger(
      db,
      redemptionsTable: 'dv_w64_redemptions',
      countersTable: 'dv_w64_counters',
    );
    await ledger.redeem(_once, customerKey: 'alice', orderId: 'o1', at: now);
    expect(await ledger.redeemedFor('once', 'o1'), isTrue);
  });

  // Each store below declared its columns with no type, which SQLite accepts
  // and PostgreSQL and MySQL refuse at CREATE TABLE: none of them could make
  // its tables on a server at all.

  test('the change-capture log takes a change and delivers it', () async {
    final DVCapture capture = DVCapture(
      database: db,
      retention: const Duration(days: 7),
    );
    await capture.ensureSchema();
    final DVRecordTable orders = DVRecordTable(
      table: 'dv_w64_orders',
      key: 'id',
      columns: const <String>['id', 'quantity'],
      database: db,
    );
    await capture.record(
      table: orders,
      operation: DVCaptureOp.insert,
      key: 'o1',
      version: 1,
      values: const <String, Object?>{'id': 'o1', 'quantity': 3},
    );

    final _Collected sink = _Collected();
    await capture.consumer('wh', sink: sink).deliverOnce();
    expect(sink.changes, hasLength(1));
    expect(sink.changes.single.key, 'o1');
    expect(sink.changes.single.version, 1);
    expect(sink.changes.single.values['quantity'], 3);
    expect(sink.changes.single.sequence, await capture.head());
    expect(
      await capture.consumer('wh', sink: sink).checkpoint(),
      await capture.head(),
    );
  });

  test('a typed record table keeps its history and feeds a warehouse', () async {
    final DVCapture capture = DVCapture(
      database: db,
      retention: const Duration(days: 7),
    );
    await capture.ensureSchema();
    final DVRecordTable orders = DVRecordTable(
      table: 'dv_w64_orders',
      key: 'id',
      columns: const <String>['id', 'quantity', 'note'],
      types: const <String, String>{
        'id': 'TEXT',
        'quantity': 'BIGINT',
        'note': 'TEXT',
      },
      history: const DVHistory(),
      softDelete: true,
      capture: capture,
      database: db,
    );
    await orders.ensureSchema();
    final DVRecord first = (await orders.write(<String, Object?>{
      'id': 'o1',
      'quantity': 5000000000,
      'note': '10',
    })).record;
    await orders.write(<String, Object?>{
      'id': 'o1',
      'quantity': 5000000001,
      'note': '10',
    }, base: first);
    await orders.delete('o1');

    final DVRecord read = (await orders.read('o1', withDeleted: true))!;
    expect(read.version, 3);
    expect(read.deletedAt, isNotNull);
    expect(read.values['quantity'], 5000000001);
    final List<DVHistoryEntry> history = await orders.history('o1');
    expect(history.map((DVHistoryEntry e) => e.version), <int>[1, 2, 3]);
    expect(history.last.deleted, isTrue);
    expect(history[1].changes['quantity']!.to, 5000000001);

    // The warehouse table is named after the model, so it lives beside the
    // source in a schema of its own.
    await db.execute('DROP SCHEMA IF EXISTS dv_w64_wh CASCADE');
    await db.execute('CREATE SCHEMA dv_w64_wh');
    try {
      final DVDatabaseAdapter inWarehouse = _InSchema(db, 'dv_w64_wh');
      final DVWarehouseSink sink = DVWarehouseSink(
        database: inWarehouse,
        fieldType: (String model, String field) =>
            field == 'quantity' ? DVFieldType.integer : DVFieldType.text,
      );
      await orders.restore('o1');
      await capture.consumer('wh', sink: sink).deliverOnce();
      final List<Map<String, Object?>> rows = await db.query(
        'SELECT _dv_key, _dv_version, quantity, note FROM dv_w64_wh.dv_w64_orders',
      );
      expect(rows, <Map<String, Object?>>[
        <String, Object?>{
          '_dv_key': 'o1',
          '_dv_version': 4,
          'quantity': 5000000001,
          'note': '10',
        },
      ]);
    } finally {
      await db.execute('DROP SCHEMA IF EXISTS dv_w64_wh CASCADE');
    }
  });

  test('an offline store replays onto a typed record table', () async {
    DVRecordTable table(String name) => DVRecordTable(
      table: name,
      key: 'id',
      columns: const <String>['id', 'quantity'],
      types: const <String, String>{'id': 'TEXT', 'quantity': 'BIGINT'},
      database: db,
    );
    final DVOfflineStore device = DVOfflineStore(
      table: table('dv_w64_device'),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );
    await device.ensureSchema();
    await device.write(<String, Object?>{'id': 'o1', 'quantity': 1});
    await device.write(<String, Object?>{'id': 'o1', 'quantity': 5000000000});
    expect(await device.pending(), hasLength(2));

    final DVRecordTableRemote server = DVRecordTableRemote(
      table('dv_w64_orders'),
      strategy: DVConflict.lastWriteWins,
    );
    await server.ensureSchema();
    await device.replay(server);
    expect(await device.pending(), isEmpty);
    expect((await server.table.read('o1'))!.values['quantity'], 5000000000);

    // The same mutation twice is applied once.
    final DVOfflineStore reopened = DVOfflineStore(
      table: table('dv_w64_device'),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );
    await reopened.ensureSchema();
    expect(await reopened.pending(), isEmpty);
  });

  test('consent is recorded and read back', () async {
    final DVConsent consent = DVConsent(
      policy: _policy,
      database: db,
      installId: 'install-1',
      clock: () => now,
    );
    await consent.ensureSchema();
    await consent.load();
    expect(
      await consent.record(<DVConsentCategory, bool>{_product: true}),
      isTrue,
    );
    await consent.record(<DVConsentCategory, bool>{_product: false});

    final List<DVConsentRecord> records = await consent.records();
    expect(records.map((DVConsentRecord r) => r.seq), <int>[1, 2]);
    expect(records.last.answers['product'], isFalse);
    expect(records.last.recordedAt, now);
  });

  test('an analytics event goes through the outbox to the store', () async {
    final DVConsent consent = DVConsent(
      policy: _policy,
      database: db,
      installId: 'install-1',
      clock: () => now,
    );
    await consent.ensureSchema();
    await consent.load();
    await consent.record(<DVConsentCategory, bool>{_product: true});
    final DVAnalyticsDatabaseStore store = DVAnalyticsDatabaseStore(
      database: db,
    );
    final DVAnalytics analytics = DVAnalytics(
      consent: consent,
      database: db,
      store: store,
      clock: () => now,
    );
    await analytics.ensureSchema();
    expect((await analytics.track(const _Step('opened'))).accepted, isTrue);
    await analytics.flush();

    final List<DVAnalyticsRecord> events = await store.events();
    expect(events.map((DVAnalyticsRecord e) => e.name), <String>['opened']);
    expect(events.single.properties['n'], 1);

    // A second pipeline over the same database keeps the anonymous id.
    final DVAnalytics again = DVAnalytics(
      consent: consent,
      database: db,
      store: store,
      clock: () => now,
    );
    await again.ensureSchema();
    expect(again.anonymousId, analytics.anonymousId);
  });

  test('an agreement acceptance is recorded with its version', () async {
    final DVAgreements agreements = DVAgreements(
      agreements: <DVAgreement>[
        DVAgreement(id: 'terms', version: '2026-09-01', route: '/terms'),
      ],
      database: db,
      clock: () => now,
    );
    await agreements.ensureSchema();
    await agreements.accept('terms', actor: 'ada');

    final List<DVAcceptance> read = await agreements.acceptances(actor: 'ada');
    expect(read.single.version, '2026-09-01');
    expect(await agreements.needsAcceptance('terms', actor: 'ada'), isFalse);
  });

  test('an erasure leaves its tombstone and its request record', () async {
    final DVPrivacy privacy = DVPrivacy(
      models: const <DVPrivacyModel>[],
      database: db,
      signingKey: List<int>.generate(32, (int i) => i),
      now: () => now,
    );
    await privacy.ensureSchema();
    await privacy.erase(subject: 'ada', reason: 'asked');

    expect(
      await db.query('SELECT subject FROM dv_privacy_tombstones'),
      <Map<String, Object?>>[
        <String, Object?>{'subject': privacy.pseudonym('ada')},
      ],
    );
    expect(await privacy.requests.all(), hasLength(1));
  });

  test('a backfill records its chunks and its state', () async {
    await db.execute(
      'CREATE TABLE dv_w64_orders (id BIGINT PRIMARY KEY, total TEXT, '
      'total_next BIGINT)',
    );
    for (int i = 1; i <= 3; i++) {
      await db.execute(
        'INSERT INTO dv_w64_orders (id, total) VALUES (?, ?)',
        <Object?>[i, '${i * 10}'],
      );
    }
    final DVBackfill backfill = DVBackfill(
      database: db,
      id: 'orders.total',
      table: 'dv_w64_orders',
      key: 'id',
      source: 'total',
      target: 'total_next',
      convert: (Object? total) => int.parse('$total'),
      chunkSize: 2,
    );
    await backfill.pause();
    expect(await backfill.paused, isTrue);
    await backfill.resume();
    await backfill.run();

    final DVBackfillProgress progress = await backfill.progress();
    expect(progress.complete, isTrue);
    expect(progress.chunks.map((DVBackfillChunk c) => c.first), <Object?>[
      1,
      3,
    ]);
    expect(progress.chunks.map((DVBackfillChunk c) => c.last), <Object?>[2, 3]);
    expect(
      await db.query('SELECT total_next FROM dv_w64_orders ORDER BY id'),
      <Map<String, Object?>>[
        <String, Object?>{'total_next': 10},
        <String, Object?>{'total_next': 20},
        <String, Object?>{'total_next': 30},
      ],
    );
  });

  test('a schema evolution is saved and loaded', () async {
    final DVSchemaEvolutionStore store = DVSchemaEvolutionStore(db);
    final DVSchemaEvolution evolution = DVSchemaEvolution.expand(
      id: 'orders.total',
      release: 'r1',
      at: now,
      expandProtocol: 8,
      verificationWindow: const Duration(hours: 1),
    );
    await store.save(evolution);
    await store.save(evolution);
    expect((await store.load('orders.total'))!.phase, evolution.phase);
  });

  test('an API key is stored on its tenant', () async {
    final DVApiKeys keys = DVApiKeys(
      database: db,
      scopes: _apiScopes,
      clock: () => now,
    );
    await keys.ensureSchema();
    final DVIssuedApiKey issued = await keys.issue(
      tenant: 'acme',
      scopes: const <String>['orders:read'],
    );
    expect(issued.key.tenant, 'acme');
    expect(await keys.find(issued.key.id), isNotNull);
    expect(await keys.audit(issued.key.id), hasLength(1));
  });

  test('an OAuth client is registered', () async {
    final DVOAuthProvider oauth = DVOAuthProvider(
      database: db,
      scopes: _apiScopes,
      clock: () => now,
    );
    await oauth.ensureSchema();
    await oauth.registerClient(
      name: 'Partner',
      redirectUris: const <String>['https://partner.example/cb'],
      scopes: const <String>['orders:read'],
      public: true,
    );
    final List<Map<String, Object?>> clients = await db.query(
      'SELECT name, public FROM dv_oauth_clients',
    );
    expect(clients.single['name'], 'Partner');
    expect(clients.single['public'], 1);
  });

  test('a content draft is stored with its history', () async {
    const DVAuthAuthorization authorization = DVAuthAuthorization();
    for (final String action in DVContentAction.all) {
      authorization.register<String, _Page>(
        action,
        (String _, _Page _) => true,
      );
    }
    final DVContentWorkflow<_Page> workflow = DVContentWorkflow<_Page>(
      kind: 'page',
      database: db,
      encode: (_Page page) => <String, Object?>{
        'route': page.route,
        'title': page.title,
      },
      decode: (Map<String, Object?> json) =>
          _Page('${json['route']}', '${json['title']}'),
      documentId: (_Page page) => page.route,
      actorId: (Object? user) => user! as String,
      clock: () => now,
    );
    await workflow.ensureSchema();
    final DVContentVersion<_Page> draft = await workflow.draft(
      const _Page('/about', 'About'),
      as: 'ada',
    );
    final DVContentVersion<_Page> edited = await workflow.edit(
      draft,
      const _Page('/about', 'About us'),
      as: 'ada',
    );
    expect(edited.revision, 2);
    expect(
      (await workflow.versions('/about')).single.document.title,
      'About us',
    );
    expect(await workflow.history('/about'), isNotEmpty);
  });

  group('a meter table an earlier release made with a REAL amount', () {
    const String before =
        'CREATE TABLE dv_w64_meter_records (dv_tenant TEXT NOT NULL, '
        'meter TEXT NOT NULL, idempotency_key TEXT NOT NULL, '
        'amount REAL NOT NULL, at_us BIGINT NOT NULL, '
        'period_start_us BIGINT NOT NULL, period_end_us BIGINT NOT NULL, '
        'UNIQUE (dv_tenant, meter, period_start_us, idempotency_key))';

    DVMeterRecord record(String key) => DVMeterRecord(
      tenant: 't1',
      meter: 'gb_hours',
      idempotencyKey: key,
      amount: 123456.789,
      at: now,
      period: DVMeterPeriod.calendarMonth(now),
    );

    test('is widened to DOUBLE PRECISION when it is empty', () async {
      await db.execute(before);
      const DVDatabase().configure(db);
      await DVDatabaseMeterStore(
        table: 'dv_w64_meter_records',
      ).add(record('k'));
      expect(
        (await columnTypes('dv_w64_meter_records'))['amount'],
        'double precision',
      );
    });

    test('with rows in it keeps working, and is not rewritten', () async {
      await db.execute(before);
      await db.execute(
        'INSERT INTO dv_w64_meter_records (dv_tenant, meter, idempotency_key, '
        'amount, at_us, period_start_us, period_end_us) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>['t0', 'gb_hours', 'old', 1.5, 1, 1, 2],
      );
      const DVDatabase().configure(db);
      expect(
        await DVDatabaseMeterStore(
          table: 'dv_w64_meter_records',
        ).add(record('k')),
        isTrue,
      );
      expect((await columnTypes('dv_w64_meter_records'))['amount'], 'real');
    });
  });

  group('a table created by an earlier release', () {
    // The statement this release's session store used, verbatim.
    const String before =
        'CREATE TABLE dv_w64_sessions ('
        'token_hash TEXT, id TEXT, user_id TEXT, tenant TEXT, '
        'created_at INTEGER, last_seen_at INTEGER, mfa_at INTEGER, '
        'revoked_at INTEGER, device TEXT, location TEXT, claims TEXT)';

    DVSessionRecord record() => DVSessionRecord(
      'hash-1',
      DVSession(id: 's1', userId: 'u1', createdAt: now, lastSeenAt: now),
    );

    test('is widened when it is empty, and then takes a session', () async {
      await db.execute(before);

      await DVDatabaseSessionStore(
        db,
        table: 'dv_w64_sessions',
      ).insert(record());

      final Map<String, String> types = await columnTypes('dv_w64_sessions');
      for (final String column in <String>[
        'created_at',
        'last_seen_at',
        'mfa_at',
        'revoked_at',
      ]) {
        expect(types[column], 'bigint', reason: column);
      }
    });

    test('with rows in it is refused with the plan, not rewritten', () async {
      await db.execute(before);
      // A row a 32-bit column can hold. No framework write could have put
      // one there on PostgreSQL; a hand-written one, or a MySQL server not in
      // strict mode clamping the value, can.
      await db.execute(
        'INSERT INTO dv_w64_sessions (token_hash, id, created_at) '
        'VALUES (?, ?, ?)',
        <Object?>['old', 'old', 1],
      );

      await expectLater(
        DVDatabaseSessionStore(db, table: 'dv_w64_sessions').insert(record()),
        throwsA(
          isA<StateError>()
              .having(
                (StateError e) => e.message,
                'message',
                contains('blocking  change type of dv_w64_sessions.created_at'),
              )
              .having((StateError e) => e.message, 'message', contains('1 row'))
              .having(
                (StateError e) => e.message,
                'message',
                contains('ALTER TABLE dv_w64_sessions'),
              ),
        ),
      );
      expect((await columnTypes('dv_w64_sessions'))['created_at'], 'integer');
      expect(await db.query('SELECT id FROM dv_w64_sessions'), hasLength(1));
    });
  });
}
