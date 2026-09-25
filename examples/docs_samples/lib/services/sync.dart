import 'package:flutter/widgets.dart';

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

  // Saving is what publishes it. There is no sync() to call: a model that
  // has to be told to sync is not realtime.
  await article.save();

  // Only because this watch was started outside a widget. One started in a
  // page goes when the page does.
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

Future<void> offline() async {
  // docs:start offline-store
  // Saved on this device at once, with a network or without one. It
  // reaches the server when the server can be reached.
  const Dispatch dispatch = Dispatch(id: 'd1', reference: 'R-1', quantity: 2);
  await dispatch.save();

  // Read back from the device, in a tunnel as on Wi-Fi.
  final Dispatch? again = await Dispatch.find('d1');

  // Where this record stands: pending, syncing, synced, conflicted or
  // rejected.
  dispatch.syncState.listen((DVSyncState state) {
    DV.log('${dispatch.reference} is ${state.name}');
  });

  // Deleting is the same: gone from the device now, from the server later.
  await dispatch.destroy();
  // docs:end
  DV.log('${again?.quantity}');
}

// docs:start offline-connectivity
// What the device can reach, as a signal: a banner is a widget that
// rebuilds, not a listener to remember to dispose.
@DVFunctionalWidget()
@pragma('vm:entry-point')
Widget _connectionBanner(BuildContext context) {
  final DVNetworkStatus status = DV.Platform.network.watch(context);
  if (status != DVNetworkStatus.offline) return const DVBox.list(<Widget>[]);
  return DVBox.list(<Widget>[
    const DVText('Offline. Your changes are saved here and will be sent.'),
    DVText('Since ${DV.Platform.network.since}'),
  ]);
}
// docs:end
