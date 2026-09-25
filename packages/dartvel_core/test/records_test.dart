// Records: one set of operations every database engine implements.
//
// The framework wrote SQL strings through DV.Database in about forty places,
// and a document database can run none of them. DVRecordAdapter is the
// storage-neutral contract -- ensure, find, count, insert, update, delete --
// with a DVFilter tree instead of a WHERE string. The SQL engine compiles it
// to parameterised SQL; a MongoDB engine will map the same tree to a filter
// document. See Storage-Neutral Records in NEW_SPEC.md.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A database that records the SQL it was handed and answers from a script.
class _Recording implements DVDatabaseAdapter {
  final List<String> sql = <String>[];
  final List<List<Object?>> params = <List<Object?>>[];
  List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  int affected = 0;

  @override
  Future<List<Map<String, Object?>>> query(String statement,
      [List<Object?>? values]) async {
    sql.add(statement);
    params.add(values ?? const <Object?>[]);
    return rows;
  }

  @override
  Future<int> execute(String statement, [List<Object?>? values]) async {
    sql.add(statement);
    params.add(values ?? const <Object?>[]);
    return affected;
  }
}

const DVRecordShape pages = DVRecordShape(
  collection: 'studio_pages',
  key: 'route',
  fields: <String, DVFieldType>{
    'route': DVFieldType.text,
    'title': DVFieldType.text,
    'version': DVFieldType.integer,
    'score': DVFieldType.real,
  },
);

