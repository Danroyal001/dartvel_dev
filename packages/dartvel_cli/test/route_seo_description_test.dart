// Every page on a Dartvel site shipped the same meta description.
//
// `@DVPage` could say what a page is *called* and not what it is *about*, so
// the static build wrote `dartvel.seo.description` into all fifty pages and
// the running app applied the project default over every route. Two pages
// with the same description are two pages a search engine has no reason to
// tell apart, which is the whole of the problem: the vs pages, the docs and
// the home page competed for one snippet.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Generates a client whose one page is [annotation], and returns
/// `router.g.dart`.
Future<String> routerFor(String annotation) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_seo_description_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages', 'vs')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'vs', 'expo.page.dart'))
      .writeAsStringSync('''
import 'package:flutter/widgets.dart';

$annotation
@pragma('vm:entry-point')
Widget _expo(BuildContext context) => const Text('expo');
''');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'seo_description_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 8080,
    devBackendHost: 'http://127.0.0.1:8080',
    prodBackendHost: 'https://example.com',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'app',
    seoTitle: 'app',
    seoDesc: 'the whole site says this',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'none',
    durationMs: 200,
    curve: 'linear',
    normalizeTrailing: true,
    notFoundRedirect: '/',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

const String _sentence =
    'Expo for Flutter: builds, updates and submissions without a Mac.';

void main() {
  _readerTests();

  test('a page says what it is about, and the route carries it', () async {
    final String router = await routerFor(
      "@DVPage(title: 'Dartvel vs Expo', description: '$_sentence')",
    );

    expect(router, contains(_sentence),
        reason: 'the declared description must reach the generated route');
    expect(
      dvRouteDescriptions(router),
      <String, String>{'/vs/expo': _sentence},
      reason: 'the static build reads it from the router, as it reads titles',
    );
  });

  test('the running page applies it, not only the prerendered file', () async {
    final String router = await routerFor(
      "@DVPage(title: 'Dartvel vs Expo', description: '$_sentence')",
    );

    // DartvelSeo merges buildWebSeo over the project default, so a
    // description declared here survives the app booting. Without the
    // override the default overwrites the route's own the moment Flutter
    // starts -- right for a crawler, wrong for the person reading the tab
    // and for anything that re-reads the DOM.
    expect(
      router,
      matches(RegExp(r'SeoProps\s+buildWebSeo\([\s\S]{0,200}?'
          r"SeoProps\(description:\s*'" + RegExp.escape(_sentence))),
      reason: 'the page class must override buildWebSeo with it',
    );
  });

  test('a page that says nothing about itself overrides nothing', () async {
    final String router = await routerFor("@DVPage(title: 'Dartvel vs Expo')");

    expect(dvRouteDescriptions(router), isEmpty);
    expect(router, isNot(contains('SeoProps buildWebSeo')),
        reason: 'an empty override would replace the project default with '
            'nothing on every route that declared no description',
    );
  });
}

// A description long enough to be worth writing does not fit on one line, and
// a description about a product whose name ends in "'s" contains an
// apostrophe. Both go through `_namedStringArg`, which read a single quoted
// run and stopped: the first produced a sentence cut off at its first line,
// which is the dangerous shape because a half sentence still looks like a
// description; the second produced `'Dartvel is Flutter\'`, which does not
// compile, and took the whole generated router down with it.
//
// Titles go through the same reader, so each case is checked there too.
void _readerTests() {
  const String wrapped = 'Build screens from two widgets, DVBox for layout '
      'and DVText for text, and style both with one chain of modifiers.';

  test('a description split across lines arrives whole', () async {
    final String router = await routerFor('''
@DVPage(
  title: 'Dartvel UI',
  description: 'Build screens from two widgets, DVBox for layout '
      'and DVText for text, and style both with one chain of modifiers.',
)''');

    expect(
      dvRouteDescriptions(router)['/vs/expo'],
      wrapped,
      reason: 'every fragment of an adjacent-string literal belongs to the '
          'sentence; stopping at the first leaves a meta tag that reads as a '
          'finished thought and is half of one',
    );
  });

  test('an apostrophe in a description still compiles', () async {
    final String router = await routerFor(
      "@DVPage(title: 'Dartvel', description: "
      "'Dartvel is Flutter\\'s Laravel, in one Dart project.')",
    );

    expect(
      dvRouteDescriptions(router)['/vs/expo'],
      "Dartvel is Flutter's Laravel, in one Dart project.",
      reason: 'the escape must survive the round trip through the router',
    );
    expect(
      router,
      isNot(contains(r"description: 'Dartvel is Flutter\')")),
      reason: 'a literal truncated at the escaped quote is not valid Dart, '
          'and every page in the project fails to compile behind it',
    );
  });

  test('a title split across lines arrives whole', () async {
    final String router = await routerFor('''
@DVPage(
  title: 'Dartvel build targets: every platform '
      'and its verified status',
  showAppBar: false,
)''');

    // The scaffold title is re-emitted as the literals it was written as,
    // which Dart joins when the router is compiled, so the assertion is that
    // the second half arrives at all. It used to be dropped: the page kept a
    // title ending in "every platform " and nothing said a word.
    expect(router, contains('and its verified status'),
        reason: 'the reader stopped at the first literal and threw the rest '
            'of the title away');
    expect(
      router,
      matches(RegExp(r"title: 'Dartvel build targets: every platform '"
          r"\s*'and its verified status'")),
      reason: 'both fragments belong to the one title the page declared',
    );
  });

  test('an apostrophe in a title still compiles', () async {
    final String router = await routerFor(
      "@DVPage(title: 'Flutter\\'s Laravel')",
    );

    expect(router, contains(r"Flutter\'s Laravel"));
    expect(router, isNot(contains(r"title: 'Flutter\')")));
  });
}
