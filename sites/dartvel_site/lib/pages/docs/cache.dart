import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel cache: remember values and revalidate by tag', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsCachePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docscache,
      lead: <String>[
        'Compute an expensive value once and serve it from DV.Cache.',
        'Tag keys and drop a whole group when the data behind them changes.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'remember',
          title: 'Remember a value and revalidate it by tag',
          children: <Widget>[
            DocsCode('cache-remember'),
            Bullets(<String>[
              'remember(key, ttl, compute) takes three positional arguments.',
              'Callers that ask for the same key at once share one compute.',
              'revalidateTag removes every tagged key and returns their names.',
            ]),
          ],
        ),
        DocsSection(
          id: 'basics',
          title: 'Get, set and delete',
          children: <Widget>[
            DocsCode('cache-basics'),
            DocsText('The time to live is the optional third argument of set.'),
          ],
        ),
        DocsSection(
          id: 'stale',
          title: 'Serve stale data while it refreshes',
          children: <Widget>[
            DocsCode('cache-stale'),
            DocsText('For staleFor after the ttl, callers get the old value at '
                'once while a new one is computed.'),
          ],
        ),
        DocsSection(
          id: 'lock',
          title: 'Let one caller at a time do the work',
          children: <Widget>[
            DocsCode('cache-lock'),
          ],
        ),
        DocsSection(
          id: 'adapters',
          title: 'Choose where the cache lives',
          children: <Widget>[
            DocsCode('cache-redis'),
            DocsTable(columns: <String>[
              'Adapter',
              'Stores entries in',
            ], rows: <List<String>>[
              <String>['DVMemoryCacheAdapter', 'Process memory, the default'],
              <String>['DVDatabaseCacheAdapter', 'A database table, '
                  'dartvel_cache'],
              <String>['DVRedisCacheAdapter', 'Redis'],
              <String>['DVMemcachedCacheAdapter', 'Memcached'],
              <String>['DVDistributedCacheAdapter', 'Several nodes, by '
                  'rendezvous hashing'],
            ]),
            Bullets(<String>[
              'Adapters are set in code. There is no pubspec setting for the '
                  'cache.',
              'Keys are prefixed with the tenant unless it is the default one.',
              'Tags are kept in the process\'s memory.',
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
            DocsStatus('Cache'),
          ],
        ),
      ],
    );
