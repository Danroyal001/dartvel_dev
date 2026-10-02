// Every application gets the two error routes, and a build can prerender them.
//
// They used to be documents the build wrote by hand at build time, which put
// two pages outside the router: no @DVPage, no theme, no capture, and -- for
// the offline page -- no way to be a page at all, since it is shown exactly
// when the network is gone. As routes they go through the one render path,
// like every other page.
//
// What is pinned here is the generator's half: that the routes are declared,
// that they are not declared over an application page, and that they are in
// the manifest and the typed targets, so a build can see them and a person
// can name one.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _generate(Map<String, String> pages) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_error_routes_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  pages.forEach((String name, String source) {
    File(p.join(root.path, 'lib', 'pages', name))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shop_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Shop',
    seoTitle: 'Shop',
    seoDesc: 'Shop',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(const <String, Object?>{}),
  );
  return root;
}

String _page(String name, String annotation) => '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$annotation
Widget ${name}Page(BuildContext context) => const SizedBox.shrink();
''';

String _read(Directory root, String file) =>
    File(p.join(root.path, 'lib', 'dartvel_client', file)).readAsStringSync();

/// The route block for [path] in the generated router.
String _route(String router, String path) {
  final int at = router.indexOf("path: '$path'");
  expect(at, isNot(-1), reason: 'no route for $path');
  final int end = router.indexOf('GoRoute(', at + 1);
  return router.substring(at, end == -1 ? router.length : end);
}

void main() {
  test('every application serves the not-found route, drawn as a page', () async {
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    });
    final String router = _read(root, 'router.g.dart');
    expect(_route(router, '/404'), contains('DVNotFoundPage('));
  });

  test('every application serves the offline route, carrying where the '
      'person was going', () async {
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    });
    final String router = _read(root, 'router.g.dart');
    expect(
      _route(router, '/offline'),
      contains("DVOfflinePage(from: state.uri.queryParameters['from'])"),
    );
  });

  test('an application page at the same path wins, because the application '
      'said so', () async {
    // The same rule the second-factor route follows: a framework route is
    // declared only where nothing else claimed the path. Overwriting a page
    // somebody wrote would make a @DVPage silently unreachable.
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
      'offline.dart': _page('offline', "@DVPage(title: 'Offline')"),
    });
    final String router = _read(root, 'router.g.dart');
    expect(_route(router, '/offline'), isNot(contains('DVOfflinePage(')));
    // The application's own generated page is the one that is built.
    expect(_route(router, '/offline'), contains('OfflinePageGeneratedPage'));
  });

  test('neither is an application page, so neither is in the manifest or the '
      'typed targets', () async {
    // The manifest is the route explorer and the sitemap's source, and both
    // read it as "pages this application wrote". An error page is neither a
    // page nor something an application navigates to, and listing it would
    // hand a crawler two URLs that exist only to report a problem. The build
    // finds them by reading the router, which is where they are declared.
    // dvNotFoundRoute and dvOfflineRoute are the way to name them.
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    });
    final String router = _read(root, 'router.g.dart');
    final int manifest = router.indexOf('dartvelRouteManifest');
    expect(manifest, isNot(-1));
    expect(router.substring(manifest), isNot(contains("path: '/404'")));
    expect(router.substring(manifest), isNot(contains("path: '/offline'")));
    expect(router, isNot(contains("DVRouteTarget('/404')")));
    expect(router, isNot(contains("DVRouteTarget('/offline')")));
  });
}
