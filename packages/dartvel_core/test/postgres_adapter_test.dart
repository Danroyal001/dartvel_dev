// Runs against a real PostgreSQL at localhost:5432 — no scripted server, no
// fake. Skips visibly when none is reachable rather than passing silently.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<bool> _postgresReachable() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      5432,
      timeout: const Duration(seconds: 1),
    );
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _postgresReachable()) {
    test(
      'postgres adapter (skipped: no PostgreSQL at localhost:5432)',
      () {},
      skip: 'Start a local postgresql with a dartvel_test database to run '
          'the Postgres adapter tests.',
    );
    return;
  }

  late DVPostgresDatabaseAdapter adapter;

  setUp(() async {
    adapter = DVPostgresDatabaseAdapter(database: 'dartvel_test');
    await adapter.execute('DROP TABLE IF EXISTS dv_people');
    await adapter.execute(
      'CREATE TABLE dv_people (slug TEXT PRIMARY KEY, name TEXT, '
      'age INT, height DOUBLE PRECISION, active BOOLEAN, joined TIMESTAMP)',
    );
  });

  tearDown(() async {
    await adapter.execute('DROP TABLE IF EXISTS dv_people');
    await adapter.close();
  });

  test('placeholder translation leaves quoted question marks alone', () {
    expect(
      DVPostgresDatabaseAdapter.translatePlaceholders(
        "SELECT * FROM t WHERE a = ? AND b = 'what?' AND c = ?",
      ),
      "SELECT * FROM t WHERE a = \$1 AND b = 'what?' AND c = \$2",
    );
  });

  test('insert, query and typed decoding round-trip', () async {
    final inserted = await adapter.execute(
      'INSERT INTO dv_people VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        'ada',
        'Ada Lovelace',
        36,
        1.65,
        true,
        DateTime.utc(1852, 11, 27),
      ],
    );
    expect(inserted, 1);

    final rows = await adapter.query(
      'SELECT * FROM dv_people WHERE slug = ?',
      <Object?>['ada'],
    );
    expect(rows, hasLength(1));
    final row = rows.single;
    // Real Dart types back out, not text: ints, doubles, bools, timestamps.
    expect(row['name'], 'Ada Lovelace');
    expect(row['age'], 36);
    expect(row['height'], 1.65);
    expect(row['active'], isTrue);
    expect(row['joined'], DateTime.utc(1852, 11, 27));
  });

  test('null parameters and null columns survive both directions', () async {
    await adapter.execute(
      'INSERT INTO dv_people (slug, name) VALUES (?, ?)',
      <Object?>['ghost', null],
    );

    final row = (await adapter.query(
      'SELECT name, age FROM dv_people WHERE slug = ?',
      <Object?>['ghost'],
    ))
        .single;
    expect(row['name'], isNull);
    expect(row['age'], isNull);
  });

  test('execute reports affected rows for updates and deletes', () async {
    for (final slug in <String>['a', 'b', 'c']) {
      await adapter
          .execute('INSERT INTO dv_people (slug) VALUES (?)', <Object?>[slug]);
    }

    expect(
      await adapter.execute("UPDATE dv_people SET name = 'x'"),
      3,
    );
    expect(
      await adapter.execute(
        'DELETE FROM dv_people WHERE slug != ?',
        <Object?>['a'],
      ),
      2,
    );
  });

  test('a SQL error surfaces with its SQLSTATE and the connection survives',
      () async {
    await expectLater(
      adapter.query('SELECT * FROM no_such_table'),
      throwsA(
        isA<DVPostgresException>().having(
          (DVPostgresException e) => e.code,
          'code',
          '42P01',
        ),
      ),
    );

    // The next query on the same connection still works.
    expect(await adapter.query('SELECT 1 AS one'), <Map<String, Object?>>[
      <String, Object?>{'one': 1},
    ]);
  });

  test('a malicious parameter is data, not SQL', () async {
    const hostile = "x'; DROP TABLE dv_people; --";
    await adapter.execute(
      'INSERT INTO dv_people (slug, name) VALUES (?, ?)',
      <Object?>['h', hostile],
    );

    final row = (await adapter
            .query('SELECT name FROM dv_people WHERE slug = ?', <Object?>['h']))
        .single;
    expect(row['name'], hostile);
    // The table is demonstrably still there.
    expect(await adapter.query('SELECT COUNT(*) AS n FROM dv_people'),
        isNotEmpty);
  });

  test('the shared cache adapter runs unchanged on Postgres', () async {
    // DVDatabaseCacheAdapter was written against SQLite; the `?` translation
    // is what lets the same SQL run here.
    final cache = DVDatabaseCacheAdapter(adapter, tableName: 'dv_pg_cache');
    addTearDown(() => adapter.execute('DROP TABLE IF EXISTS dv_pg_cache'));

    await cache.write('greeting', <String, Object?>{'text': 'hello'}, null);
    expect(
      await cache.read('greeting'),
      <String, Object?>{'text': 'hello'},
    );
    await cache.remove('greeting');
    expect(await cache.read('greeting'), isNull);
  });
}
