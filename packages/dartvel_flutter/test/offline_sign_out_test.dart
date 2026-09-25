// Signing out empties the device's copy of every offline data model.
//
// A device holds only what its session may read. A signed-out phone that
// still has the last person's orders in its offline store is a data leak
// with a plausible explanation, and nothing about it looks broken: the next
// person signs in and the rows are simply there.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    await DVOfflineSync.resetForTesting();
    DV.Test.resetAuth();
  });

  test('signing out leaves nothing of the session on the device', () async {
    final MemoryDVDatabaseAdapter device = MemoryDVDatabaseAdapter();
    DVOfflineSync.register(
      'Order',
      (DVDatabaseAdapter database) => DVOfflineStore(
        table: DVRecordTable(
          table: 'orders',
          key: 'id',
          columns: const <String>['id', 'reference'],
          database: database,
        ),
        policy: const DVOffline(strategy: DVConflict.lastWriteWins),
      ),
    );
    DVOfflineSync.install(database: () async => device);
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});

    DV.Auth.configure(DVLocalAuthProvider());
    await DV.Auth.signIn();
    await DV.Auth.signOut();

    expect(await store.all(), isEmpty);
    expect(await store.pending(), isEmpty,
        reason: 'the queued write is the session\'s too');
  });
}
