import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel cache: get, set, has and delete',
  description: 'DV.Cache is four calls: get, set, has and delete. get '
      'computes a missing value, set takes tags, delete drops a key, a tag or '
      'everything, and the store is one line in pubspec.yaml.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsCachePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docscache,
      lead: <String>[
        'DV.Cache is four calls, get, set, has and delete, from a page or a '
            'backend function.',
        'Everything else is an option on those four: get computes a missing '
            'value, set takes tags, and delete drops a key, a tag or '
            'everything.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'basics',
          title: 'Get, set, has and delete',
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
          id: 'compute',
          title: 'Compute a value on a miss',
          children: <Widget>[
            DocsCode('cache-compute'),
            Bullets(<String>[
              'The compute runs only on a miss. Callers that ask for the same '
                  'key at once share one compute.',
              'A compute that throws stores nothing.',
              'ttl, tags and staleFor apply to what the compute stores. '
                  'Passing one to get without a compute is an error.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tags',
          title: 'Drop a group of keys by tag',
          children: <Widget>[
            DocsCode('cache-tags'),
            Bullets(<String>[
              'set and get take tags. delete(DVCacheTag(...)) removes every '
                  'key with that tag, and delete(DVCache.all) removes every key.',
              'delete takes one argument: a String key, a DVCacheTag or '
                  'DVCache.all. Anything else is an error, never a guess.',
              'Tags are kept in each server\'s memory. Deleting a tag drops '
                  'the keys this server has tagged.',
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
                'they wait for a new value. staleFor needs a ttl.'),
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
              'On a device, memory is the default store. The store in '
                  'pubspec.yaml applies only to the server.',
              'A device can switch store in code with withAdapter, below. '
                  'Sharing a cache with the server is planned.',
              'Keys are prefixed with the tenant unless it is the default one.',
            ]),
            DocsText('pubspec.yaml sets the store DV.Cache uses by default. '
                'DV.Cache.withAdapter switches to another store in code, with '
                'the same four calls:'),
            DocsCode('cache-switch'),
            Bullets(<String>[
              'Every call goes to the adapter you pass, never to the default '
                  'store.',
              'The adapters are DVMemoryCacheAdapter, DVDatabaseCacheAdapter, '
                  'DVRedisCacheAdapter, DVMemcachedCacheAdapter and '
                  'DVDistributedCacheAdapter.',
              'Tags and the shared compute are kept per adapter, so '
                  'deleting a tag on one store leaves the others alone.',
            ]),
          ],
        ),
        DocsSection(
          id: 'once',
          title: 'Run work once',
          children: <Widget>[
            DocsText('For work only one server should do, such as a monthly '
                'report, declare a schedule. Each occurrence is claimed once '
                'across cron processes, and a process does not start a '
                'schedule again while its last run is still going. Unique jobs '
                'are not built yet.'),
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
              'Model writes do not drop tags yet. Call '
                  'delete(DVCacheTag(...)) yourself.',
              'A device cannot share the server\'s cache yet. The plan is an '
                  'adapter that calls the server, with every call checked '
                  'against a policy and scoped to the tenant.',
              'Several Redis or Memcached nodes are not a store pubspec.yaml '
                  'can name yet. Pass a DVDistributedCacheAdapter to '
                  'withAdapter instead.',
            ]),
          ],
        ),
      ],
    );
