// The names DVRoutes gives its typed targets.
//
// A generated member is only useful if application code can name it. A route
// whose first path segment starts with an underscore produced a private
// member — every route under /_dartvel_admin did — so the target existed and
// nothing outside the generated file could reach it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Generates a client for pages at [routes] and returns `router.g.dart`.
Future<String> routerFor(List<String> routes) async {
  final root = await Directory.systemTemp.createTemp('dartvel_route_names_');
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
      pkgName: 'route_names_app',
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

/// The DVRoutes class body, so an assertion cannot be satisfied by the
/// manifest below it.
String routesClassOf(String router) {
  final start = router.indexOf('class DVRoutes {');
  expect(start, greaterThan(-1), reason: 'no DVRoutes was generated');
  return router.substring(start, router.indexOf('}', start));
}

void main() {
  test('an underscored route still gets a reachable target', () async {
    final routes = routesClassOf(
        await routerFor(<String>['/_dartvel_admin/cache', '/pricing']));

    // `static const _dartvel_admincache` is private: the admin's own routes
    // could not be navigated to through DVRoutes at all.
    expect(routes, isNot(contains('static const _')));
    expect(routes,
        contains(r"dartvel_admincache = DVRouteTarget('/_dartvel_admin/cache')"));
    expect(routes, contains("pricing = DVRouteTarget('/pricing')"));
  });

  test('the root route is still called index', () async {
    final routes = routesClassOf(await routerFor(<String>['/']));

    expect(routes, contains("index = DVRouteTarget('/')"));
  });

  test('the route manifest lists every route', () async {
    final router =
        await routerFor(<String>['/_dartvel_admin/cache', '/pricing']);

    // DVRoutes is static consts, which nothing can enumerate; the manifest is
    // what the admin's route explorer reads.
    expect(router, contains('const List<DVRouteInfo> dartvelRouteManifest'));
    expect(router, contains("path: '/_dartvel_admin/cache'"));
    expect(router, contains("path: '/pricing'"));
  });

  test('a dynamic route records its parameters in the manifest', () async {
    final router = await routerFor(<String>['/posts/:slug']);

    expect(router, contains("parameters: <String>['slug']"));
  });
}
