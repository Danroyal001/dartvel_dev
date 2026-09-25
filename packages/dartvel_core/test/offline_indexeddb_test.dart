// The web's offline store, in a real browser: `dart test -p chrome`.
//
// A snapshot adapter tested against a map proves the adapter; only a browser
// proves that what IndexedDB is handed comes back after the database is
// opened again, which is the whole of what a closed tab needs.
@TestOn('browser')
library;

import 'package:dartvel_core/src/data/offline_database.dart';
import 'package:dartvel_core/src/data/offline_database_web.dart';
import 'package:test/test.dart';

void main() {
  test('a write made through one connection is read by the next', () async {
    final String name =
        'dartvel-offline-test-${DateTime.now().microsecondsSinceEpoch}';

    final DVSnapshotDatabaseAdapter first = await DVSnapshotDatabaseAdapter.open(
      await DVIndexedDbSnapshots.open(name),
    );
    await first.execute('CREATE TABLE orders (id TEXT, reference TEXT)');
    await first.execute(
      'INSERT INTO orders (id, reference) VALUES (?, ?)',
      <Object?>['o1', 'R-1'],
    );

    final DVSnapshotDatabaseAdapter second =
        await DVSnapshotDatabaseAdapter.open(
      await DVIndexedDbSnapshots.open(name),
    );
    expect(await second.query('SELECT reference FROM orders'),
        <Map<String, Object?>>[
          <String, Object?>{'reference': 'R-1'},
        ]);
  });

  test('a dropped table is removed from IndexedDB', () async {
    final String name =
        'dartvel-offline-drop-${DateTime.now().microsecondsSinceEpoch}';
    final DVIndexedDbSnapshots snapshots =
        await DVIndexedDbSnapshots.open(name);
    final DVSnapshotDatabaseAdapter db =
        await DVSnapshotDatabaseAdapter.open(snapshots);
    await db.execute('CREATE TABLE notes (id TEXT)');
    await db.execute('DROP TABLE notes');

    expect((await snapshots.readAll()).containsKey('notes'), isFalse);
  });

  test('the device database on the web is IndexedDB, not memory', () async {
    final Object database = await dvLocalOfflineDatabase(
        'web${DateTime.now().microsecondsSinceEpoch}');
    expect(database, isA<DVSnapshotDatabaseAdapter>());
  });
}
