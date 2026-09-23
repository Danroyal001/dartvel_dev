import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel workers and memory: heavy work off the UI thread',
  description: 'Run heavy work on another core with progress, a timeout and '
      'cancellation while the UI keeps drawing, and reserve a memory '
      'budget you fill with typed slices.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsWorkersPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsworkers,
      lead: <String>[
        'Run heavy work on another core with progress, a timeout and '
            'cancellation, and keep the UI drawing.',
        'Reserve a memory budget once and fill it with typed slices, without '
            'churning the garbage collector.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'run',
          title: 'Run a task on a worker',
          children: <Widget>[
            DocsCode('workers-run'),
            Bullets(<String>[
              'On native targets the pool uses isolates, one fewer than the '
                  'cores and at most 8. On the web it uses web workers.',
              'The timeout counts from the call, so time spent waiting for a '
                  'free worker counts too.',
              'The result says completed, failed, cancelled or timedOut. value '
                  'rethrows anything but completed.',
            ]),
            DocsNote('Web workers run tasks by name',
                'A web worker cannot be handed a function. Register each task '
                'with DVWorkerTasks.register in the page and in a worker script '
                'that calls dvWebWorkerMain. You write that script yourself '
                'today.'),
          ],
        ),
        DocsSection(
          id: 'lend',
          title: 'Lend memory to a worker',
          children: <Widget>[
            Bullets(<String>[
              'Pass a DVWorkerBuffer or an arena in lend: and its addresses in '
                  'the input. The worker writes in place, with no copy.',
              'While a buffer is lent, reading or freeing it on the caller\'s '
                  'side throws.',
              'Lending needs native memory. On the web, bytes are copied and '
                  'DV-WORKER-004 says so once.',
            ]),
            DocsStatus('Compute: Workers and Native Offload', missing: <String>[
              'A task that captures something it cannot send fails when it '
                  'runs. There is no build-time check yet.',
              'Pool size ignores dartvel.deviceProfiles, and no worker script '
                  'is generated for web builds.',
              'Jobs do not report progress or accept cancellation this way yet.',
            ]),
          ],
        ),
        DocsSection(
          id: 'arena',
          title: 'Reserve memory up front',
          children: <Widget>[
            DocsCode('memory-arena'),
            Bullets(<String>[
              'Slices come in int, double and fixed-width types, spread across '
                  'segments of the arena.',
              'reset and dispose invalidate every slice, so stale memory is '
                  'never read by mistake.',
              'Native targets allocate outside the Dart heap. The web uses '
                  'typed data.',
            ]),
          ],
        ),
        DocsSection(
          id: 'budget',
          title: 'Set budgets per target and device',
          children: <Widget>[
            DocsYaml('yaml-memory'),
            Bullets(<String>[
              'A device profile beats its target, which beats the top level. A '
                  'target or profile budget is a ceiling.',
              'dartvel doctor fails when a profile\'s budget is larger than its '
                  'RAM.',
              'Pick the profile when you build: dartvel build tizen '
                  '--device-profile lobby-screen',
            ]),
            DocsStatus('Platform Memory', missing: <String>[
              'Verified on Linux only among native targets, and never run in a '
                  'real browser.',
              'dispose frees native memory when the last view is collected, '
                  'which can be later than the call.',
              'Tizen, webOS and Sony eLinux builds get desktop defaults.',
            ]),
          ],
        ),
      ],
    );
