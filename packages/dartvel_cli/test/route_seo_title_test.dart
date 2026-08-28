// The title a page declares has to reach the running page, not only the
// static file.
//
// dvStaticPage writes `@DVPage(title:)` into each prerendered index.html, so a
// crawler reading /docs/index.html sees "Documentation — Dartvel". Then
// Flutter boots and DartvelSeo applies the page's SeoProps, which default to
// SeoProps.empty, and the project-wide default title overwrites the route's.
//
// Checked in a real browser: /docs/ served the right <title> and showed
// "Dartvel — Flutter, full stack" once the app started. Right for crawlers,
// wrong for every person with JavaScript on, and wrong for the tab they
// bookmark.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Generates a client for pages at [routes] and returns `router.g.dart`.
Future<String> routerFor(List<String> routes) async {
  final root = await Directory.systemTemp.createTemp('dartvel_route_seo_');
  try {
    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      final segments =
          route.split('/').where((String s) => s.isNotEmpty).toList();
      final directory = segments.length > 1
          ? p.join(root.path, 'lib', 'pages', segments.sublist(0, segments.length - 1).join(p.separator))
          : p.join(root.path, 'lib', 'pages');
      Directory(directory).createSync(recursive: true);
      final file = segments.isEmpty ? 'index' : segments.last;
      File(p.join(directory, '$file.page.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage(title: 'P$i')
@pragma('vm:entry-point')
Widget _p$i(BuildContext context) => const Text('p$i');
''');
    }
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);

    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'route_seo_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 8080,
      devBackendHost: 'http://127.0.0.1:8080',
      prodBackendHost: 'https://example.com',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'app',
      seoTitle: 'app',
      seoDesc: 'app',
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
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('the route carries the title its page declared', () async {
    final router = await routerFor(<String>['/docs']);

    // The generated route has to put the declared title underneath whatever
    // the page's own buildWebSeo returns, so a page that says nothing still
    // gets its declared title and a page that overrides one still wins.
    // Read from the scaffold spec rather than pasted in as a literal, so the
    // app bar, the prerendered file and the tab all come from one
    // declaration. The real check that this reaches the tab is the browser
    // pass over the built site; this pins the wiring.
    expect(
      router,
      matches(RegExp(r'SeoProps\(title:\s*page\.pageScaffold\.title\)\s*'
          r'\.merge\(\s*page\.buildWebSeo')),
      reason: "the declared title must sit under the page's own props, so an "
          'explicit buildWebSeo title still wins',
    );
    expect(router, contains("title: 'P0'"),
        reason: 'the scaffold spec must still carry the declared title');
  });

  test('a page with no declared title does not fabricate one', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_seo_untitled_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
        .writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage()
@pragma('vm:entry-point')
Widget _home(BuildContext context) => const Text('home');
''');
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);

    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'untitled_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 8080,
      devBackendHost: 'http://127.0.0.1:8080',
      prodBackendHost: 'https://example.com',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'app',
      seoTitle: 'app',
      seoDesc: 'app',
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

    final router = File(
            p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
        .readAsStringSync();

    // The project default is what should show, so the route must not force a
    // title of its own.
    expect(router, isNot(contains("SeoProps(title: 'home'")));
  });
}
