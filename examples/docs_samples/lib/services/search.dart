import '../dartvel_client/dartvel_client.dart';

void hostedSearch() {
  // docs:start search-hosted
  Article.useSearchProvider(MeilisearchProvider<Article, ArticleFacets>(
    baseUrl: Uri.parse('https://search.example.com'),
    apiKey: DV.Secrets.get('MEILISEARCH_KEY'),
    indexName: 'articles',
    fromJson: ArticleParser.fromJson,
    tuning: Article.searchTuning, // from dartvel.search in pubspec.yaml
  ));
  // docs:end
}

Future<void> highlights() async {
  // docs:start search-results
  final DVSearchResultPage<Article> page =
      await Article.search('dart', page: 1, perPage: 20);

  for (int i = 0; i < page.items.length; i++) {
    final Article article = page.items[i];
    final String snippet = page.highlights.isEmpty ? '' : page.highlights[i];
    DV.log('${article.title}: $snippet');
  }
  DV.log('${page.total} matches, facets ${page.facetCounts}');
  // docs:end
}

// docs:start search-semantic-index
// The model says it has one. The embedder and the vector store are the only
// things Dartvel cannot know, so they are the only things passed.
void semanticIndex() {
  Article.useSemanticSearch(
    embedder: DVAIEmbedder(
      OpenAIDVAIAdapter(apiKey: DV.Secrets.get('OPENAI_API_KEY')),
      id: 'openai/text-embedding-3-small',
      dimensions: 1536,
    ),
    vectors: DVInMemoryVectorAdapter(),
  );
}
// docs:end

Future<void> semanticSearch(Article article) async {
  // docs:start search-semantic-query
  // Saving queues the embedding. There is no second call, and nothing waits
  // on the embedder: a worker drains the queue with
  //
  //     dartvel queue work --queue semantic
  await article.save();

  final DVSemanticPage<Article> page = await Article.semanticSearch(
    'how do refunds work',
    limit: 5,
  );
  for (final DVSemanticHit<Article> hit in page.hits) {
    DV.log('${hit.record.title} matched in ${hit.field}: ${hit.chunk?.text}');
  }
  // docs:end
}
