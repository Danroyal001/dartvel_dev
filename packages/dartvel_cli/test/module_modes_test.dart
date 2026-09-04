// A module's shell, auth, theme and data modes.
//
// Four keys the specification defines per module and nothing read, so
// `auth: independent` and `theme: isolated` were comments. Reading them is
// half the job; the half that matters is refusing the combinations that
// cannot work, because those read perfectly and fail at run time in another
// deployment.
//
// A federated module runs in its own deployment. It cannot inherit the
// parent's DV.Auth -- there is no shared process to inherit it from, which is
// exactly why the specification gives federated auth its own mode -- and it
// cannot share the parent's database. A declaration that says it does is not
// a preference the build can honour; it is a mistake that shows up as a
// module that silently has no session.
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

Directory workspace(String modes, {String deployment = 'embedded'}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_modes_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: $deployment
$modes
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

DVModuleMount mountOf(String modes, {String deployment = 'embedded'}) =>
    dvDiscoverModuleMounts(workspace(modes, deployment: deployment).path).single;

void main() {
  group('what a module declares', () {
    test('an undeclared module inherits everything and shares data', () {
      final DVModuleMount mount = mountOf('');

      expect(mount.shell, 'inherit');
      expect(mount.auth, 'inherit');
      expect(mount.theme, 'inherit');
      expect(mount.data, 'shared');
      expect(mount.problems, isEmpty);
    });

    test('the declared modes are read', () {
      final DVModuleMount mount = mountOf('''
      shell: none
      auth: public
      theme: override
      data: schema-isolated
''');

      expect(mount.shell, 'none');
      expect(mount.auth, 'public');
      expect(mount.theme, 'override');
      expect(mount.data, 'schema-isolated');
      expect(mount.problems, isEmpty);
    });

    test('a mode that is not one of the modes is a problem, not a silent default', () {
      final DVModuleMount mount = mountOf('      auth: whatever\n');

      expect(mount.problems, isNotEmpty);
      expect(mount.problems.join(' '), contains('whatever'));
      expect(mount.auth, 'inherit', reason: 'and the default is what is used');
    });
  });

  group('combinations that cannot work', () {
    test('a federated module cannot inherit the parent\'s auth', () {
      // There is no shared process to inherit a session from, which is why
      // the specification gives federated auth a mode of its own. Left
      // unchecked, the module would run with no session and look like a
      // login bug.
      final DVModuleMount mount =
          mountOf('      auth: inherit\n', deployment: 'federated');

      expect(mount.problems.join(' '), contains('auth'));
      expect(mount.problems.join(' '), contains('federated'));
    });

    test('a federated module cannot share the parent\'s database', () {
      final DVModuleMount mount =
          mountOf('      data: shared\n', deployment: 'federated');

      expect(mount.problems.join(' '), contains('data'));
    });

    test('a federated module defaults to the modes its deployment can honour', () {
      // Not to inherit-and-refuse: defaulting to something impossible and
      // then complaining about it would make every federated module report
      // two problems nobody wrote.
      final DVModuleMount mount = mountOf('', deployment: 'federated');

      expect(mount.auth, 'federated');
      expect(mount.data, 'remote');
      expect(mount.theme, 'isolated');
      expect(mount.problems.where((String p) => p.contains('auth')), isEmpty);
    });

    test('a federated module may be independent, federated or public', () {
      for (final String auth in <String>['independent', 'federated', 'public']) {
        final DVModuleMount mount =
            mountOf('      auth: $auth\n      data: remote\n', deployment: 'federated');
        expect(mount.problems.where((String p) => p.contains('auth')), isEmpty,
            reason: 'auth: $auth was refused');
      }
    });

    test('an embedded module may inherit everything', () {
      final DVModuleMount mount = mountOf('''
      auth: inherit
      data: shared
      theme: inherit
''');

      expect(mount.problems, isEmpty);
    });

    test('a backend-only module has no shell or theme to speak of', () {
      // It contributes models and functions and no pages, so a theme mode is
      // a declaration about something that does not exist.
      final DVModuleMount mount =
          mountOf('      theme: override\n', deployment: 'backend-only');

      expect(mount.problems.join(' '), contains('theme'));
    });
  });

  group('a backend deployed on its own', () {
    test('the address is read', () {
      final DVModuleMount mount = mountOf(
        '      backend: https://store-api.example.com\n',
        deployment: 'split-backend',
      );

      expect(mount.backend, 'https://store-api.example.com');
      expect(mount.problems, isEmpty);
    });

    test('split-backend with no address is refused', () {
      // The pages compile in exactly as an embedded module's do, so nothing
      // looks wrong: every call the module makes goes to the parent's API,
      // which does not serve those functions, and the answer is a 404 from
      // an application that was built and deployed and looks right.
      final DVModuleMount mount = mountOf('', deployment: 'split-backend');

      expect(mount.problems, isNotEmpty);
      expect(mount.problems.join(' '), contains('backend'));
    });

    test('an embedded module needs no address', () {
      expect(mountOf('').problems, isEmpty);
      expect(mountOf('').backend, isNull);
    });
  });

  group('the module\'s own client', () {
    Future<String> generateModule({String extra = ''}) async {
      final Directory root = Directory.systemTemp.createTempSync('dartvel_module_client_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(_page);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: store\n');
      final YamlMap dv = loadYaml(extra.isEmpty ? '{}' : extra) as YamlMap;
      await ClientGenerator.generate(
        root: root.path,
        pagesDir: 'lib/pages',
        pkgName: 'store',
        buildId: 'b',
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
        dv: dv,
      );
      return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
          .readAsStringSync();
    }

    test('a module asks where its own backend is before using the application\'s', () async {
      // Compiled into a parent, this code runs inside an application whose
      // base URL is the parent's. Its functions are not there.
      final String runtime = await generateModule(extra: 'module: { id: store }');

      expect(runtime, contains("DV.Modules.maybeGet('store')"));
      expect(runtime, contains('apiBase'));
    });

    test('an application that is not a module asks nothing', () async {
      final String runtime = await generateModule();

      expect(runtime, isNot(contains('maybeGet')));
    });
  });

  group('what auth does at run time', () {
    // The four modes were read and carried into the registry, and that was
    // all: a module mounted `auth: public` sat behind the parent's guard
    // exactly as one mounted `auth: inherit` did, so the mode was a comment
    // with a typed accessor in front of it.
    //
    // Inherit is the parent's guard on the module's routes. Public is no
    // guard, which is the whole point of the word: a documentation module
    // mounted into an application everybody has to sign into is a
    // documentation module nobody can read.
    Future<String> routerFor(String modes) async {
      final Directory root = workspace(modes);
      // A guard over the parent's own pages. The module's routes are not
      // under this directory, so nothing gave them one.
      File(p.join(root.path, 'lib', 'pages', '_guard.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

Future<String?> guard(BuildContext context, Object state) async => null;
''');
      File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_page);
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);

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
      return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
          .readAsStringSync();
    }

    /// The GoRoute block for the module's mounted page.
    String moduleRoute(String router) {
      final int at = router.indexOf("path: '/store'");
      expect(at, greaterThan(-1), reason: 'the module route is not there');
      return router.substring(router.lastIndexOf('GoRoute(', at), at + 400);
    }

    test('a module that inherits sits behind the parent\'s guard', () async {
      expect(moduleRoute(await routerFor('      auth: inherit')),
          contains('guard(context, state)'));
    });

    test('a public module does not', () async {
      expect(moduleRoute(await routerFor('      auth: public')),
          isNot(contains('guard(context, state)')));
    });

    test('the default is to inherit, which is what embedded means', () async {
      expect(moduleRoute(await routerFor('')),
          contains('guard(context, state)'));
    });
  });
}
