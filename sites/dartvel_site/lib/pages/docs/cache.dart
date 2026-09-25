import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel cache: set, get, remember and revalidate by tag',
  description: 'Five calls read and write DV.Cache. remember computes a value '
      'once, tags drop a group of keys, and the store is one line in '
      'pubspec.yaml.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsCachePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docscache,
      lead: <String>[
        'Five calls read and write DV.Cache, from a page or a backend '
            'function.',
        'remember computes a value once, and tags drop a group of keys when '
            'the data behind them changes.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'basics',
          title: 'Set, get, has, delete and clear',
          children: <Widget>[
            DocsCode('cache-basics'),
            Bullets(<String>[
              'ttl is named. Without one an entry stays until it is deleted.',
              'get returns null for a missing key, an expired one, or a value '
                  'of another type.',
              'A backend function uses the same calls, with DV from '
                  'package:dartvel_core/dv.dart.',
            ]),
          ],
        ),
        DocsSection(
          id: 'remember',
          title: 'Remember a value and revalidate it by tag',
          children: <Widget>[
            DocsCode('cache-remember'),
            Bullets(<String>[
              'The compute runs only on a miss. Callers that ask for the same '
                  'key at once share one compute.',
              'A compute that throws stores nothing.',
              'revalidateTag deletes every key with that tag and returns their '
                  'names.',
              'DV.Cache.tag(key, tags) adds tags to an entry that already '
                  'exists. set takes tags as well.',
              'Tags are kept in each server\'s memory. revalidateTag drops the '
                  'keys this server has tagged.',
            ]),
          ],
        ),
        DocsSection(
          id: 'stale',
          title: 'Serve stale data while it refreshes',
          children: <Widget>[
            DocsCode('cache-stale'),
            DocsText('After ttl and for staleFor more, callers get the old '
                'value at once while one compute refreshes it. After both, '
                'they wait for a new value.'),
          ],
        ),
        DocsSection(
          id: 'lock',
          title: 'Let one caller at a time do the work',
          children: <Widget>[
            DocsCode('cache-lock'),
            Bullets(<String>[
              'lock returns what the body returns, or null when another caller '
                  'holds the lock.',
              'The lock is released when the body returns or throws.',
              'wait: keeps trying for that long. ttl: (30 seconds by default) '
                  'frees a lock whose holder crashed.',
              'Locks cover every server only on Redis or Memcached.',
            ]),
          ],
        ),
        DocsSection(
          id: 'store',
          title: 'Choose where the cache lives',
          children: <Widget>[
            DocsYaml('yaml-cache'),
            DocsTable(columns: <String>[
              'store',
              'Keeps entries in',
            ], rows: <List<String>>[
              <String>['memory', 'The server process. The default'],
              <String>['database', 'The database in DATABASE_URL, table '
                  'dartvel_cache. Change it with table:'],
              <String>['redis', 'Redis or Valkey, at url'],
              <String>['memcached', 'Memcached, at url'],
            ]),
            Bullets(<String>[
              r'url reads an environment variable, such as ${REDIS_URL}. '
                  'The build refuses a password written into pubspec.yaml.',
              'prefix starts every key, so two applications can share one '
                  'server. The default is dartvel:.',
              'The server refuses to start when it cannot reach the store.',
              'On a device, DV.Cache keeps entries in memory.',
              'Keys are prefixed with the tenant unless it is the default one.',
            ]),
          ],
        ),
        DocsSection(
          id: 'cli',
          title: 'Manage a database cache from the CLI',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel cache purge --database dartvel.db   # drop expired entries',
              'dartvel cache clear --database dartvel.db',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Cache', missing: <String>[
              'No model query cache, and no caching a backend function by '
                  'annotation.',
              'Model writes do not revalidate tags yet. Call revalidateTag '
                  'yourself.',
              'Several Redis or Memcached nodes are not a store you can name '
                  'yet.',
            ]),
          ],
        ),
      ],
    );
