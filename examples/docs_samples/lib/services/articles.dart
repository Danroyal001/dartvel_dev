import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

Future<void> crud() async {
  // docs:start models-crud
  final Article article = Article(
    slug: 'hello-world',
    title: 'Hello, world',
    body: 'The first article.',
    tags: 'news',
    published: false,
    authorId: 'user-1',
    editorNotes: 'Check the title',
  );
  await article.save();

  final List<Article> all = await Article.all();
  final Article? found = await Article.find('hello-world');

  final Article published = await found!.copyWith(published: true).save();
  await published.destroy();
  // docs:end
  debugPrint('${all.length}');
}

Future<void> conflicts(Article article) async {
  // docs:start models-conflict
  try {
    await article.save();
  } on DVConflictError catch (conflict) {
    // Someone saved a newer version after you read this one.
    debugPrint('Stored version ${conflict.actualVersion}');
  }

  // Replace the stored row on purpose.
  await Article.save(article, onConflict: DVConflict.lastWriteWins);
  // docs:end
}

Future<void> history(Article article) async {
  // docs:start models-history
  // Needs @DVModel(history: DVHistory(...)).
  final List<DVHistoryEntry> entries = await article.history();
  for (final DVHistoryEntry entry in entries) {
    debugPrint('version ${entry.version} at ${entry.at}');
  }
  await article.revert(to: entries.first);
  // docs:end
}

Future<void> softDelete(Article article) async {
  // docs:start models-soft-delete
  // Needs @DVModel(softDelete: true).
  await article.destroy(); // hidden from find() and all()

  final Article? deleted = await Article.withDeleted.find(article.slug);
  final List<Article> everything = await Article.withDeleted.all();

  await Article.restore(article.slug); // visible again
  // docs:end
  debugPrint('$deleted ${everything.length}');
}

// docs:start models-widgets
Widget articleEditor(Article article) => article.Form();

Widget articleTable(List<Article> articles) => Article.Table(articles);

Widget articlePage(Article article) => Article.Page.sync(article);
// docs:end

// docs:start models-reactive
Widget liveArticle(BuildContext context, Article article) {
  final DVSignal<Article> current = article.signal(context);
  return Article.Page.signal(current);
}
// docs:end

Future<void> search() async {
  // docs:start models-search
  Article.useSearchProvider(DVInMemorySearchProvider<Article, ArticleFacets>(
    records: await Article.all(),
    document: (Article article) => '${article.title} ${article.body}',
  ));

  final DVSearchResultPage<Article> page = await Article.search('dart', perPage: 10);
  // docs:end
  debugPrint('${page.total}');
}
