import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel sync, presence and offline models',
  description: 'React to every change to a model, see who else is on a page, '
      'and keep taking writes when the network drops. It runs on your '
      'models, signals and queues.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsSyncPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docssync,
      lead: <String>[
        'React to every change to a model, see who else is on a page, and keep '
            'taking writes when the network drops.',
        'All of it runs on your models, signals and queues. There is no '
            'separate realtime API to learn.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'changes',
          title: 'Watch model changes',
          children: <Widget>[
            DocsCode('sync-changes'),
            Bullets(<String>[
              'Generated models publish created, updated, deleted, restored and '
                  'synced changes.',
              'A watcher only gets changes for the current tenant. Pass '
                  'allTenants: true to DVModelSync.changes for all of them.',
              'The generated backend also serves GraphQL subscriptions over '
                  'server-sent events.',
            ]),
            DocsCode('sync-policy'),
          ],
        ),
        DocsSection(
          id: 'presence',
          title: 'Show who is here',
          children: <Widget>[
            DocsCode('sync-presence'),
            Bullets(<String>[
              'A member is an identity, so one person on two devices counts '
                  'once.',
              'Members are scoped to the current tenant.',
              'A member who stops sending heartbeats for 45 seconds is gone. A '
                  'crashed app never says goodbye.',
            ]),
          ],
        ),
        DocsSection(
          id: 'across-processes',
          title: 'Reaching another server or another device',
          children: <Widget>[
            DocsText('A model you have opted into syncing is read and written '
                'the way any other model is. There is nothing to wire up and '
                'no object to implement: saving a record is what publishes the '
                'change, and watching one is what receives it.'),
            DocsText('Today that delivery happens inside one process. Carrying '
                'it between servers and devices is the framework\'s job and is '
                'not built yet, so a change on one instance does not reach '
                'another.'),
            DocsStatus('Model Sync and Presence', missing: <String>[
              'Delivery is in-process only. Nothing carries a change to '
                  'another server or to a phone yet.',
              'No reconnect policy, backpressure or collaborative editing.',
            ]),
          ],
        ),
        DocsSection(
          id: 'offline',
          title: 'Keep writing while offline',
          children: <Widget>[
            DocsText('DVOfflineStore keeps a local copy and a log of every write '
                'made on the device. When the connection comes back, replay '
                'sends the log to the server in order.'),
            DocsCode('offline-store'),
            Bullets(<String>[
              'Replay stops at a dropped connection and picks up there next '
                  'time. Two replays at once share one run.',
              'A write the server refuses for good moves to rejected(), so '
                  'nothing is lost silently.',
              'A full log refuses the next write. It never drops an old one.',
            ]),
          ],
        ),
        DocsSection(
          id: 'offline-server',
          title: 'Apply replayed writes on the server',
          children: <Widget>[
            DocsCode('offline-server'),
            Bullets(<String>[
              'A resent write is recognised by its mutation id and applied once.',
              'Last write wins by the time the write was made on the device, '
                  'corrected for clock drift. Arrival order does not decide.',
              'DVConflict.ask is refused offline, because nobody is there to '
                  'answer.',
            ]),
            DocsStatus('Offline-First Models', missing: <String>[
              'No @DVModel(offline:) yet, so you build the store by hand.',
              'No IndexedDB store on web.',
              'Signing out does not clear the store, and encrypt: true is not '
                  'applied.',
            ]),
          ],
        ),
      ],
    );
