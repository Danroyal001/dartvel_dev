// The in-memory database honours the UNIQUE keys a framework table declares.
//
// The meter store relies on its table's unique key to refuse a retry that
// races its original past the in-process check -- two DVMeters, two
// instances, one database. On SQLite, PostgreSQL and MySQL the key holds. On
// the in-memory adapter the key was read and ignored, so the same race
// counted twice there, and every test run on it said the guard worked.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late MemoryDVDatabaseAdapter db;

  setUp(() async {
    db = MemoryDVDatabaseAdapter();
    await db.execute('CREATE TABLE IF NOT EXISTS t (a VARCHAR(10) NOT NULL, '
        'b VARCHAR(10), c BIGINT, UNIQUE (a, b))');
  });

  test('a second row with the same key is refused, naming the constraint',
      () async {
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', 'y', 1]);
    await expectLater(
      db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
          <Object?>['x', 'y', 2]),
      throwsA(predicate((Object e) => '$e'.contains('UNIQUE'))),
    );
    final List<Map<String, Object?>> rows =
        await db.query('SELECT c FROM t');
    expect(rows.map((Map<String, Object?> r) => r['c']), <Object?>[1]);
  });

  test('rows differing in any key column are both kept', () async {
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', 'y', 1]);
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', 'z', 2]);
    expect(await db.query('SELECT c FROM t'), hasLength(2));
  });

  test('NULL is not equal to NULL, as in SQL', () async {
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', null, 1]);
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', null, 2]);
    expect(await db.query('SELECT c FROM t'), hasLength(2));
  });

  test('an update onto an existing key is refused and changes nothing',
      () async {
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', 'y', 1]);
    await db.execute('INSERT INTO t (a, b, c) VALUES (?, ?, ?)',
        <Object?>['x', 'z', 2]);
    await expectLater(
      db.execute('UPDATE t SET b = ? WHERE c = ?', <Object?>['y', 2]),
      throwsA(predicate((Object e) => '$e'.contains('UNIQUE'))),
    );
    final List<Map<String, Object?>> rows =
        await db.query('SELECT b FROM t WHERE c = ?', <Object?>[2]);
    expect(rows.single['b'], 'z');
  });

  test('a column-level PRIMARY KEY is a unique key too', () async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS p (id VARCHAR(10) PRIMARY KEY, v BIGINT)');
    await db.execute(
        'INSERT INTO p (id, v) VALUES (?, ?)', <Object?>['k', 1]);
    await expectLater(
      db.execute('INSERT INTO p (id, v) VALUES (?, ?)', <Object?>['k', 2]),
      throwsA(predicate((Object e) => '$e'.contains('UNIQUE'))),
    );
  });

  group('the meter store on it', () {
    setUp(() => const DVDatabase().configure(MemoryDVDatabaseAdapter()));
    tearDown(() {
      const DVDatabase().unconfigure();
      DVTenants.reset();
    });

    test('a retry racing its original on another instance counts once',
        () async {
      final DVMeterDefinition meter = DVMeterDefinition('api_calls', unit: 'call');
      DateTime now() => DateTime.utc(2026, 9, 15, 12);
      final DVMeters first = DVMeters(store: DVDatabaseMeterStore(), clock: now);
      final DVMeters second =
          DVMeters(store: DVDatabaseMeterStore(), clock: now);

      final List<DVMeterOutcome> outcomes = await Future.wait(<Future<DVMeterOutcome>>[
        first.record(meter, 1, idempotencyKey: 'req-1'),
        second.record(meter, 1, idempotencyKey: 'req-1'),
      ]);

      expect(outcomes.where((DVMeterOutcome o) => o.recorded), hasLength(1));
      expect(await first.usage(meter, tenant: DVTenants.defaultTenant), 1);
    });
  });
}
