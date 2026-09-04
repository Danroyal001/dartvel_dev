// The backend has to know what the application mounts, too.
//
// The module registry decides where a schema-isolated module's tables are and
// which database its models use. Registration happened in
// configureDartvelRuntime, which is the client's bootstrap -- so in the
// backend process the registry was empty, every module looked unmounted, and
// its models resolved the plain table name in the application's database.
// Nothing had created that table, and backend functions are where model
// queries actually run.
//
// The registration also cannot be in a file that imports Flutter: the backend
// is a pure Dart server and dart:ui is not there.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
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

Directory workspace() {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_backend_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
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
      data: schema-isolated
''');

  final Directory module = Directory(p.join(root.path, 'modules', 'store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
''');
  File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  return root;
}

Future<void> generate(Directory root) => ClientGenerator.generate(
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

String read(Directory root, String name) =>
    File(p.join(root.path, 'lib', 'dartvel_client', name)).readAsStringSync();

void main() {
  _theServerCalls();
  group('the registration a server can load', () {
    test('the registration itself imports no Flutter', () async {
      final Directory root = workspace();
      await generate(root);

      final String source = read(root, 'modules_data.g.dart');
      expect(source, contains("register("));
      expect(source, contains("id: 'store'"));
      expect(source, isNot(contains('dartvel_flutter')),
          reason: 'a pure Dart server cannot load dart:ui');
      expect(source, isNot(contains('package:flutter/')));
    });

    test('the typed accessors stay where Flutter is allowed', () async {
      final Directory root = workspace();
      await generate(root);

      // DVRouteTarget is a Flutter type, so the typed route targets cannot
      // move; only the registration has to.
      final String flutterSide = read(root, 'modules.g.dart');
      expect(flutterSide, contains('StoreModuleRoutes'));
      expect(flutterSide, contains('DVRouteTarget'));
    });

    test('the client bootstrap still registers exactly once', () async {
      final Directory root = workspace();
      await generate(root);

      final String runtime =
          read(root, 'dartvel_runtime.dart');
      expect(RegExp(RegExp.escape('registerDartvelModules()'))
          .allMatches(runtime)
          .length,
          1,
          reason: 'registering twice would re-register every module');
    });
  });
}


// Appended: the server end of the same thing.
//
// The registration file existing is half the fix. Something has to call it in
// the backend process, and it has to be startBackend rather than each entry
// point, because there are several -- the dev server, whatever a deployment
// runs -- and the one that forgets is the one that reads the wrong table.
void _theServerCalls() {
  group('the generated server', () {
    test('registers the modules before it serves anything', () async {
      final Directory root =
          Directory.systemTemp.createTempSync('dartvel_backend_modules_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'backend', 'functions', 'sum.post.dart'))
          .writeAsStringSync('int sum(int a, int b) => a + b;\n');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'shopfront',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final String routes =
          File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
              .readAsStringSync();

      expect(routes, contains('modules_data.g.dart'),
          reason: 'the Flutter-free registration is the one a server loads');
      expect(routes, contains('registerDartvelModules()'));
      // Before the router is built, because building it is what wires the
      // handlers that go on to query models.
      expect(
        routes.indexOf('registerDartvelModules()'),
        lessThan(routes.indexOf('final router = buildBackendRouter()')),
      );
    });
  });
}
