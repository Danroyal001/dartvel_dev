// Runs against a real MySQL/MariaDB at localhost:3306 — no scripted server,
// no fake. Skips visibly when none is reachable rather than passing silently.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<bool> _reachable() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      3306,
      timeout: const Duration(seconds: 1),
    );
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _reachable()) {
    test(
      'mysql adapter (skipped: no MySQL at localhost:3306)',
      () {},
      skip: 'Start mariadb-server with a dartvel_test database to run these.',
    );
    return;
  }

  late DVMySqlDatabaseAdapter adapter;

  setUp(() async {
    adapter = DVMySqlDatabaseAdapter(
      database: 'dartvel_test',
      user: 'dartvel',
      password: 'dartvel',
    );
    await adapter.execute('DROP TABLE IF EXISTS dv_people');
    await adapter.execute(
      'CREATE TABLE dv_people (slug VARCHAR(64) PRIMARY KEY, name TEXT, '
      'age INT, height DOUBLE, active BOOLEAN, joined DATETIME)',
    );
  });

  tearDown(() async {
    await adapter.execute('DROP TABLE IF EXISTS dv_people');
    await adapter.close();
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
        DateTime.utc(1852, 11, 27, 9, 30),
      ],
    );
    expect(inserted, 1);

    final rows = await adapter.query(
      'SELECT * FROM dv_people WHERE slug = ?',
      <Object?>['ada'],
    );
    expect(rows, hasLength(1));
    final row = rows.single;
    // Real Dart types out of the binary protocol, not text.
    expect(row['name'], 'Ada Lovelace');
    expect(row['age'], 36);
    expect(row['height'], closeTo(1.65, 0.0001));
    expect(row['active'], 1);
    expect(row['joined'], DateTime.utc(1852, 11, 27, 9, 30));
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
      await adapter.execute(
        'INSERT INTO dv_people (slug) VALUES (?)',
        <Object?>[slug],
      );
    }

    expect(await adapter.execute("UPDATE dv_people SET name = 'x'"), 3);
    expect(
      await adapter.execute(
        'DELETE FROM dv_people WHERE slug <> ?',
        <Object?>['a'],
      ),
      2,
    );
  });

  test('a SQL error surfaces with its code and the connection survives',
      () async {
    await expectLater(
      adapter.query('SELECT * FROM no_such_table'),
      throwsA(
        isA<DVMySqlException>().having(
          (DVMySqlException e) => e.code,
          'code',
          1146, // ER_NO_SUCH_TABLE
        ),
      ),
    );

    // The next statement on the same connection still works, which is what
    // proves the failed exchange was fully consumed.
    expect(
      (await adapter.query('SELECT 1 AS one')).single['one'],
      1,
    );
  });

  test('a malicious parameter is data, not SQL', () async {
    const hostile = "x'; DROP TABLE dv_people; --";
    await adapter.execute(
      'INSERT INTO dv_people (slug, name) VALUES (?, ?)',
      <Object?>['h', hostile],
    );

    final row = (await adapter.query(
      'SELECT name FROM dv_people WHERE slug = ?',
      <Object?>['h'],
    ))
        .single;
    expect(row['name'], hostile);
    // The table is demonstrably still there.
    expect(await adapter.query('SELECT COUNT(*) AS n FROM dv_people'),
        isNotEmpty);
  });

  test('multi-byte text survives the length-encoded round trip', () async {
    const value = 'naïve — 😀 café';
    await adapter.execute(
      'INSERT INTO dv_people (slug, name) VALUES (?, ?)',
      <Object?>['u', value],
    );

    expect(
      (await adapter.query(
        'SELECT name FROM dv_people WHERE slug = ?',
        <Object?>['u'],
      ))
          .single['name'],
      value,
    );
  });

  test('several statements run in sequence on one connection', () async {
    // Each exchange must be consumed exactly, or the next reply reads this
    // one's tail.
    for (var i = 0; i < 5; i++) {
      await adapter.execute(
        'INSERT INTO dv_people (slug, age) VALUES (?, ?)',
        <Object?>['p$i', i],
      );
      final rows = await adapter.query('SELECT COUNT(*) AS n FROM dv_people');
      expect(rows.single['n'], i + 1);
    }
  });

  test('the shared cache adapter runs unchanged on MySQL', () async {
    // DVDatabaseCacheAdapter was written against SQLite; MySQL uses the same
    // `?` placeholder, so it should need no translation at all.
    final cache = DVDatabaseCacheAdapter(adapter, tableName: 'dv_my_cache');
    addTearDown(() => adapter.execute('DROP TABLE IF EXISTS dv_my_cache'));

    await cache.write('greeting', <String, Object?>{'text': 'hello'}, null);
    expect(await cache.read('greeting'), <String, Object?>{'text': 'hello'});
    await cache.remove('greeting');
    expect(await cache.read('greeting'), isNull);
  });
}
