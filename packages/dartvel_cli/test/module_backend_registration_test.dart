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
  _theShell();
  _theTheme();
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

// Appended: the theme mode reaching the router.
//
// A mode that only the registry knows is a mode nothing applies. The router
// is where a module's pages are built, so it is where the parent's `theme:`
// declaration has to be honoured -- and only there, because the parent's own
// pages must not be wrapped in a module's look.
void _theTheme() {
  group('a module with a theme mode of its own', () {
    Directory themed(String mode) {
      final Directory root = workspace();
      final File pubspec = File(p.join(root.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst(
              '      data: schema-isolated',
              '      data: schema-isolated\n      theme: $mode',
            ),
      );
      return root;
    }

    test('its pages are wrapped, and the parent\'s are not', () async {
      final Directory root = themed('override');
      await generate(root);

      final String router = read(root, 'router.g.dart');
      expect(router, contains("dvModuleTheme(context, 'store'"));
      // One wrap per module page, and nothing else: the count is what says
      // the parent's own pages were left alone.
      expect(
        RegExp(RegExp.escape("dvModuleTheme(context, 'store'"))
            .allMatches(router)
            .length,
        1,
      );
    });

    test('an inheriting module is not wrapped at all', () async {
      final Directory root = themed('inherit');
      await generate(root);

      // Wrapping and then resolving to the parent's theme would work and
      // would put a widget in the tree of every module page for nothing.
      expect(read(root, 'router.g.dart'), isNot(contains('dvModuleTheme')));
    });

  });
}

// Appended: the shell mode reaching the router, the same way the theme does.
void _theShell() {
  group('a module with a shell mode of its own', () {
    Directory withMode(String key, String mode) {
      final Directory root = workspace();
      final File pubspec = File(p.join(root.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst(
              '      data: schema-isolated',
              '      data: schema-isolated\n      $key: $mode',
            ),
      );
      return root;
    }

    test('its pages are wrapped', () async {
      final Directory root = withMode('shell', 'none');
      await generate(root);

      expect(read(root, 'router.g.dart'),
          contains("dvModuleShell(context, 'store'"));
    });

    test('an inheriting module is not wrapped', () async {
      final Directory root = withMode('shell', 'inherit');
      await generate(root);

      expect(read(root, 'router.g.dart'), isNot(contains('dvModuleShell')));
    });

    test('both modes wrap, and in an order that puts the theme outside',
        () async {
      final Directory root = workspace();
      final File pubspec = File(p.join(root.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst(
              '      data: schema-isolated',
              '      data: schema-isolated\n      shell: override\n'
                  '      theme: override',
            ),
      );
      await generate(root);

      final String router = read(root, 'router.g.dart');
      // The module's chrome is built with the module's theme, which it can
      // only be if the theme is the outer of the two. The other order gives
      // a module a header painted in the application's colours above a page
      // painted in its own.
      expect(router.indexOf('dvModuleTheme'),
          lessThan(router.indexOf('dvModuleShell')));
    });
  });
}
