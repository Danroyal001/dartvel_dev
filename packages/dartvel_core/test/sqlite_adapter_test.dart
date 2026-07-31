import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteDVDatabaseAdapter', () {
    late SqliteDVDatabaseAdapter db;

    setUp(() {
      db = SqliteDVDatabaseAdapter.memory();
    });
    tearDown(() => db.close());

    test('executes real DDL and DML, not a fixed set of statement shapes',
        () async {
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          age INTEGER NOT NULL
        );
      ''');

      expect(
        await db.execute(
          'INSERT INTO users (name, age) VALUES (?, ?)',
          <Object?>['Ada', 36],
        ),
        1,
      );
      await db.execute(
        'INSERT INTO users (name, age) VALUES (?, ?)',
        <Object?>['Grace', 45],
      );

      final rows =
          await db.query('SELECT id, name, age FROM users ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows.first, <String, Object?>{'id': 1, 'name': 'Ada', 'age': 36});
      expect(rows.last['name'], 'Grace');
    });

    test('supports WHERE, UPDATE, aggregates and JOIN', () async {
      await db.execute(
        'CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL);',
      );
      await db.execute('''
        CREATE TABLE books (
          id INTEGER PRIMARY KEY,
          author_id INTEGER NOT NULL REFERENCES authors(id),
          title TEXT NOT NULL
        );
      ''');
      await db.execute(
        'INSERT INTO authors (id, name) VALUES (1, ?), (2, ?)',
        <Object?>['Ada', 'Grace'],
      );
      await db.execute(
        'INSERT INTO books (id, author_id, title) VALUES (1, 1, ?), '
        '(2, 1, ?), (3, 2, ?)',
        <Object?>['Notes', 'Engine', 'Compiler'],
      );

      // WHERE + parameter binding
      final ada = await db.query(
        'SELECT title FROM books WHERE author_id = ? ORDER BY id',
        <Object?>[1],
      );
      expect(ada.map((row) => row['title']), <String>['Notes', 'Engine']);

      // JOIN + aggregate
      final counts = await db.query('''
        SELECT authors.name AS name, COUNT(books.id) AS total
        FROM authors
        JOIN books ON books.author_id = authors.id
        GROUP BY authors.id
        ORDER BY authors.id
      ''');
      expect(counts, <Map<String, Object?>>[
        <String, Object?>{'name': 'Ada', 'total': 2},
        <String, Object?>{'name': 'Grace', 'total': 1},
      ]);

      // UPDATE reports the number of affected rows
      expect(
        await db.execute(
          'UPDATE books SET title = ? WHERE author_id = ?',
          <Object?>['Redacted', 1],
        ),
        2,
      );
    });

    test('round-trips SQLite types including NULL and blobs', () async {
      await db.execute('''
        CREATE TABLE values_t (
          t TEXT, i INTEGER, r REAL, b BLOB, n TEXT
        );
      ''');
      await db.execute(
        'INSERT INTO values_t (t, i, r, b, n) VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          'text',
          7,
          1.5,
          <int>[1, 2, 3],
          null
        ],
      );

      final row = (await db.query('SELECT * FROM values_t')).single;
      expect(row['t'], 'text');
      expect(row['i'], 7);
      expect(row['r'], 1.5);
      expect(row['b'], <int>[1, 2, 3]);
      expect(row['n'], isNull);
    });

    test('reports the row id assigned by the last insert', () async {
      await db.execute(
        'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT);',
      );
      await db.execute('INSERT INTO t (v) VALUES (?)', <Object?>['a']);
      expect(db.lastInsertRowId, 1);
      await db.execute('INSERT INTO t (v) VALUES (?)', <Object?>['b']);
      expect(db.lastInsertRowId, 2);
    });

    test('surfaces SQL errors instead of silently returning nothing', () {
      expect(
        () => db.query('SELECT * FROM does_not_exist'),
        throwsA(isA<Object>()),
      );
    });

    test('rejects use after close', () async {
      final closing = SqliteDVDatabaseAdapter.memory();
      await closing.execute('CREATE TABLE t (v TEXT);');
      closing.close();

      expect(closing.close, returnsNormally, reason: 'close is idempotent');
      await expectLater(
        closing.query('SELECT * FROM t'),
        throwsA(isA<StateError>()),
      );
    });

    test('satisfies the DVDatabaseAdapter contract', () {
      expect(db, isA<DVDatabaseAdapter>());
    });
  });

  group('SqliteDVDatabaseAdapter.file', () {
    test('persists across connections and enables WAL', () async {
      final dir = Directory.systemTemp.createTempSync('dartvel_sqlite_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';

      final first = SqliteDVDatabaseAdapter.file(path);
      expect(first.isWalEnabled, isTrue,
          reason: 'WAL should be applied on a normal filesystem');
      await first.execute('CREATE TABLE t (v TEXT NOT NULL);');
      await first.execute('INSERT INTO t (v) VALUES (?)', <Object?>['kept']);
      first.close();

      expect(File(path).existsSync(), isTrue);

      final second = SqliteDVDatabaseAdapter.file(path);
      addTearDown(second.close);
      expect(
        (await second.query('SELECT v FROM t')).single['v'],
        'kept',
      );
    });

    test('enforces foreign keys by default', () async {
      final dir = Directory.systemTemp.createTempSync('dartvel_sqlite_fk_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SqliteDVDatabaseAdapter.file('${dir.path}/fk.db');
      addTearDown(db.close);

      await db.execute('CREATE TABLE parent (id INTEGER PRIMARY KEY);');
      await db.execute(
        'CREATE TABLE child (id INTEGER PRIMARY KEY, '
        'parent_id INTEGER REFERENCES parent(id));',
      );

      await expectLater(
        db.execute('INSERT INTO child (id, parent_id) VALUES (1, 99)'),
        throwsA(isA<Object>()),
        reason: 'a dangling foreign key must be rejected',
      );
    });
  });

  group('MemoryDVDatabaseAdapter', () {
    test('still serves the narrow shapes it always supported', () async {
      final db = MemoryDVDatabaseAdapter();
      expect(await db.query('select 1'), const [
        {'1': 1}
      ]);
      await db.execute(
        'insert into users (name) values (?)',
        <Object?>['Ada'],
      );
      expect((await db.query('select * from users')).single['name'], 'Ada');
    });

    test('rejects statements it cannot interpret', () async {
      final db = MemoryDVDatabaseAdapter();
      await expectLater(
        db.query('select * from users where name = ?'),
        throwsArgumentError,
      );
    });
  });
}
