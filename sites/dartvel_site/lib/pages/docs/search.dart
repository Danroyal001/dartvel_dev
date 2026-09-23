import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel search: full text, hosted engines and semantic search',
  description: 'Search your models with typed results, from an in-memory index '
      'in tests to Meilisearch or OpenSearch in production, and add '
      'semantic search by meaning.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsSearchPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docssearch,
      lead: <String>[
        'Search your models with typed results, from an in-memory index in '
            'tests to Meilisearch or OpenSearch in production.',
        'Add semantic search when people search by meaning and the words do '
            'not match.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'providers',
          title: 'Choose a search provider',
          children: <Widget>[
            DocsText('@DVModel(searchable: true) generates ArticleSearch. It '
                'has no provider until you set one, and a query before that '
                'throws a StateError.'),
            DocsTable(columns: <String>[
              'Provider',
              'Searches with',
            ], rows: <List<String>>[
              <String>['DVInMemorySearchProvider', 'A list in memory, for '
                  'tests and small apps'],
              <String>['DVSqliteSearchProvider', 'SQLite FTS5'],
              <String>['DVPostgresSearchProvider', 'Postgres full text'],
              <String>['MeilisearchProvider', 'Meilisearch'],
              <String>['OpenSearchProvider', 'OpenSearch or Elasticsearch'],
              <String>['AlgoliaSearchProvider', 'Algolia'],
            ]),
            DocsCode('search-hosted'),
            Bullets(<String>[
              'Meilisearch and OpenSearch run against real servers in CI.',
              'Algolia has no local server, so its requests are checked '
                  'against recorded ones.',
            ]),
          ],
        ),
        DocsSection(
          id: 'results',
          title: 'Read results, highlights and facets',
          children: <Widget>[
            DocsCode('search-results'),
            Bullets(<String>[
              'items are your model type, in rank order.',
              'highlights has one entry per item, or none when the provider '
                  'does not highlight.',
              'facetCounts counts what each facet value would leave for this '
                  'query.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tuning',
          title: 'Tune synonyms, typos and highlights',
          children: <Widget>[
            DocsYaml('yaml-search'),
            DocsText('Generation writes these into ArticleSearch.tuning. Pass '
                'it to the provider so the settings live in one place. '
                'Synonyms work in both directions.'),
          ],
        ),
        DocsSection(
          id: 'fields',
          title: 'Pick the fields that are indexed',
          children: <Widget>[
            Bullets(<String>[
              'Mark fields with @DVModel.searchableField(). With none marked, '
                  'every field is searchable.',
              'A @DVModel.sensitiveField() is never indexed, even when it is '
                  'marked searchable.',
              'A tenant-scoped model searched through Postgres only returns '
                  'the current tenant\'s rows.',
            ]),
          ],
        ),
        DocsSection(
          id: 'semantic',
          title: 'Search by meaning with embeddings',
          children: <Widget>[
            DocsText('DVSemanticIndex finds records by meaning: "how do refunds '
                'work" finds an article about returning an order. Today you '
                'wire it to a model by hand.'),
            DocsCode('search-semantic-index'),
            DocsCode('search-semantic-query'),
            Bullets(<String>[
              'Saving queues an embedding job. Nothing is embedded during the '
                  'save.',
              'mode is keyword (the default), semantic or hybrid. keyword and '
                  'hybrid also need a keyword: provider.',
              'Long fields are split into chunks, and a record appears once '
                  'with the chunk that matched.',
            ]),
            DocsNote('There is no default embedder',
                'You name the embedder and its dimensions. Vectors from two '
                'models cannot be compared, so changing the embedder builds a '
                'new index beside the old one.'),
            DocsStatus('Semantic Search and Embeddings', missing: <String>[
              'No @DVModel.searchableField(semantic: true) or generated '
                  'semantic query.',
              'DVInMemoryVectorAdapter is the only vector store. There is no '
                  'pgvector or hosted vector adapter.',
              'The dartvel.search.semantic block in pubspec.yaml is not read.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Search'),
          ],
        ),
      ],
    );
