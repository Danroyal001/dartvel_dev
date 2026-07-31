import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Author {
  final String name;
  final String bio;
  final String role;

  const Author(this.name, this.bio, this.role);
}

class AuthorFacets {
  final List<String>? role;
  const AuthorFacets({this.role});
}

const authors = <Author>[
  Author('Ada Lovelace', 'Wrote the first published algorithm.', 'admin'),
  Author('Grace Hopper', 'Built the first compiler.', 'admin'),
  Author(
      'Alan Turing', 'Formalised computation and the Turing machine.', 'user'),
  Author('Unlovelaced Ada', 'A decoy whose name embeds the term.', 'user'),
];

void main() {
  late SqliteDVDatabaseAdapter db;

  DVSqliteSearchProvider<Author, AuthorFacets> provider({
    List<Author> records = authors,
    bool prefixMatchLastTerm = true,
  }) =>
      DVSqliteSearchProvider<Author, AuthorFacets>(
        database: db,
        records: records,
        document: (author) => '${author.name} ${author.bio}',
        facetMatcher: (author, facets) =>
            facets?.role == null || facets!.role!.contains(author.role),
        prefixMatchLastTerm: prefixMatchLastTerm,
      );

  setUp(() => db = SqliteDVDatabaseAdapter.memory());
  tearDown(() => db.close());

  group('DVSqliteSearchProvider', () {
    test('matches on whole words rather than substrings', () async {
      final results =
          await provider(prefixMatchLastTerm: false).query('lovelace');

      expect(
          results.items.map((author) => author.name), <String>['Ada Lovelace'],
          reason: '"Unlovelaced" contains the substring but is not the word');
      expect(results.total, 1);
    });

    test('the in-memory provider matches the substring, which is the point',
        () async {
      final memory = DVInMemorySearchProvider<Author, AuthorFacets>(
        records: authors,
        document: (author) => '${author.name} ${author.bio}',
      );
      final results = await memory.query('lovelace');

      expect(results.total, 2,
          reason: 'the substring scan also matches "Unlovelaced Ada"');
    });

    test('ranks better matches first', () async {
      final results = await provider().query('compiler');
      expect(results.items.first.name, 'Grace Hopper');
    });

    test('treats several terms as an AND', () async {
      final results = await provider().query('ada algorithm');
      expect(
          results.items.map((author) => author.name), <String>['Ada Lovelace']);
    });

    test('prefix-matches the final term', () async {
      final results = await provider().query('ada lovel');
      expect(
          results.items.map((author) => author.name), contains('Ada Lovelace'));
    });

    test('applies facets on top of the index', () async {
      final all = await provider().query('the');
      final admins = await provider().query(
        'the',
        facets: const AuthorFacets(role: <String>['admin']),
      );

      expect(admins.total, lessThan(all.total));
      expect(admins.items.every((author) => author.role == 'admin'), isTrue);
    });

    test('paginates ranked results', () async {
      final first = await provider().query('the', perPage: 1);
      final second = await provider().query('the', page: 2, perPage: 1);

      expect(first.items, hasLength(1));
      expect(first.page, 1);
      expect(first.perPage, 1);
      expect(second.items, hasLength(1));
      expect(second.items.single.name, isNot(first.items.single.name));
      expect(second.total, first.total);
    });

    test('returns an empty page past the end', () async {
      final results = await provider().query('lovelace', page: 99);
      expect(results.items, isEmpty);
      expect(results.total, greaterThan(0));
    });

    test('rejects non-positive paging arguments', () async {
      await expectLater(provider().query('x', page: 0), throwsArgumentError);
      await expectLater(provider().query('x', perPage: 0), throwsArgumentError);
    });

    test('an empty or punctuation-only query returns everything', () async {
      expect((await provider().query('')).total, authors.length);
      expect((await provider().query('   ')).total, authors.length);
      expect((await provider().query('!!! ???')).total, authors.length);
    });

    test('treats FTS5 operators typed by a user as literal text', () async {
      // None of these may raise a syntax error or execute as query syntax.
      for (final hostile in <String>[
        'lovelace AND turing',
        'lovelace OR turing',
        '"unbalanced quote',
        'NEAR(ada turing)',
        'col:value',
        'ada*',
        '^ada',
        '-turing',
      ]) {
        await expectLater(
          provider().query(hostile),
          completes,
          reason: '"$hostile" must not blow up the query',
        );
      }
    });

    test('finds a term that is also an FTS5 keyword', () async {
      final withKeyword = <Author>[
        const Author('Near Miss', 'A record about NEAR and OR.', 'user'),
      ];
      final results = await provider(records: withKeyword).query(
        'near',
      );

      expect(results.total, 1);
    });

    test('reindex picks up a changed record set', () async {
      final search = provider(records: const <Author>[]);
      expect((await search.query('lovelace')).total, 0);

      await search.reindex(authors);
      expect((await search.query('lovelace')).total, greaterThan(0));
      expect(search.records, hasLength(authors.length));
    });

    test('shares the database with application tables', () async {
      await db.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY);');
      await provider().query('ada');

      final tables = await db.query(
        "SELECT name FROM sqlite_master WHERE type IN ('table') "
        'ORDER BY name',
      );
      expect(
        tables.map((row) => row['name']),
        containsAll(<String>['authors', 'dartvel_search']),
      );
    });

    test('rejects an unsafe table name', () {
      expect(
        () => DVSqliteSearchProvider<Author, AuthorFacets>(
          database: db,
          records: authors,
          document: (author) => author.name,
          tableName: 'idx; DROP TABLE authors',
        ),
        throwsArgumentError,
      );
    });

    test('satisfies the DVSearchProvider contract', () {
      expect(provider(), isA<DVSearchProvider<Author, AuthorFacets>>());
    });
  });
}
