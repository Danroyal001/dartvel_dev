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
