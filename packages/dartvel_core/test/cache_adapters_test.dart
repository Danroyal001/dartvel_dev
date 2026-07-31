import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  // Both adapters must satisfy the same contract, so the shared expectations
  // run against each rather than being written twice.
  void sharedContract(String name, DVCacheAdapter Function() create) {
    group('$name (DVCacheAdapter contract)', () {
      late DVCacheAdapter cache;

      setUp(() => cache = create());

      test('reads back what it wrote', () async {
        await cache.write('greeting', 'hello', null);
        expect(await cache.read('greeting'), 'hello');
      });

      test('returns null for a key that was never written', () async {
        expect(await cache.read('absent'), isNull);
      });

      test('overwrites an existing key', () async {
        await cache.write('k', 'first', null);
        await cache.write('k', 'second', null);
        expect(await cache.read('k'), 'second');
      });

      test('honours a TTL', () async {
        await cache.write('short', 'value', const Duration(milliseconds: 40));
        expect(await cache.read('short'), 'value');

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(await cache.read('short'), isNull,
            reason: 'an expired key reads like a missing key');
      });

      test('keeps entries with no TTL', () async {
        await cache.write('forever', 'value', null);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(await cache.read('forever'), 'value');
      });

      test('removes a single key', () async {
        await cache.write('a', 1, null);
        await cache.write('b', 2, null);
        await cache.remove('a');

        expect(await cache.read('a'), isNull);
        expect(await cache.read('b'), 2);
      });

      test('clears everything', () async {
        await cache.write('a', 1, null);
        await cache.write('b', 2, null);
        await cache.clear();

        expect(await cache.read('a'), isNull);
        expect(await cache.read('b'), isNull);
      });

      test('purgeExpired reclaims only expired entries', () async {
        await cache.write('keep', 'v', null);
        await cache.write('live', 'v', const Duration(seconds: 30));
        await cache.write('dead', 'v', const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 45));

        expect(await cache.purgeExpired(), 1);
        expect(await cache.read('keep'), 'v');
        expect(await cache.read('live'), 'v');
        expect(await cache.read('dead'), isNull);
      });

      test('round-trips the JSON value shapes', () async {
        await cache.write('int', 7, null);
        await cache.write('double', 1.5, null);
        await cache.write('bool', true, null);
        await cache.write('null', null, null);
        await cache.write('list', <Object?>[1, 'two'], null);
        await cache.write('map', <String, Object?>{'a': 1}, null);

        expect(await cache.read('int'), 7);
        expect(await cache.read('double'), 1.5);
        expect(await cache.read('bool'), isTrue);
        expect(await cache.read('null'), isNull);
        expect(await cache.read('list'), <Object?>[1, 'two']);
        expect(await cache.read('map'), <String, Object?>{'a': 1});
      });
    });
  }

  sharedContract('DVMemoryCacheAdapter', DVMemoryCacheAdapter.new);
  sharedContract(
    'DVDatabaseCacheAdapter',
    () => DVDatabaseCacheAdapter(SqliteDVDatabaseAdapter.memory()),
  );

  group('DVDatabaseCacheAdapter', () {
    test('survives a restart when backed by a database file', () async {
      final dir = Directory.systemTemp.createTempSync('dartvel_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/cache.db';

      final firstDb = SqliteDVDatabaseAdapter.file(path);
      final first = DVDatabaseCacheAdapter(firstDb);
      await first.write('session:42', <String, Object?>{'user': 'ada'}, null);
      firstDb.close();

      // A brand new process would open the same file and see the entry.
      final secondDb = SqliteDVDatabaseAdapter.file(path);
      addTearDown(secondDb.close);
      final second = DVDatabaseCacheAdapter(secondDb);

      expect(
        await second.read('session:42'),
        <String, Object?>{'user': 'ada'},
        reason: 'the memory adapter would have lost this',
      );
    });

    test('shares one database with the application tables', () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);
      await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY);');

      final cache = DVDatabaseCacheAdapter(db);
      await cache.write('k', 'v', null);

      final tables = await db.query(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      expect(
        tables.map((row) => row['name']),
        containsAll(<String>['dartvel_cache', 'users']),
      );
    });

    test('honours a custom table name and rejects an unsafe one', () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);

      final cache = DVDatabaseCacheAdapter(db, tableName: 'page_cache');
      await cache.write('k', 'v', null);
      expect((await db.query('SELECT key FROM page_cache')).single['key'], 'k');

      for (final unsafe in <String>[
        'cache; DROP TABLE users',
        '',
        '1_bad',
        'has space',
      ]) {
        expect(
          () => DVDatabaseCacheAdapter(db, tableName: unsafe),
          throwsArgumentError,
          reason: '"$unsafe" is not a plain identifier',
        );
      }
    });

    test('rejects a value it cannot persist instead of dropping it', () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);
      final cache = DVDatabaseCacheAdapter(db);

      await expectLater(
        cache.write('bad', Object(), null),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('not JSON-encodable'),
          ),
        ),
      );
      expect(await cache.read('bad'), isNull);
    });

    test('initialize is idempotent and safe to call eagerly', () async {
      final db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);
      final cache = DVDatabaseCacheAdapter(db);

      await cache.initialize();
      await cache.initialize();
      await cache.write('k', 'v', null);
      expect(await cache.read('k'), 'v');
    });
  });
}
