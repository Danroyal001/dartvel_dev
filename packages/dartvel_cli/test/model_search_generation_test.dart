// Searching an Article is Article.search.
//
// The generator wrote a companion class, ArticleSearch, and put the query,
// the provider and the tuning on it. That is a second name to learn for one
// model's own capability, and it sat beside ArticleImport doing the same
// thing for importing. A model's capabilities belong to the model.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generated() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_search_gen_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'article.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(searchable: true)
class _Article {
  final String id;
  final String title;
  @DVModel.sensitiveField()
  final String authorEmail;

  const _Article({
    required this.id,
    required this.title,
    required this.authorEmail,
  });
}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'search_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  importExportTests();

  test('search, its provider and its tuning are the model\'s', () async {
    final String content = await generated();

    expect(content, contains('static Future<DVSearchResultPage<Article>> search('));
    expect(content, contains('static void useSearchProvider('));
    expect(content, contains('static const DVSearchTuning searchTuning ='));
  });

  test('there is no companion class', () async {
    final String content = await generated();

    expect(content, isNot(contains('class ArticleSearch {')),
        reason: 'one model, one name');
  });

  test('the facets are named for the model, and exclude a sensitive field',
      () async {
    final String content = await generated();

    final int facets = content.indexOf('class const ArticleFacets(');
    expect(facets, isNonNegative);
    expect(content, isNot(contains('ArticleSearchFacets')));
    // A facet is client-facing, so a sensitive field is not one.
    final String declaration =
        content.substring(facets, content.indexOf(');', facets));
    expect(declaration, contains('title'));
    expect(declaration, isNot(contains('authorEmail')));
  });
}

// Importing and exporting are the model's too.
//
// ArticleImport and ArticleExport were two more companion classes for two
// more of one model's own capabilities. They stay as the private machinery
// the model reaches for, and an application names the model.
void importExportTests() {
  test('import and export are members of the model', () async {
    final String content = await generated();

    for (final String member in <String>[
      'static DVImportResult<Article> importCsv(',
      'static DVImportResult<Article> importNdjson(',
      'static DVExportResult exportCsv(',
      'static Stream<DVExportResult> exportStreamNdjson(',
    ]) {
      expect(content, contains(member), reason: member);
    }
  });

  test('the companions are private', () async {
    final String content = await generated();

    expect(content, contains('class _ArticleImport {'));
    expect(content, contains('class _ArticleExport {'));
    expect(content, isNot(contains('class ArticleImport {')));
    expect(content, isNot(contains('class ArticleExport {')));
  });
}
