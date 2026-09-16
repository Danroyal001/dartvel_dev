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
];

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
