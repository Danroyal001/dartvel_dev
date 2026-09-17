import '../dartvel_client/dartvel_client.dart';

void hostedSearch() {
  // docs:start search-hosted
  ArticleSearch.useProvider(MeilisearchProvider<Article, ArticleSearchFacets>(
    baseUrl: Uri.parse('https://search.example.com'),
    apiKey: DV.Secrets.get('MEILISEARCH_KEY'),
    indexName: 'articles',
    fromJson: ArticleParser.fromJson,
    tuning: ArticleSearch.tuning, // from dartvel.search in pubspec.yaml
  ));
  // docs:end
}

Future<void> highlights() async {
  // docs:start search-results
  final DVSearchResultPage<Article> page =
      await ArticleSearch.query('dart', page: 1, perPage: 20);

  for (int i = 0; i < page.items.length; i++) {
    final Article article = page.items[i];
    final String snippet = page.highlights.isEmpty ? '' : page.highlights[i];
    DV.log('${article.title}: $snippet');
  }
  DV.log('${page.total} matches, facets ${page.facetCounts}');
  // docs:end
}

// docs:start search-semantic-index
final DVSemanticIndex<Article> articleIndex = DVSemanticIndex<Article>(
  name: 'articles',
  embedder: DVAIEmbedder(
    OpenAIDVAIAdapter(apiKey: DV.Secrets.get('OPENAI_API_KEY')),
    id: 'openai/text-embedding-3-small',
    dimensions: 1536,
  ),
  vectors: DVInMemoryVectorAdapter(),
  idOf: (Article article) => article.slug,
  fields: <String, String Function(Article)>{
    'body': (Article article) => article.body,
  },
  load: Article.find,
  sensitiveFields: Article.sensitiveFields,
  toJson: (Article article) => article.toPublicJson(),
);
// docs:end

Future<void> semanticSearch(Article article) async {
  // docs:start search-semantic-query
  await article.save();
  await articleIndex.indexed(article); // queues an embedding job

  // A worker embeds it. Queries never wait on the embedder.
  await DV.Jobs.work(queue: 'semantic');

  final DVSemanticPage<Article> page = await articleIndex.query(
    'how do refunds work',
    mode: DVSearchMode.semantic,
    limit: 5,
  );
  for (final DVSemanticHit<Article> hit in page.hits) {
    DV.log('${hit.record.title} matched in ${hit.field}: ${hit.chunk?.text}');
  }
  // docs:end
}
