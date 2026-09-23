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

Future<void> offline(DVDatabaseAdapter serverDatabase) async {
  // docs:start offline-store
  // On the device: the local copy of a data model that declared offline:.
  final DVOfflineStore dispatches =
      Dispatch.offlineStore(SqliteDVDatabaseAdapter.file('device.db'));
  await dispatches.ensureSchema();

  // Written locally at once, and queued for the server.
  await dispatches.write(<String, Object?>{
    'id': 'd1',
    'reference': 'R-1',
    'quantity': 2,
  });
  final List<DVMutation> waiting = await dispatches.pending();

  // On reconnect: send the queue in order, to the server side of the same
  // data model. Neither side states the table, the key or the columns, so
  // neither can drift from the other or from the model.
  final DVReplayResult result =
      await dispatches.replay(Dispatch.offlineRemote(serverDatabase));
  DV.log('${result.applied} applied, ${result.rejected} refused');
  // docs:end
  DV.log('${waiting.length} ${dispatches.syncStateOf('d1')}');
}

// docs:start offline-server
// The server side, with a check on what it accepts. A write that fails it
// is refused rather than applied, and the device is told.
DVOfflineRemote dispatchesRemote(DVDatabaseAdapter database) =>
    Dispatch.offlineRemote(
      database,
      validate: (Map<String, Object?> values) => values['quantity'] is int,
    );
// docs:end
