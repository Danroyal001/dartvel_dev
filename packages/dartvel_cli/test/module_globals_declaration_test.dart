// What a module shares, as the build reads it.
//
// The specification declares module globals in two places: the module's own
// pubspec says what it exports, the parent's says what it hands down. The
// runtime honours both, and the build read neither -- so every declaration
// arrived at the registry empty and a module that had written down exactly
// what it shares shared nothing.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

Directory workspace({
  String parentGlobals = '''
      globals:
        inherit: [auth, currentTenant]
''',
  String moduleGlobals = '''
    globals:
      export: [cart, checkoutState]
''',
}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_globals_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: embedded
$parentGlobals
''');

  final Directory module = Directory(p.join(root.path, 'modules', 'store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
$moduleGlobals
''');
  File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  return root;
}

Future<String> generatedRegistry(Directory root) async {
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
  // Both files: the registration is in modules_data.g.dart, which imports
  // core alone so the backend can load it, and the typed accessors stay in
  // modules.g.dart, which is Flutter because a route target is.
  return File(p.join(root.path, 'lib', 'dartvel_client', 'modules_data.g.dart'))
          .readAsStringSync() +
      File(p.join(root.path, 'lib', 'dartvel_client', 'modules.g.dart'))
          .readAsStringSync();
}

void main() {
  test('the module says what it exports and the parent what it hands down', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.exportedGlobals, <String>['cart', 'checkoutState']);
    expect(mount.inheritedGlobals, <String>['auth', 'currentTenant']);
  });

  test('a module that declares nothing shares nothing', () {
    // The default the specification gives: isolated unless written down.
    final DVModuleMount mount = dvDiscoverModuleMounts(
            workspace(parentGlobals: '', moduleGlobals: '').path)
        .single;

    expect(mount.exportedGlobals, isEmpty);
    expect(mount.inheritedGlobals, isEmpty);
  });

  test('both reach the generated registry', () async {
    // Where the runtime reads them. Declared and not registered is the same
    // as not declared, and reads exactly like a working feature.
    final String registry = await generatedRegistry(workspace());

    expect(registry, contains("'export': <String>['cart', 'checkoutState'],"));
    expect(registry, contains("'inherit': <String>['auth', 'currentTenant'],"));
  });
}
