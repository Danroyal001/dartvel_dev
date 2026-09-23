import '../dartvel_client/dartvel_client.dart';

Future<void> modelChanges(Article article) async {
  // docs:start sync-changes
  // Every save, destroy and restore of an Article in this process.
  Article.changes.listen((DVModelChange<Article> change) {
    DV.log('${change.kind.name} ${change.model.slug} for ${change.tenant}');
  });

  // The whole list now, and again after each change.
  final DVModelWatch watch = await Article.watch((List<Article> articles) {
    DV.log('${articles.length} articles');
  });

  await article.sync(); // saves, then publishes a synced change
  await watch.cancel();
  // docs:end
}

void syncPolicy() {
  // docs:start sync-policy
  // A change is delivered only to watchers allowed to see the model.
  Article.syncPolicy((Article article) => article.published);
  // docs:end
}

Future<void> presence() async {
  // docs:start sync-presence
  DVPresence.startSweeping(); // drops members whose heartbeats stopped

  DVPresence.channel('article:hello-world').listen((DVPresenceEvent event) {
    DV.log('${event.member.id} ${event.kind.name}');
  });

  await DVPresence.join(
    'article:hello-world',
    DVPresenceMember(id: 'user-1', state: <String, Object?>{'name': 'Ada'}),
  );
  await DVPresence.heartbeat('article:hello-world', 'user-1');

  final List<DVPresenceMember> here = DVPresence.members('article:hello-world');
  await DVPresence.leave('article:hello-world', 'user-1');
  // docs:end
  DV.log('${here.length}');
}

Future<void> offline(DVOfflineRemote server) async {
  // docs:start offline-store
  final DVOfflineStore orders = DVOfflineStore(
    table: DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: <String>['id', 'reference', 'quantity'],
      database: SqliteDVDatabaseAdapter.file('device.db'),
    ),
    policy: const DVOffline(strategy: DVConflict.lastWriteWins),
  );
  await orders.ensureSchema();

  // Written locally at once, and queued for the server.
  await orders.write(<String, Object?>{'id': 'o1', 'reference': 'R-1', 'quantity': 2});
  final List<DVMutation> waiting = await orders.pending();

  // On reconnect: send the queue in order.
  final DVReplayResult result = await orders.replay(server);
  DV.log('${result.applied} applied, ${result.rejected} refused');
  // docs:end
  DV.log('${waiting.length} ${orders.syncStateOf('o1')}');
}

// docs:start offline-server
DVOfflineRemote ordersRemote(DVDatabaseAdapter database) => DVRecordTableRemote(
      DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: <String>['id', 'reference', 'quantity'],
        database: database,
      ),
      strategy: DVConflict.lastWriteWins,
      validate: (Map<String, Object?> values) => values['quantity'] is int,
    );
// docs:end
