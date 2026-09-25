// Every data model gets a generated public page unless it opts out.
//
// What that must never do is publish what the model protects. These read the
// generated client for the two places a record reaches a reader from: the
// page the router serves, and the page data, static paths and sitemap the
// server and the static build make without anybody signed in. Whether the
// generated code compiles is generated_client_analyzes_test's job; whether
// the policy questions it asks answer correctly is dartvel_core's
// model_page_access_test.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_cli/src/generators/static_paths_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _article = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.field('authorId'), retain: DVRetention.indefinite)
class const _Article({
  required final String slug,
  @DVModel.pageTitle() required final String title,
  @DVModel.mainContent() required final String body,
  required final bool published,
  required final String authorId,
  @DVModel.sensitiveField() required final String editorNotes,
  @DVModel.featuredImage() @DVModel.sensitiveField() required final String privatePhoto,
});
''';

const String _customer = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true, subject: DVSubject.self, retain: DVRetention.indefinite)
class const _Customer({
  required final String id,
  required final String name,
});
''';

const String _session = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class const _UserSession({required final String id, required final String device});
''';

const String _reading = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class const _Reading({required final int id, required final double value});
''';

const String _memo = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: false)
class const _Memo({required final String id, required final String text});
''';

const String _policy = '''
import 'package:dartvel_core/dartvel.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPolicy(Article)
class ArticlePolicy {
  bool view(DVSessionPrincipal? user, Article article) => article.published;
}
''';

late Directory root;
late String models;
late String pages;
late String stderrText;

Future<void> generate(Map<String, String> files, {Set<String> takenRoutes = const <String>{}}) async {
  root = await Directory.systemTemp.createTemp('dartvel_public_pages_');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  files.forEach((String rel, String source) {
    File(p.join(root.path, 'lib', rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  await ModelGenerator.generate(root: root.path, pkgName: 'app', takenRoutes: takenRoutes);
  models = File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart')).readAsStringSync();
  pages = File(p.join(root.path, 'lib', 'dartvel_client', 'model_pages.g.dart')).readAsStringSync();
}

/// The generated class body of [name], so an assertion about one model is
/// not satisfied by another's.
String classOf(String name) {
  int start = models.indexOf('\nclass const $name(');
  if (start < 0) start = models.indexOf('\nclass $name(');
  expect(start, greaterThan(-1), reason: 'no generated $name');
  final int end = models.indexOf('\nclass ', start + 1);
  return models.substring(start, end < 0 ? models.length : end);
}

String member(String body, String signature) {
  final int start = body.indexOf(signature);
  expect(start, greaterThan(-1), reason: 'no $signature');
  final int end = body.indexOf('\n  }\n', start);
  return body.substring(start, end);
}

String specOf(String model) {
  // The page specs only: Studio's, below them, name every model.
  final String specs = pages.substring(0, pages.indexOf('dartvelStudioModels'));
  final int start = specs.indexOf("model: '$model'");
  if (start < 0) return '';
  return specs.substring(start, specs.indexOf('  ),', start));
}

void main() {
  tearDown(() => root.deleteSync(recursive: true));

  group('by default', () {
    setUp(() => generate(<String, String>{
          'models/article.dart': _article,
          'models/customer.dart': _customer,
          'models/user_session.dart': _session,
          'models/reading.dart': _reading,
          'models/memo.dart': _memo,
          'policies/article_policy.dart': _policy,
        }));

    test('a model that said nothing has a page at its own route', () {
      expect(classOf('Article'), contains('generatePublicPages = true;'));
      expect(classOf('Article'), contains("publicPageRoute = '/articles/:slug'"));
      expect(specOf('Article'), contains("route: '/articles/:slug'"));
    });

    test('a model that opted out, a session and a keyless model have none', () {
      expect(classOf('Memo'), contains('generatePublicPages = false;'));
      expect(classOf('UserSession'), contains('generatePublicPages = false;'));
      expect(classOf('Reading'), contains('generatePublicPages = false;'));
      expect(specOf('Memo'), isEmpty);
      expect(specOf('UserSession'), isEmpty);
      expect(specOf('Reading'), isEmpty);
    });

    test('the page data spec names every protected field, and none as content', () {
      final String spec = specOf('Article');
      expect(spec, contains("protectedFields: <String>{'authorId', 'editorNotes', 'privatePhoto'}"));
      // The annotated featured image is sensitive, so it is not the image.
      expect(spec, contains('imageField: null'));
      expect(spec, contains("titleField: 'title'"));
      expect(spec, contains("contentFields: <String>['body']"));
      expect(spec, isNot(contains("'authorId'],")));
      expect(spec, contains('personal: false'));
    });

    test('the server is told a view policy exists, even one it cannot load', () {
      expect(specOf('Article'), contains('viewPolicy: true'));
      expect(specOf('Customer'), contains('viewPolicy: false'));
    });

    test('the page body never renders a protected field', () {
      final String body = member(classOf('Article'), 'static Widget PageBody(');
      for (final String field in <String>['authorId', 'editorNotes', 'privatePhoto']) {
        expect(body, isNot(contains('model.$field')), reason: field);
      }
      expect(body, contains('model.title'));
    });

    test('the protected fields render only behind the viewSensitive policy', () {
      final String page = member(classOf('Article'), 'static Widget publicPage(');
      expect(page, contains("mayViewProtected('Article', viewer, found)"));
      expect(page, contains('revealProtected'));
      final String extra = member(classOf('Article'), 'static Widget _dvProtectedPageFields(');
      expect(extra, contains('model.authorId'));
      expect(extra, contains('model.editorNotes'));
    });

    test('a refused or unpublished record renders exactly as a missing one', () {
      final String page = member(classOf('Article'), 'static Widget publicPage(');
      expect(page, contains('if (found == null ||'));
      expect(page, contains('!found.published ||'));
      expect(page, contains("!await const DVModelPageAccess().mayView('Article', viewer, found, "
          'personal: false, declaredViewPolicy: true)'));
      // One refusal for all three, so nothing tells them apart.
      expect(RegExp('throw ').allMatches(page), hasLength(1));
    });

    test('static paths name only published records anybody may see', () {
      final String paths = member(classOf('Article'), 'static Future<core.List<String>> publicStaticPaths(');
      expect(paths, contains('if (!model.published) continue;'));
      expect(paths, contains("mayView('Article', null, model, "));
      expect(paths, contains('paths.add(model.slug);'));
    });

    test('a person\'s records asked for by name are never enumerated', () {
      final String paths = member(classOf('Customer'), 'static Future<core.List<String>> publicStaticPaths(');
      expect(paths, contains('return const <String>[];'));
      expect(paths, isNot(contains('DV.Database')));
      expect(specOf('Customer'), contains('personal: true'));
      expect(specOf('Customer'), contains("protectedFields: <String>{'id', 'name'}"));
    });
  });

  test('a default page yields to the application\'s own page at its route', () async {
    await generate(<String, String>{'models/article.dart': _article},
        takenRoutes: <String>{'/articles/:id'});
    expect(classOf('Article'), contains('generatePublicPages = false;'));
    expect(specOf('Article'), isEmpty);
  });

  group('static-path discovery', () {
    test('finds every model under lib/models that did not opt out', () async {
      await generate(<String, String>{
        'models/article.dart': _article,
        'models/user_session.dart': _session,
        'models/reading.dart': _reading,
        'models/memo.dart': _memo,
      });
      final List<StaticPathsProvider> found =
          StaticPathsGenerator.discover(root: root.path, pkgName: 'app');
      expect(found.map((StaticPathsProvider p) => p.className), <String?>['Article']);
      expect(found.single.route, '/articles/:slug');
      expect(found.single.generatesPage, isTrue);
    });

    test('a model elsewhere in lib/ has no class to serve a page, so none', () async {
      await generate(<String, String>{
        'pages/sample.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Sample {
  final String id;
  const _Sample({required this.id});
}
''',
      });
      expect(StaticPathsGenerator.discover(root: root.path, pkgName: 'app'), isEmpty);
    });

    test('yields to a taken route as the model generator does', () async {
      await generate(<String, String>{'models/article.dart': _article});
      expect(
          StaticPathsGenerator.discover(
              root: root.path, pkgName: 'app', takenRoutes: <String>{'/articles/:slug'}),
          isEmpty);
    });
  });
}
