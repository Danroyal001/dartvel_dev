import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/cache_command.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('CacheCommand', () {
    late CommandRunner<void> runner;

    setUp(() {
      const DVTestHarness().resetCacheTags();
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(CacheCommand());
    });

    test('inspect reads keys for a cache tag', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'inspect', 'users']);

      expect(tags.keysForTag('users'), contains('users:list'));
    });

    test('revalidate removes keys for a cache tag', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'revalidate', 'users']);

      expect(tags.keysForTag('users'), isEmpty);
    });

    test('clear resets cache tag metadata', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'clear']);

      expect(tags.keysForTag('users'), isEmpty);
    });

    group('persistent cache', () {
      late Directory directory;
      late String path;

      setUp(() {
        directory = Directory.systemTemp.createTempSync('dartvel_cache_cli');
        path = '${directory.path}/cache.db';
      });

      tearDown(() {
        directory.deleteSync(recursive: true);
      });

      /// Writes entries the way an application would, then closes the database
      /// so the command under test opens the file itself.
      Future<void> seed() async {
        final database = SqliteDVDatabaseAdapter.file(path);
        final cache = DVDatabaseCacheAdapter(database);
        await cache.write('fresh', 'a', const Duration(hours: 1));
        await cache.write('stale', 'b', const Duration(milliseconds: 1));
        await cache.write('forever', 'c', null);
        database.close();
      }

      Future<List<Map<String, Object?>>> rows() async {
        final database = SqliteDVDatabaseAdapter.file(path);
        try {
          return await database.query('SELECT cache_key FROM dartvel_cache');
        } finally {
          database.close();
        }
      }

      test('clear --database empties the persistent cache', () async {
        await seed();

        await runner.run(<String>['cache', 'clear', '--database', path]);

        expect(await rows(), isEmpty);
      });

      test('purge removes only expired entries', () async {
        await seed();
        // The 1ms entry has to actually be past its expiry before purging.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await runner.run(<String>['cache', 'purge', '--database', path]);

        expect(
          (await rows()).map((Map<String, Object?> row) => row['cache_key']),
          unorderedEquals(<String>['fresh', 'forever']),
        );
      });

      test('clear reports a missing database rather than creating one',
          () async {
        final missing = '${directory.path}/absent.db';

        await expectLater(
          runner.run(<String>['cache', 'clear', '--database', missing]),
          throwsA(isA<UsageException>()),
        );
        expect(File(missing).existsSync(), isFalse);
      });

      test('purge requires a database path', () async {
        await expectLater(
          runner.run(<String>['cache', 'purge']),
          throwsA(isA<UsageException>()),
        );
      });

      test('clear --table rejects an unsafe identifier', () async {
        await seed();

        await expectLater(
          runner.run(<String>[
            'cache',
            'clear',
            '--database',
            path,
            '--table',
            'dartvel_cache; DROP TABLE dartvel_cache',
          ]),
          throwsA(isA<ArgumentError>()),
        );
        expect((await rows()).length, 3);
      });
    });
  });
}
