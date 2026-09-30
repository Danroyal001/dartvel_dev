// Semantic search and a sync policy are the model's own, like search and
// import before them.
//
// A sample had to build a DVSemanticIndex<Article> by hand, re-listing the
// id, the fields, the loader, the sensitive fields and the JSON the model
// already declares, and then name DVModelSync to say who may see a change.
// Both are machinery. What an application has is a model.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generated() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_semantic_gen_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'article.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true, semantic: true)
class _Article {
  final String id;
  final String title;
  final String body;
  @DVModel.sensitiveField()
  final String authorEmail;

  const _Article({
    required this.id,
    required this.title,
    required this.body,
    required this.authorEmail,
  });
}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'semantic_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  semanticSurfaceTests();
  semanticFieldTests();

  test('the index is configured through the model', () async {
    final String content = await generated();

    expect(content, contains('static void useSemanticSearch('));
    expect(
      content,
      contains('static Future<DVSemanticPage<Article>> semanticSearch('),
    );
  });

  test('the index is built from what the model already declares', () async {
    final String content = await generated();

    // The reader passes an embedder and a vector store. Everything else --
    // the id, the fields, the loader, the sensitive set, the JSON -- comes
    // from the model, because re-stating it is how the two drift apart.
    expect(content, contains('idOf: (Article record) => record.id'));
    expect(content, contains('load: Article.find'));
    expect(content, contains('sensitiveFields: Article.sensitiveFields'));
    expect(content, isNot(contains("'authorEmail': (Article record)")));
    expect(content, contains("'body': (Article record) => record.body"));
  });

  test('saving a model indexes it, with no second call', () async {
    final String content = await generated();

    expect(content, contains('await _dvSemanticIndex?.indexed('));
  });

  test('who may see a change is the model\'s too', () async {
    final String content = await generated();

    expect(content, contains('static void syncPolicy('));
  });

  test('no application names DVSemanticIndex or DVModelSync to use them',
      () async {
    final String content = await generated();

    // They appear inside the generated body, which is framework code. What
    // must not exist is a public companion the reader has to construct.
    expect(content, isNot(contains('class ArticleSemanticIndex')));
    expect(content, isNot(contains('class ArticleIndex')));
  });
}

void semanticSurfaceTests() {
  test('hybrid and keyword modes read the model\'s own search provider',
      () async {
    final String content = await generated();

    // useSemanticSearch built its index with no keyword provider, so
    // Article.semanticSearch(q, mode: DVSearchMode.hybrid) threw "keyword
    // search on article needs a keyword provider" although the model is
    // searchable and has one. Read when the query runs, so a provider set
    // after useSemanticSearch is the one used.
    expect(content,
        contains('keyword: DVDeferredSearchProvider<Article>(() => _searchProvider)'));
  });

  test('records stored before semantic search was configured can be embedded',
      () async {
    final String content = await generated();

    // Saving is what enqueued an embedding, so every record written before
    // useSemanticSearch -- or by a process with no worker -- was never
    // found, and the model had no member to say "embed what is stored".
    expect(content, contains('static Future<int> semanticBackfill('));
    expect(content, contains('index.backfill(await Article.all(), complete: true)'));
  });
}

void semanticFieldTests() {
  test('declared searchable fields are what is embedded, and nothing else',
      () async {
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_semantic_fields_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true, semantic: true)
class const _Note({
  required final String id,
  required final String path,
  @DVModel.searchableField() required final String heading,
  @DVModel.searchableField() required final String body,
});
''');
    await ModelGenerator.generate(
        root: root.path, pkgName: 'fields_app', buildId: 'test-build');
    final String content =
        File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
            .readAsStringSync();

    // With no @DVModel.mainContent(), the page falls back to every String
    // field as a content candidate, and the semantic index took that
    // fallback too: a path, a slug or a status was embedded as prose and
    // matched queries that happened to share a word with it.
    expect(content, contains("'heading': (Note record) => record.heading"));
    expect(content, contains("'body': (Note record) => record.body"));
    expect(content, isNot(contains("'path': (Note record) => record.path")));
  });
}
