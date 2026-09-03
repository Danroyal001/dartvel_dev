// A mounted module's pages in the parent's router.
//
// Discovery finds them and rebases them; this is the half that makes the
// parent serve them. Without it the routes would be in the index, the
// sitemap and the server's manifest while the running application answered
// its own not-found page -- a crawler follows the link, gets HTML, and sees
// nothing there. That failure was fixed once for generated model pages;
// mounting must not reintroduce it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

const String _productPage = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Product')
Widget _productPage(BuildContext context) => const DVText('product');
''';

/// A parent with one page and a module mounted at /store.
Directory? lastParent;

Future<String> generateParent({String mount = '/store', String deployment = 'embedded'}) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_module_router_');
  lastParent = root;
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: $mount
      deployment: $deployment
''');

  final Directory module = Directory(p.join(root.path, 'modules', 'store'))..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
flutter:
  assets:
    - assets/logo.png
dartvel:
  module:
    id: store
''');
  File(p.join(module.path, 'lib', 'pages', 'products', '[id].page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_productPage);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shopfront',
    buildId: 'b',
    modules: dvDiscoverModuleMounts(root.path),
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
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
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart')).readAsStringSync();
}

void main() {
  test('the parent serves the module\'s page at the mounted path', () async {
    final String router = await generateParent();

    expect(router, contains("import 'package:store/dartvel_client/dartvel_client.dart'"));
    expect(router, contains("path: '/store/products/:id'"));
    // The module's own generated page, not a placeholder: the parent builds
    // what the module's generator made.
    expect(router, contains('ProductPageGeneratedPage()'));
  });

  test('the mounted routes are in the route manifest, so tools can enumerate them', () async {
    final String router = await generateParent();

    final int at = router.indexOf('dartvelRouteManifest');
    expect(at, greaterThan(0));
    final String manifest = router.substring(at);
    expect(manifest, contains("path: '/store/products/:id'"));
    expect(manifest, contains("parameters: <String>['id']"));
    expect(manifest, contains("module: 'store'"), reason: 'a tool can tell whose route it is');
  });

  test('the parent\'s own routes are untouched', () async {
    final String router = await generateParent();

    expect(router, contains("path: '/'"));
    expect(router, contains('HomePageGeneratedPage'));
  });

  test('a module mounted at the root serves its pages there', () async {
    final String router = await generateParent(mount: '/');

    expect(router, contains("path: '/products/:id'"));
  });

  test('a backend-only module adds no routes and no import', () async {
    final String router = await generateParent(deployment: 'backend-only');

    expect(router, isNot(contains('package:store/dartvel_client')));
    expect(router, isNot(contains('/store/products')));
  });

  group('the module registry', () {
    // DV.Modules is documented as having typed <id> accessors the generator
    // emits, and nothing emitted them: the registry was empty in every
    // application, so DV.Modules.store threw for a module the build had
    // just mounted.
    String modulesFile() =>
        File(p.join(lastParent!.path, 'lib', 'dartvel_client', 'modules.g.dart')).readAsStringSync();

    test('each mounted module is registered with its id and mount point', () async {
      await generateParent();
      final String generated = modulesFile();

      expect(generated, contains('void registerDartvelModules()'));
      expect(generated, contains("id: 'store'"));
      expect(generated, contains("mountPath: '/store'"));
    });

    test('the module\'s assets are registered as the paths that find them here', () async {
      await generateParent();

      expect(modulesFile(), contains("assets: const <String, String>{"));
      expect(modulesFile(), contains("'assets/logo.png': 'packages/store/assets/logo.png',"));
    });

    test('a typed accessor reaches it, so DV.Modules.store is the module', () async {
      await generateParent();

      expect(modulesFile(), contains('extension DartvelModules on DVModuleRegistry'));
      expect(modulesFile(), contains("DVModule get store =>"));
    });

    test('a backend-only module is registered too: it has no pages, not no existence', () async {
      await generateParent(deployment: 'backend-only');

      expect(modulesFile(), contains("id: 'store'"));
    });

    test('the runtime registers them, rather than leaving it to the application', () async {
      await generateParent();
      final String runtime =
          File(p.join(lastParent!.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart')).readAsStringSync();

      expect(runtime, contains('registerDartvelModules()'));
    });
  });
}
