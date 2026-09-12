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

  // The in-memory adapter has to run the framework's own surfaces, or nothing
  // that uses them can be demoed or tested without a real database. Studio's
  // page store, DVDatabaseCacheAdapter and DVDatabaseQueueAdapter issue every
  // statement below; the adapter answered four shapes and threw on the rest.
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

    test('creates a table, then reads a column subset back by key', () async {
      final db = MemoryDVDatabaseAdapter();
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dartvel_pages (
          route TEXT,
          title TEXT,
          document TEXT
        )
      ''');
      expect(
        await db.query('SELECT route FROM dartvel_pages'),
        isEmpty,
        reason: 'a created table reads as empty, not as an unknown table',
      );

      await db.execute(
        'INSERT INTO dartvel_pages (route, title, document) VALUES (?, ?, ?)',
        <Object?>['/pricing', 'Pricing', '{"route":"/pricing"}'],
      );
      expect(
        await db.query(
          'SELECT document FROM dartvel_pages WHERE route = ?',
          <Object?>['/pricing'],
        ),
        const [
          {'document': '{"route":"/pricing"}'}
        ],
        reason: 'a column subset returns that column and no others',
      );
      expect(
        await db.query(
          'SELECT document FROM dartvel_pages WHERE route = ?',
          <Object?>['/missing'],
        ),
        isEmpty,
      );
    });

    test('a scoped delete removes the matching rows and leaves the rest',
        () async {
      final db = MemoryDVDatabaseAdapter();
      for (final route in <String>['/a', '/b']) {
        await db.execute(
          'INSERT INTO pages (route, title) VALUES (?, ?)',
          <Object?>[route, route],
        );
      }

      expect(
        await db.execute('DELETE FROM pages WHERE route = ?', <Object?>['/a']),
        1,
        reason: 'a delete answers with the number of rows it removed',
      );
      expect(
        (await db.query('SELECT route FROM pages')).single['route'],
        '/b',
      );

      await db.execute('DELETE FROM pages');
      expect(await db.query('SELECT * FROM pages'), isEmpty);
    });

    test('updates rows in place, binding SET before WHERE', () async {
      final db = MemoryDVDatabaseAdapter();
      await db.execute(
        'INSERT INTO jobs (id, state, attempts) VALUES (?, ?, ?)',
        <Object?>['j1', 'reserved', 0],
      );
      await db.execute(
        'INSERT INTO jobs (id, state, attempts) VALUES (?, ?, ?)',
        <Object?>['j2', 'pending', 0],
      );

      expect(
        await db.execute(
          'UPDATE jobs SET attempts = ?, state = ? WHERE id = ? AND state = ?',
          <Object?>[1, 'failed', 'j1', 'reserved'],
        ),
        1,
      );
      final rows = await db.query('SELECT id, state, attempts FROM jobs');
      expect(rows, hasLength(2));
      expect(rows.first, <String, Object?>{
        'id': 'j1',
        'state': 'failed',
        'attempts': 1,
      });
      expect(rows.last['state'], 'pending',
          reason: 'the WHERE clause scoped the update to one row');

      expect(
        await db.execute(
          'UPDATE jobs SET state = ? WHERE id = ? AND state = ?',
          <Object?>['reserved', 'j1', 'pending'],
        ),
        0,
        reason: 'a claim that loses the race updates nothing',
      );
    });

    test('orders, limits and counts the way the queue adapter asks', () async {
      final db = MemoryDVDatabaseAdapter();
      Future<void> job(String id, int priority, String createdAt) =>
          db.execute(
            'INSERT INTO jobs (id, queue, state, priority, created_at) '
            'VALUES (?, ?, ?, ?, ?)',
            <Object?>[id, 'default', 'pending', priority, createdAt],
          );
      await job('low', 1, '2026-01-01T00:00:00Z');
      await job('high-late', 9, '2026-01-03T00:00:00Z');
      await job('high-early', 9, '2026-01-02T00:00:00Z');

      final next = await db.query(
        'SELECT * FROM jobs WHERE queue = ? AND state = ? '
        'ORDER BY priority DESC, created_at ASC LIMIT 1',
        <Object?>['default', 'pending'],
      );
      expect(next.single['id'], 'high-early',
          reason: 'highest priority first, oldest first within a priority');

      expect(
        await db.query(
          'SELECT COUNT(*) AS total FROM jobs WHERE state = ?',
          <Object?>['pending'],
        ),
        const [
          {'total': 3}
        ],
      );
      expect(
        await db.query(
          'SELECT COUNT(*) AS total FROM jobs WHERE state = ?',
          <Object?>['done'],
        ),
        const [
          {'total': 0}
        ],
        reason: 'a count of nothing is a row holding zero, not no rows',
      );
    });

    test('compares against null and by inequality, as cache expiry does',
        () async {
      final db = MemoryDVDatabaseAdapter();
      await db.execute(
        'INSERT INTO cache (key, expires_at) VALUES (?, ?)',
        <Object?>['forever', null],
      );
      await db.execute(
        'INSERT INTO cache (key, expires_at) VALUES (?, ?)',
        <Object?>['stale', 100],
      );
      await db.execute(
        'INSERT INTO cache (key, expires_at) VALUES (?, ?)',
        <Object?>['fresh', 900],
      );

      expect(
        await db.execute(
          'DELETE FROM cache WHERE expires_at IS NOT NULL AND expires_at <= ?',
          <Object?>[500],
        ),
        1,
      );
      expect(
        (await db.query('SELECT key FROM cache'))
            .map((row) => row['key'])
            .toList(),
        <String>['forever', 'fresh'],
        reason: 'a null expiry never expires, and = NULL never matches',
      );
      expect(
        await db.query('SELECT key FROM cache WHERE expires_at IS NULL'),
        const [
          {'key': 'forever'}
        ],
      );
    });

    test('keeps a rowid, and orders and de-duplicates by column', () async {
      final db = MemoryDVDatabaseAdapter();
      await db.execute(
        'INSERT INTO revisions (route, number) VALUES (?, ?)',
        <Object?>['/pricing', 1],
      );
      await db.execute(
        'INSERT INTO revisions (route, number) VALUES (?, ?)',
        <Object?>['/about', 1],
      );
      await db.execute(
        'INSERT INTO revisions (route, number) VALUES (?, ?)',
        <Object?>['/pricing', 2],
      );

      expect(
        (await db.query('SELECT DISTINCT route FROM revisions ORDER BY route'))
            .map((row) => row['route'])
            .toList(),
        <String>['/about', '/pricing'],
      );
      expect(
        (await db.query('SELECT route FROM revisions ORDER BY number, rowid'))
            .map((row) => row['route'])
            .toList(),
        <String>['/pricing', '/about', '/pricing'],
        reason: 'insertion order breaks the tie, which is what rowid means',
      );
      expect(
        (await db.query('SELECT * FROM revisions')).first.containsKey('rowid'),
        isFalse,
        reason: 'rowid is orderable but not a column SELECT * returns',
      );
    });

    test('rejects what it cannot interpret, and says what it was', () async {
      final db = MemoryDVDatabaseAdapter();
      await db.execute(
        'INSERT INTO docs (id, body) VALUES (?, ?)',
        <Object?>[1, 'Ada'],
      );

      // Negative controls. Full-text search is SQLite's own, a join is a
      // second table, and a schema migration is a real database's job: each
      // has to fail, and the message has to name the statement so a developer
      // reads what was refused rather than guessing.
      for (final unsupported in <String>[
        'SELECT rowid FROM docs_fts WHERE docs_fts MATCH ?',
        'SELECT a.id FROM docs a JOIN docs b ON a.id = b.id',
        'SELECT body FROM docs WHERE id IN (SELECT id FROM docs)',
      ]) {
        await expectLater(
          db.query(unsupported, <Object?>['x']),
          throwsA(
            isA<ArgumentError>().having(
              (error) => '$error',
              'message',
              contains(unsupported),
            ),
          ),
          reason: unsupported,
        );
      }
      await expectLater(
        db.execute('ALTER TABLE docs ADD COLUMN title TEXT'),
        throwsArgumentError,
      );
      await expectLater(
        db.query('SELECT body FROM docs WHERE id = ?'),
        throwsArgumentError,
        reason: 'a placeholder with no parameter is a caller bug, not a null',
      );
    });
  });
}
