// Resolving model pages at build time needs the database the models live in.
//
// The resolver ran the application's providers with no DV.Database configured
// at all, so every generatePublicPages model failed the same way on every
// build -- "UserPublicStaticPaths: Bad state: DV.Database has no configured
// adapter" -- whether or not the project had a database, and the web-server
// build printed it twice because two steps each resolved the paths again.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_paths_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory project({String? database, bool createFile = false}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_static_paths_db_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
${database == null ? '' : 'dartvel:\n  database:\n    provider: sqlite\n    path: $database\n'}''');
  if (createFile) {
    File(p.join(root.path, database ?? 'dartvel.db')).writeAsStringSync('');
  }
  return root;
}

void main() {
  group('the database a build resolves model pages against', () {
    test('DATABASE_URL, when it is set', () {
      final Directory root = project();
      final DVStaticPathsDatabase? db = dvStaticPathsDatabase(
        root.path,
        const <String, String>{'DATABASE_URL': 'postgres://db.example/shop'},
      );
      expect(db, isNotNull);
      expect(db!.environment, isEmpty,
          reason: 'the resolver inherits DATABASE_URL as it is');
      expect(db.description, 'DATABASE_URL');
    });

    test('the SQLite file dartvel.database names, when it exists', () {
      final Directory root = project(database: 'data/shop.db');
      File(p.join(root.path, 'data', 'shop.db'))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      final DVStaticPathsDatabase? db =
          dvStaticPathsDatabase(root.path, const <String, String>{});
      expect(db, isNotNull);
      expect(db!.environment['DARTVEL_STATIC_PATHS_SQLITE'],
          p.join(root.path, 'data', 'shop.db'));
    });

    test('nothing, when there is no URL and no file', () {
      // Never a new empty file: a model page resolved against a database
      // nobody wrote to is no pages, reported as success.
      final Directory root = project();
      expect(dvStaticPathsDatabase(root.path, const <String, String>{}), isNull);
      expect(File(p.join(root.path, 'dartvel.db')).existsSync(), isFalse);
    });
  });

  test('the resolver entry configures DV.Database before resolving', () {
    final String source = dvStaticPathsEntrySource('shop');
    final int configure = source.indexOf('DV.Database.configure(');
    expect(configure, greaterThan(-1));
    expect(source, contains("DARTVEL_STATIC_PATHS_SQLITE"));
    expect(source, contains('DVDatabaseConnection.fromEnvironment'));
    expect(configure, lessThan(source.indexOf('resolveDartvelStaticPaths(')));
  });

  group('what the build says about providers that did not resolve', () {
    const String stdout = '''
00:00 +0: resolve static paths
DARTVEL_STATIC_PATHS_ERROR UserPublicStaticPaths: Bad state: DV.Database has no configured adapter. Configure SQLite or another database adapter before use.
DARTVEL_STATIC_PATHS_ERROR PostPublicStaticPaths: Bad state: DV.Database has no configured adapter. Configure SQLite or another database adapter before use.
DARTVEL_STATIC_PATHS_ERROR productPaths: FormatException: bad slug
''';

    test('with no database, one line naming the models and what to do', () {
      final List<String> lines =
          dvStaticPathsReport(stdout, database: null, databaseHint: 'dartvel.db');
      final List<String> skipped = lines
          .where((String l) => l.contains('UserPublicStaticPaths'))
          .toList();
      expect(skipped, hasLength(1));
      expect(skipped.single, contains('PostPublicStaticPaths'));
      expect(skipped.single, contains('DATABASE_URL'));
      expect(skipped.single, contains('dartvel.db'));
      expect(lines.join('\n'), isNot(contains('Bad state')));
      // An error that is not about the database is still said as it is.
      expect(lines, contains('productPaths: FormatException: bad slug'));
    });

    test('with a database, every error is said as it is', () {
      final List<String> lines = dvStaticPathsReport(stdout,
          database: const DVStaticPathsDatabase('DATABASE_URL'),
          databaseHint: 'dartvel.db');
      expect(lines, hasLength(3));
    });
  });

  test('one build resolves the paths once, however many steps ask', () async {
    var runs = 0;
    final DVStaticPathsCache cache = DVStaticPathsCache((String root) async {
      runs++;
      return <String>['/users/ada'];
    });
    expect(await cache.resolve('/app'), <String>['/users/ada']);
    expect(await cache.resolve('/app'), <String>['/users/ada']);
    expect(runs, 1);
  });
}
