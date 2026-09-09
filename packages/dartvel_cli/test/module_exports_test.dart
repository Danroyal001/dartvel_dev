// What a module says it shares, honoured.
//
// The specification writes an exports block on a module -- pages, functions
// and a list of models -- and nothing read any of it. A module that had
// written down exactly what it shares shared everything anyway, because a
// module compiled into a parent contributes its pages to the route index and
// its functions to the parent router whatever the block says. An author who
// wrote `pages: false` was refused nothing and told nothing, which is the
// worst of the three possible outcomes: silence reads as agreement.
//
// This is the same failure the globals declaration had before it was built,
// one level up.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

/// A parent with a module beside it, the module declaring [exports].
Directory workspace({String exports = ''}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_exports_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source:
        path: modules/store
      mount: /store
      deployment: embedded
''');

  final Directory module = Directory(p.join(root.path, 'modules', 'store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  pagesDir: lib/pages
  module:
    id: store
    name: Store
    version: 1.2.0
    routes:
      base: /
$exports
''');
  final File page = File(p.join(module.path, 'lib', 'pages', 'index.page.dart'));
  page.parent.createSync(recursive: true);
  page.writeAsStringSync(_page);

  final File fn =
      File(p.join(module.path, 'lib', 'backend', 'functions', 'total.post.dart'));
  fn.parent.createSync(recursive: true);
  fn.writeAsStringSync('int moduleTotal(int a, int b) => a + b;\n');

  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  return root;
}

void main() {
  // The default is the behaviour every existing module already relies on.
  // A block nobody wrote must not start withholding anything.
  test('a module that declares nothing shares its pages and functions', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.exportsPages, isTrue);
    expect(mount.exportsFunctions, isTrue);
    expect(mount.exportedModels, isEmpty);
    expect(mount.routes, isNotEmpty);
    expect(mount.routes, hasLength(mount.declaredRoutes.length));
  });

  test('pages: false is read', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      pages: false
''').path).single;

    expect(mount.exportsPages, isFalse);
    // `routes` is what the parent takes, so it is empty. The pages still
    // exist and stay on `declaredRoutes` for the inspector.
    //
    // This way round on purpose. The other reading -- routes holds everything
    // and each consumer checks the flag -- is the design that produced this
    // gap: the block was there and every consumer shared everything because
    // none of them looked. Naming the shared set `routes` makes every
    // consumer that already reads it correct without being touched, and makes
    // the careless answer the safe one.
    expect(mount.routes, isEmpty);
    expect(mount.declaredRoutes, isNotEmpty);
  });

  test('functions: false is read', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      functions: false
''').path).single;

    expect(mount.exportsFunctions, isFalse);
    expect(mount.exportsPages, isTrue);
  });

  test('the model list is read, in the order it was written', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      models: [Product, Cart, Order]
''').path).single;

    expect(mount.exportedModels, <String>['Product', 'Cart', 'Order']);
  });

  test('an explicit true is the same as saying nothing', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      pages: true
      functions: true
''').path).single;

    expect(mount.exportsPages, isTrue);
    expect(mount.exportsFunctions, isTrue);
  });

  // A value that is neither true nor false is a typo, and a typo that reads
  // as the permissive default is how a module silently shares what it meant
  // to keep. It is refused by name.
  test('a value that is not a boolean is refused, naming the key', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      pages: yes-please
''').path).single;

    expect(
      mount.problems.join(' '),
      allOf(contains('exports.pages'), contains('yes-please')),
    );
  });

  // Read is not honoured, and the gap was that nothing honoured it.
  group('and it is honoured, not only read', () {
    test('a module that shares its functions contributes them', () async {
      final String routes = await backendRoutes(workspace());
      expect(routes, contains('moduleTotal'));
    });

    test('functions: false keeps them out of the parent router', () async {
      final String routes = await backendRoutes(workspace(exports: '''
    exports:
      functions: false
'''));
      expect(routes, isNot(contains('moduleTotal')));
    });

    test('pages: false leaves the parent nothing to route', () {
      final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      pages: false
''').path).single;

      // Every consumer that builds an application reads `routes`.
      expect(mount.routes, isEmpty);
    });
  });

  test('a models entry that is not a list is refused', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(workspace(exports: '''
    exports:
      models: Product
''').path).single;

    expect(mount.problems.join(' '), contains('exports.models'));
  });
}

/// The generated backend routes for [root].
Future<String> backendRoutes(Directory root) async {
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shopfront',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  final File file = File(p.join(
      root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'));
  return file.existsSync() ? file.readAsStringSync() : '';
}
