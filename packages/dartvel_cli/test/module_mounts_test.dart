// Mounting a module into a parent application.
//
// A module is a complete Dartvel application: its own pages, its own route
// base, runnable on its own. Mounted, `/products/:id` becomes
// `/store/products/:id`, and the parent's route index, sitemap, static
// generation and server rendering all have to know about it -- the
// specification says mounted modules contribute their routes to every one
// of those. Nothing at build time read `dartvel.modules` at all, so a
// mounted module's pages existed only in the module's own project.
import 'dart:io';

import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

/// A parent with a module beside it, both real projects on disk.
Directory workspace({
  String mount = '/store',
  String moduleBase = '/',
  Map<String, String> modulePages = const <String, String>{
    'index.page.dart': _page,
    'products/[id].page.dart': _page,
  },
  String? deployment,
  bool sitemap = true,
}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_modules_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source:
        path: modules/store
      mount: $mount
      deployment: ${deployment ?? 'embedded'}
      sitemap: ${sitemap ? 'include' : 'exclude'}
''');
  final Directory module = Directory(p.join(root.path, 'modules', 'store'))..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
flutter:
  assets:
    - assets/logo.png
    - assets/icons/
dartvel:
  pagesDir: lib/pages
  module:
    id: store
    name: Store
    version: 1.2.0
    routes:
      base: $moduleBase
''');
  modulePages.forEach((String rel, String source) {
    final File file = File(p.join(module.path, 'lib', 'pages', rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  });
  return root;
}

void main() {
  test('a mounted module is found, with its id, package and mount point', () {
    final List<DVModuleMount> mounts = dvDiscoverModuleMounts(workspace().path);

    expect(mounts, hasLength(1));
    expect(mounts.single.id, 'store');
    expect(mounts.single.packageName, 'store');
    expect(mounts.single.mount, '/store');
    expect(mounts.single.name, 'Store');
    expect(mounts.single.version, '1.2.0');
    expect(mounts.single.deployment, DVModuleDeployment.embedded);
    expect(mounts.single.inSitemap, isTrue);
    expect(mounts.single.problems, isEmpty);
  });

  test('the module\'s routes are rebased under the mount point', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.routes.map((DVModuleRoute r) => r.standalone), <String>['/', '/products/:id']);
    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>['/store', '/store/products/:id']);
  });

  test('a module mounted at the root keeps its own routes', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(mount: '/').path).single;

    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>['/', '/products/:id']);
  });

  test('a module with its own route base has the base taken off before the mount goes on', () {
    // The module answers at /shop/products standalone and, mounted at
    // /store, at /store/products -- not /store/shop/products.
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(moduleBase: '/shop').path).single;

    expect(mount.routes.map((DVModuleRoute r) => r.standalone), <String>['/shop', '/shop/products/:id']);
    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>['/store', '/store/products/:id']);
  });

  test('a trailing slash on the mount does not double the separator', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(mount: '/store/').path).single;

    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>['/store', '/store/products/:id']);
  });

  test('each route says which file it came from, so the parent can import it', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.routes.first.import, 'package:store/pages/index.page.dart');
    expect(mount.routes.last.import, 'package:store/pages/products/[id].page.dart');
  });

  test('each route names the widget the module generated for it', () {
    // The parent serves the module's own generated page, so it has to name
    // the class the module's generator made -- by the same rule, in one
    // place, or the parent would import a name that is not there.
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.routes.first.widget, 'APageGeneratedPage');
    expect(mount.clientImport, 'package:store/dartvel_client/dartvel_client.dart');
  });

  test('a page whose entrypoint cannot be found is skipped and said', () {
    final Directory root = workspace(modulePages: <String, String>{
      'index.page.dart': _page,
      'broken.page.dart': 'class NotAPage {}\n',
    });

    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>['/store']);
    expect(mount.problems.single, contains('broken.page.dart'));
  });

  test('the module\'s assets are named as the parent must ask for them', () {
    // Flutter serves another package's asset under packages/<name>/, so the
    // path a module uses standing alone is not the path that finds it once
    // it is mounted. A module that hard-coded either would be wrong in the
    // other place.
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.assets, <String, String>{
      'assets/logo.png': 'packages/store/assets/logo.png',
      'assets/icons/': 'packages/store/assets/icons/',
    });
  });

  test('a module that declares no assets has none', () {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_modules_noassets_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
''');
    final Directory module = Directory(p.join(root.path, 'modules', 'store'))..createSync(recursive: true);
    File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('name: store\n');

    expect(dvDiscoverModuleMounts(root.path).single.assets, isEmpty);
  });

  test('a backend-only module contributes no routes', () {
    final DVModuleMount mount =
        dvDiscoverModuleMounts(workspace(deployment: 'backend-only').path).single;

    expect(mount.deployment, DVModuleDeployment.backendOnly);
    expect(mount.routes, isEmpty, reason: 'a backend-only module has no pages to mount');
  });

  test('a module excluded from the sitemap says so, and keeps its routes', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(sitemap: false).path).single;

    expect(mount.inSitemap, isFalse);
    expect(mount.routes, isNotEmpty);
  });

  test('a source path that is not there is a problem, not a crash', () {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_modules_missing_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/nowhere }
      mount: /store
''');

    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.routes, isEmpty);
    expect(mount.problems.single, contains('modules/nowhere'));
  });

  test('a mount that is not a path is refused rather than joined into nonsense', () {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_modules_bad_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: store
''');

    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.problems, anyElement(contains('mount')));
    expect(mount.mount, '/', reason: 'a mount that is not a path mounts nothing under itself');
  });

  test('a project with no modules has none', () {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_modules_none_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: solo\n');

    expect(dvDiscoverModuleMounts(root.path), isEmpty);
  });
}
