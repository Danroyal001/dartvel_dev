// Runs against a real PostgreSQL, using its own full-text engine.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Article {
  final String slug;
  final String title;
  final String body;
  final bool published;

  const Article(this.slug, this.title, this.body, {this.published = true});
}

Future<bool> _reachable() async {
  try {
    final socket = await Socket.connect('127.0.0.1', 5432,
        timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _reachable()) {
    test(
      'postgres search (skipped: no PostgreSQL at localhost:5432)',
      () {},
      skip: 'Start postgresql with a dartvel_test database to run these.',
    );
    return;
  }

  late DVPostgresDatabaseAdapter database;
  late DVPostgresSearchProvider<Article, Map<String, Object?>> search;

  setUp(() async {
    database = DVPostgresDatabaseAdapter(database: 'dartvel_test');
    await database.execute('DROP TABLE IF EXISTS dv_articles');
    await database.execute(
      'CREATE TABLE dv_articles (slug TEXT PRIMARY KEY, title TEXT, '
      'body TEXT, published BOOLEAN)',
    );
    search = DVPostgresSearchProvider<Article, Map<String, Object?>>(
      database: database,
      table: 'dv_articles',
      columns: <String>['title', 'body'],
      fromRow: (Map<String, Object?> row) => Article(
        row['slug']! as String,
        row['title']! as String,
        row['body']! as String,
        published: row['published'] == true,
      ),
      filter: (Map<String, Object?>? facets) => facets?['published'] == true
          ? (sql: 'published = ?', params: <Object?>[true])
          : (sql: '', params: <Object?>[]),
    );

    for (final article in <Article>[
      const Article('a', 'Dart language tour', 'Learning the Dart language'),
      const Article('b', 'Flutter widgets', 'Building interfaces with widgets'),
      const Article('c', 'Draft post', 'A draft about databases',
          published: false),
    ]) {
      await database.execute(
        'INSERT INTO dv_articles VALUES (?, ?, ?, ?)',
        <Object?>[
          article.slug,
          article.title,
          article.body,
          article.published,
        ],
      );
    }
  });

  tearDown(() async {
    await database.execute('DROP TABLE IF EXISTS dv_articles');
    await database.close();
  });

  test('finds matching rows and rebuilds models', () async {
    final results = await search.query('Dart');

    expect(results.total, 1);
    expect(results.items.single.slug, 'a');
    expect(results.items.single.title, 'Dart language tour');
  });

  test('stemming matches word forms, which is why this beats LIKE', () async {
    // "learning" in the body should be found by "learn".
    final results = await search.query('learn');

    expect(results.items.map((Article a) => a.slug), contains('a'));
  });

  test('searches every configured column', () async {
    // "widgets" appears in both title and body of one row, "interfaces" only
    // in the body.
    expect((await search.query('interfaces')).items.single.slug, 'b');
  });

  test('an empty query returns nothing rather than everything', () async {
    // Matching everything would page the whole table into memory.
    final results = await search.query('   ');

    expect(results.total, 0);
    expect(results.items, isEmpty);
  });

  test('a filter narrows the search and keeps its values out of the SQL',
      () async {
    final all = await search.query('draft');
    expect(all.total, 1);

    final publishedOnly = await search.query(
      'draft',
      facets: <String, Object?>{'published': true},
    );
    expect(publishedOnly.total, 0);
  });

  test('paging reports the full total, not the page size', () async {
    for (var i = 0; i < 5; i++) {
      await database.execute(
        'INSERT INTO dv_articles VALUES (?, ?, ?, ?)',
        <Object?>['p$i', 'Paging test $i', 'about paging', true],
      );
    }

    final first = await search.query('paging', perPage: 2);
    expect(first.items, hasLength(2));
    expect(first.total, 5);

    final second = await search.query('paging', page: 2, perPage: 2);
    expect(second.items, hasLength(2));
    expect(
      second.items.map((Article a) => a.slug),
      isNot(anyElement(isIn(first.items.map((Article a) => a.slug)))),
    );
  });

  test('a hostile query is data, not SQL', () async {
    final results = await search.query("x'; DROP TABLE dv_articles; --");

    expect(results.total, 0);
    // The table is demonstrably still there.
    expect((await search.query('Dart')).total, 1);
  });

  test('an unsafe table or column name is refused at construction', () {
    // Identifiers cannot be parameterised, so they are validated instead.
    expect(
      () => DVPostgresSearchProvider<Article, Object>(
        database: database,
        table: 'articles; DROP TABLE users',
        columns: <String>['title'],
        fromRow: (_) => const Article('x', 'y', 'z'),
      ),
      throwsArgumentError,
    );
    expect(
      () => DVPostgresSearchProvider<Article, Object>(
        database: database,
        table: 'dv_articles',
        columns: <String>[],
        fromRow: (_) => const Article('x', 'y', 'z'),
      ),
      throwsArgumentError,
    );
  });

  test('createIndex builds a usable GIN index', () async {
    await search.createIndex();

    // Idempotent, and searching still works over it.
    await search.createIndex();
    expect((await search.query('Flutter')).items.single.slug, 'b');

    final indexes = await database.query(
      "SELECT indexname FROM pg_indexes WHERE tablename = 'dv_articles'",
    );
    expect(
      indexes.map((Map<String, Object?> row) => row['indexname']),
      contains('dv_articles_dv_search_idx'),
    );
  });
}
