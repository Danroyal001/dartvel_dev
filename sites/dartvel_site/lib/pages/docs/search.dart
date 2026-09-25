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
            DocsText('@DVModel(searchable: true) gives the model '
                'Article.search. It has no provider until you set one with '
                'Article.useSearchProvider, and a search before that throws '
                'a StateError.'),
            DocsTable(columns: <String>[
              'Provider',
              'Searches with',
            ], rows: <List<String>>[
              <String>['DVInMemorySearchProvider', 'A list in memory, for '
                  'tests and small apps'],
              <String>['DVSqliteSearchProvider, DVPostgresSearchProvider',
                  'Your own database, with no search service to run. Use the '
                  'one that matches your database engine'],
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
            DocsText('Generation writes these into Article.searchTuning. '
                'Pass it to the provider so the settings live in one place. '
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
                  'the current tenant\'s records.',
            ]),
          ],
        ),
        DocsSection(
          id: 'semantic',
          title: 'Search by meaning with embeddings',
          children: <Widget>[
            DocsText('Semantic search finds records by meaning: "how do '
                'refunds work" finds an article about returning an order. '
                'Add semantic: true to @DVModel and the data model gets it.'),
            DocsCode('search-semantic-index'),
            DocsCode('search-semantic-query'),
            Bullets(<String>[
              'The embedder and the vector store are the only two things '
                  'Dartvel cannot know, so they are the only two you pass.',
              'What is embedded is the prose the data model already declares: '
                  'its searchable fields, its page title and its main '
                  'content. A sensitive field is never embedded.',
              'Saving a record queues an embedding job and destroying one '
                  'removes it. Nothing is embedded during the save.',
              'A worker does the embedding: `dartvel queue work --queue` '
                  'semantic. Queries never wait on it.',
              'mode is semantic (the default), keyword or hybrid. keyword and '
                  'hybrid also read the search provider.',
              'Long fields are split into chunks, and a record appears once '
                  'with the chunk that matched.',
            ]),
            DocsNote('There is no default embedder',
                'You name the embedder and its dimensions. Vectors from two '
                'models cannot be compared, so changing the embedder builds a '
                'new index beside the old one.'),
            DocsStatus('Semantic Search and Embeddings', missing: <String>[
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
