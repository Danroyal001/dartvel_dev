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
              'A watcher only gets changes for the current tenant. '
                  'Article.allChanges is every tenant\'s, for a process '
                  'that serves all of them.',
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
            DocsText('A data model that has to work with no network says so, '
                'and says how a write made offline is resolved when it '
                'reaches the server.'),
            DocsCode('offline-model'),
            DocsText('That is all you declare. The data model is then saved, '
                'deleted and read like any other, with a network or without '
                'one.'),
            DocsCode('offline-store'),
            DocsText('A save returns as soon as the record is on the device. '
                'The device keeps its own copy and a queue of every change, '
                'in the order they were made: SQLite on phones, desktops '
                'and TVs, IndexedDB in a browser. Reads come from that copy, '
                'so they answer in a tunnel as they do on Wi-Fi.'),
            DocsText('You never send the queue. It goes when the app starts, '
                'after each save while the server can be reached, and again '
                'as soon as the device can reach the server after losing '
                'it. A send that fails is tried again later, on its own.'),
            Bullets(<String>[
              'The queue goes in order, and stops at a dropped connection, so '
                  'a later change never reaches the server before an earlier '
                  'one.',
              'A change the server keeps differently comes back to the '
                  'device, and watchers of the data model see it.',
              'syncState on a record says where it stands: pending, syncing, '
                  'synced, conflicted or rejected.',
              'A change the server refuses for good is not sent again, and '
                  'its record reads rejected, so nothing is lost silently.',
              'A full queue refuses the next save. It never drops an old one.',
              'Signing out sends what it can, then removes the device\'s '
                  'copy and queue, so the next person to sign in on that '
                  'device sees none of it.',
            ]),
            DocsSubheading('Show what the device can reach'),
            DocsText('Application code does not branch on connectivity: a '
                'write is made the same way in a tunnel as on Wi-Fi. It does '
                'show it, though, and that reading is a signal.'),
            DocsCode('offline-connectivity'),
            Bullets(<String>[
              'status is online, metered, offline, or unknown where no '
                  'binding on this target has reported.',
              'canReachTheServer is what most call sites are asking. It is '
                  'true on a metered connection, and true when nothing has '
                  'reported: a write\'s own failure is what proves the '
                  'server is gone.',
              'since is when it last changed, so an offline banner can say '
                  'how long. A platform that re-reports the same status does '
                  'not move it.',
              'The browser binding is built. Other targets report unknown '
                  'until theirs is.',
            ]),
          ],
        ),
        DocsSection(
          id: 'offline-server',
          title: 'What the server does with a change made offline',
          children: <Widget>[
            DocsText('The generated backend takes each change a device sends '
                'and applies it itself. There is no server code to write for '
                'it: what decides is the data model\'s own declaration and '
                'its policy.'),
            Bullets(<String>[
              'Only a signed-in person\'s changes are taken, and only for '
                  'data models that declared offline:.',
              'Every change is put to the data model\'s policy first, as '
                  'create, update or delete, the same question an online '
                  'change asks. The policy is asked about the record, as the '
                  'class your policy is written for. A policy that refuses, '
                  'or cannot answer, refuses the change.',
              'A change sent twice, because an answer was lost on the way '
                  'back, is applied once.',
              'A refusal is remembered, so a device sending a refused change '
                  'again gets the same answer, even if the policy has changed '
                  'since.',
              'With lastWriteWins, the later change wins by the time it was '
                  'made on its device, corrected for that device\'s clock '
                  'drift. The order changes arrive in does not decide.',
              'DVConflict.ask is refused offline, because nobody is there to '
                  'answer. A data model that declares it stops the build, so '
                  'it cannot fail on somebody\'s phone instead.',
            ]),
            DocsStatus('Offline-First Models', missing: <String>[
              'encrypt: true is not applied, and sensitive fields are not '
                  'encrypted in the device\'s copy.',
              'The device copy\'s shape does not come from the migration '
                  'schema, and a changed data model does not rebuild it.',
              'Replay is not carried by the job queue, and the queue bounds '
                  'and clock tolerance are not read from pubspec.yaml.',
              'Only the browser reports connectivity. Elsewhere a failed send '
                  'is what says the server is gone, and the retry is what '
                  'finds it again.',
            ]),
          ],
        ),
      ],
    );
