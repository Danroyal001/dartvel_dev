// Where a device keeps an offline data model's copy and its queue.
//
// The failure that matters is the quiet one: a store that looks like it works
// for the whole session and is empty after the tab is closed. Every write the
// person made offline in that session was in it, and nothing said so. On the
// web that was every store, because SQLite is not there and the only thing
// that was is the in-memory development database.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// The browser's IndexedDB as the adapter sees it: named snapshots that
/// outlive the adapter holding them.
class _Snapshots implements DVTableSnapshots {
  final Map<String, String> saved = <String, String>{};
  int writes = 0;

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.of(saved);

  @override
  Future<void> write(String table, String snapshot) async {
    writes++;
    saved[table] = snapshot;
  }

  @override
  Future<void> remove(String table) async {
    saved.remove(table);
  }
}

DVOfflineStore _store(DVDatabaseAdapter database) => DVOfflineStore(
      table: DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: const <String>['id', 'reference'],
        database: database,
      ),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );

void main() {
  group('a snapshot-backed store', () {
    test('keeps the copy and the queue across a restart', () async {
      final _Snapshots snapshots = _Snapshots();

      final DVOfflineStore before =
          _store(await DVSnapshotDatabaseAdapter.open(snapshots));
      await before.ensureSchema();
      await before.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});

      // The tab closes. A new adapter over the same snapshots is the next
      // launch.
      final DVOfflineStore after =
          _store(await DVSnapshotDatabaseAdapter.open(snapshots));
      await after.ensureSchema();

      expect((await after.read('o1'))?.values['reference'], 'R-1');
      final List<DVMutation> pending = await after.pending();
      expect(pending.map((DVMutation m) => m.key), <Object>['o1'],
          reason: 'a queued write that did not survive is a lost write');
    });

    test('is persistent, so it does not report itself memory-backed',
        () async {
      final DVOfflineStore store =
          _store(await DVSnapshotDatabaseAdapter.open(_Snapshots()));
      await store.ensureSchema();

      expect(store.persistent, isTrue);
      expect(store.reported, isNot(contains('DV-OFFLINE-001')));
    });

    test('a write is saved before it returns', () async {
      // A write that is saved "soon" is lost when the tab closes in between.
      final _Snapshots snapshots = _Snapshots();
      final DVSnapshotDatabaseAdapter database =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      await database.execute('CREATE TABLE notes (id TEXT, body TEXT)');
      final int before = snapshots.writes;

      await database
          .execute('INSERT INTO notes (id, body) VALUES (?, ?)', <Object?>[
        'n1',
        'hello',
      ]);

      expect(snapshots.writes, greaterThan(before));
      final DVSnapshotDatabaseAdapter reopened =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      expect(await reopened.query('SELECT body FROM notes'),
          <Map<String, Object?>>[
            <String, Object?>{'body': 'hello'},
          ]);
    });

    test('a read writes nothing', () async {
      final _Snapshots snapshots = _Snapshots();
      final DVSnapshotDatabaseAdapter database =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      await database.execute('CREATE TABLE notes (id TEXT)');
      final int before = snapshots.writes;

      await database.query('SELECT * FROM notes');

      expect(snapshots.writes, before);
    });

    test('a dropped table is gone after a restart too', () async {
      final _Snapshots snapshots = _Snapshots();
      final DVSnapshotDatabaseAdapter database =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      await database.execute('CREATE TABLE notes (id TEXT)');
      await database.execute('INSERT INTO notes (id) VALUES (?)', <Object?>['n']);
      await database.execute('DROP TABLE notes');

      expect(snapshots.saved.containsKey('notes'), isFalse);
    });

    test('row order and rowids survive, so a tie still breaks the same way',
        () async {
      final _Snapshots snapshots = _Snapshots();
      final DVSnapshotDatabaseAdapter database =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      await database.execute('CREATE TABLE log (seq INTEGER)');
      for (final int seq in <int>[3, 1, 2]) {
        await database
            .execute('INSERT INTO log (seq) VALUES (?)', <Object?>[seq]);
      }

      final DVSnapshotDatabaseAdapter reopened =
          await DVSnapshotDatabaseAdapter.open(snapshots);
      expect(
        await reopened.query('SELECT seq FROM log ORDER BY rowid DESC'),
        <Map<String, Object?>>[
          <String, Object?>{'seq': 2},
          <String, Object?>{'seq': 1},
          <String, Object?>{'seq': 3},
        ],
      );
      await reopened
          .execute('INSERT INTO log (seq) VALUES (?)', <Object?>[4]);
      final List<Map<String, Object?>> last = await reopened
          .query('SELECT seq FROM log ORDER BY rowid DESC LIMIT 1');
      expect(last.single['seq'], 4,
          reason: 'a new row after a restart must not reuse an old rowid');
    });
  });

  group('the device database an offline data model gets', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('dv_offline_db_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('is a file that outlives the process on a device', () async {
      final DVDatabaseAdapter first = await dvLocalOfflineDatabase(
        'shop',
        directory: directory.path,
        environment: const <String, String>{},
      );
      final DVOfflineStore store = _store(first);
      await store.ensureSchema();
      await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
      expect(store.persistent, isTrue);

      final DVOfflineStore again = _store(await dvLocalOfflineDatabase(
        'shop',
        directory: directory.path,
        environment: const <String, String>{},
      ));
      await again.ensureSchema();
      expect((await again.pending()).single.key, 'o1');
    });

    test('is in memory under flutter test, and says so', () async {
      // An application's widget tests would otherwise write into the
      // developer's own data directory, and share a queue between runs.
      final DVDatabaseAdapter database = await dvLocalOfflineDatabase(
        'shop',
        environment: const <String, String>{'FLUTTER_TEST': 'true'},
      );
      final DVOfflineStore store = _store(database);
      await store.ensureSchema();

      expect(store.persistent, isFalse);
      expect(store.reported, contains('DV-OFFLINE-001'));
    });

    test('refuses an app id that is not a plain name', () {
      expect(
        () => dvLocalOfflineDatabase('../elsewhere',
            directory: directory.path),
        throwsArgumentError,
      );
    });
  });
}