void main() {
  group('a filter', () {
    test('matches a record as SQL would, null never comparing equal', () {
      final DVFilter filter = DVFilter.all(<DVFilter>[
        DVFilter.equals('route', '/menu'),
        const DVFilter.compare('version', DVCompare.greaterOrEqual, 2),
      ]);

      expect(filter.matches(<String, Object?>{'route': '/menu', 'version': 3}),
          isTrue);
      expect(filter.matches(<String, Object?>{'route': '/menu', 'version': 1}),
          isFalse);
      expect(DVFilter.equals('title', null).matches(<String, Object?>{}),
          isFalse);
      expect(const DVFilter.isNull('title').matches(<String, Object?>{}), isTrue);
      expect(
          DVFilter.any(<DVFilter>[
            DVFilter.equals('route', '/a'),
            DVFilter.equals('route', '/b'),
          ]).matches(<String, Object?>{'route': '/b'}),
          isTrue);
    });
  });

  group('the SQL engine', () {
    late _Recording database;
    late DVSqlRecordAdapter records;

    setUp(() {
      database = _Recording();
      records = DVSqlRecordAdapter(database);
    });

    test('creates the collection as a table with typed columns', () async {
      await records.ensure(pages);

      expect(
          database.sql.first,
          'CREATE TABLE IF NOT EXISTS studio_pages (route VARCHAR(255) '
          'PRIMARY KEY, '
          'title TEXT, version BIGINT, score DOUBLE PRECISION)');
    });

    test('ensures a collection once per database, not on every call',
        () async {
      await records.ensure(pages);
      final int after = database.sql.length;
      await records.ensure(pages);

      expect(database.sql.length, after);
    });

    test('a collection with no key field declares no primary key', () async {
      await records.ensure(const DVRecordShape(
        collection: 'audit',
        fields: <String, DVFieldType>{
          'route': DVFieldType.text,
          'at': DVFieldType.text,
        },
      ));

      expect(database.sql.first,
          'CREATE TABLE IF NOT EXISTS audit (route TEXT, at TEXT)');
    });

    test('compiles a find to parameterised SQL', () async {
      await records.find(
        'studio_pages',
        where: DVFilter.all(<DVFilter>[
          DVFilter.equals('route', '/menu'),
          const DVFilter.any(<DVFilter>[
            DVFilter.isNull('title'),
            DVFilter.compare('version', DVCompare.less, 3),
          ]),
        ]),
        orderBy: const <DVSort>[DVSort('title', descending: true)],
        limit: 5,
        offset: 10,
        fields: const <String>['route', 'title'],
      );

      expect(
          database.sql.single,
          'SELECT route, title FROM studio_pages WHERE route = ? AND '
          '(title IS NULL OR version < ?) ORDER BY title DESC LIMIT 5 '
          'OFFSET 10');
      expect(database.params.single, <Object?>['/menu', 3]);
    });

    test('updates only the matches, and answers how many', () async {
      database.affected = 1;

      final int changed = await records.update(
        'studio_pages',
        <String, Object?>{'title': 'Menu', 'version': 4},
        where: DVFilter.all(<DVFilter>[
          DVFilter.equals('route', '/menu'),
          DVFilter.equals('version', 3),
        ]),
      );

      expect(changed, 1);
      expect(database.sql.single,
          'UPDATE studio_pages SET title = ?, version = ? '
          'WHERE route = ? AND version = ?');
      expect(database.params.single, <Object?>['Menu', 4, '/menu', 3]);
    });

    test('inserts, counts and deletes', () async {
      database.rows = <Map<String, Object?>>[
        <String, Object?>{'n': 2},
      ];
      await records.insert(
          'studio_pages', <String, Object?>{'route': '/a', 'title': 'A'});
      final int n = await records.count('studio_pages',
          where: DVFilter.isNotNull('title'));
      await records.delete('studio_pages', where: DVFilter.equals('route', '/a'));

      expect(database.sql, <String>[
        'INSERT INTO studio_pages (route, title) VALUES (?, ?)',
        'SELECT COUNT(*) AS n FROM studio_pages WHERE title IS NOT NULL',
        'DELETE FROM studio_pages WHERE route = ?',
      ]);
      expect(n, 2);
    });

    // A tenant's tables live in its own schema under schema-per-tenant.
    test('a collection may be qualified by its schema', () async {
      await records.find('tenant_a.dv_studio_grants');

      expect(database.sql.single, 'SELECT * FROM tenant_a.dv_studio_grants');
      expect(() => records.find('a..b'), throwsA(isA<ArgumentError>()));
      expect(() => records.find('a.b.c'), throwsA(isA<ArgumentError>()));
    });

    test('refuses a name that is not an identifier', () async {
      expect(() => records.find('pages; DROP TABLE users'),
          throwsA(isA<ArgumentError>()));
      expect(
          () => records.find('pages',
              where: DVFilter.equals('route = route OR 1', 1)),
          throwsA(isA<ArgumentError>()));
    });

    test('refuses to update or delete with an empty filter', () async {
      expect(
          () => records.delete('studio_pages',
              where: const DVFilter.all(<DVFilter>[])),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('on the development database', () {
    late MemoryDVDatabaseAdapter memory;

    setUp(() {
      memory = MemoryDVDatabaseAdapter();
      const DVDatabase().configure(memory);
    });

    tearDown(() => const DVDatabase().unconfigure());

    test('DV.Database.records reads back what it wrote', () async {
      final DVRecordAdapter records = const DVDatabase().records;
      await records.ensure(pages);
      await records.insert('studio_pages',
          <String, Object?>{'route': '/menu', 'title': 'Menu', 'version': 1});

      // An optimistic write: the version it read is in the filter, so a
      // second writer holding the same version changes nothing.
      final DVFilter atVersion1 = DVFilter.all(<DVFilter>[
        DVFilter.equals('route', '/menu'),
        DVFilter.equals('version', 1),
      ]);
      expect(
          await records.update('studio_pages',
              <String, Object?>{'title': 'Our menu', 'version': 2},
              where: atVersion1),
          1);
      expect(
          await records.update('studio_pages',
              <String, Object?>{'title': 'Lost write', 'version': 2},
              where: atVersion1),
          0);

      final List<Map<String, Object?>> found = await records.find(
          'studio_pages',
          where: DVFilter.equals('route', '/menu'));
      expect(found.single['title'], 'Our menu');
      expect(await records.count('studio_pages'), 1);
    });
  });

  // A table from an earlier release lacks a field its shape has since
  // gained, and CREATE TABLE IF NOT EXISTS leaves it as it was: the first
  // write naming the new field would fail. ensure() adds it, as dartvel db
  // migrate does for a model.
  test('ensure adds a field an existing table lacks', () async {
    final SqliteDVDatabaseAdapter sqlite = SqliteDVDatabaseAdapter.memory();
    addTearDown(sqlite.close);
    await sqlite.execute('CREATE TABLE audit (route TEXT)');
    final DVSqlRecordAdapter records = DVSqlRecordAdapter(sqlite);

    await records.ensure(const DVRecordShape(
      collection: 'audit',
      fields: <String, DVFieldType>{
        'route': DVFieldType.text,
        'seq': DVFieldType.integer,
      },
    ));
    await records.insert('audit', <String, Object?>{'route': '/a', 'seq': 7});

    expect((await records.find('audit')).single['seq'], 7);
  });

  // The same collection ensured again in the same process with a field it
  // did not have: a destination that follows a model's schema grows this
  // way. Remembering the collection alone skipped the second ensure, and the
  // first write naming the new field failed.
  test('ensure adds a field a shape gained since this process ensured it',
      () async {
    final SqliteDVDatabaseAdapter sqlite = SqliteDVDatabaseAdapter.memory();
    addTearDown(sqlite.close);
    final DVSqlRecordAdapter records = DVSqlRecordAdapter(sqlite);
    await records.ensure(const DVRecordShape(
      collection: 'copies',
      fields: <String, DVFieldType>{'route': DVFieldType.text},
    ));

    await records.ensure(const DVRecordShape(
      collection: 'copies',
      fields: <String, DVFieldType>{
        'route': DVFieldType.text,
        'seq': DVFieldType.integer,
      },
    ));
    await records.insert('copies', <String, Object?>{'route': '/a', 'seq': 7});

    expect((await records.find('copies')).single['seq'], 7);
  });

  test('over() answers an engine as itself and SQL through the SQL engine',
      () {
    final _Engine engine = _Engine();
    expect(DVRecordAdapter.over(engine), same(engine));
    expect(DVRecordAdapter.over(_Recording()), isA<DVSqlRecordAdapter>());
  });

  test('an adapter that is itself a record engine is used as one', () {
    final _Engine engine = _Engine();
    const DVDatabase().configure(engine);
    addTearDown(() => const DVDatabase().unconfigure());

    expect(const DVDatabase().records, same(engine));
  });
}

/// A database engine that speaks records natively, as a MongoDB one will.
class _Engine extends _Recording implements DVRecordAdapter {
  @override
  Future<void> ensure(DVRecordShape shape) async {}

  @override
  Future<List<Map<String, Object?>>> find(String collection,
          {DVFilter? where,
          List<DVSort> orderBy = const <DVSort>[],
          int? limit,
          int? offset,
          List<String>? fields}) async =>
      const <Map<String, Object?>>[];

  @override
  Future<int> count(String collection, {DVFilter? where}) async => 0;

  @override
  Future<void> insert(String collection, Map<String, Object?> record) async {}

  @override
  Future<int> update(String collection, Map<String, Object?> changes,
          {required DVFilter where}) async =>
      0;

  @override
  Future<int> delete(String collection, {required DVFilter where}) async => 0;
}
