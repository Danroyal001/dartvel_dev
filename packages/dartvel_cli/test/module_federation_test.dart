// Mounting a module that somebody else deploys.
//
// An embedded module is compiled in from source, so the parent can see what
// it is mounting. A federated one is built and deployed elsewhere: the source
// beside it is not what will answer, and the manifest is the only description
// of the thing that will. The specification is explicit that the parent
// verifies it before integration.
//
// So the failures here are the ones where a build succeeds and the wrong
// thing gets mounted: source compiled in for a module that is deployed
// somewhere else -- which works right up until the two versions differ -- and
// a manifest taken on trust.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

final Uint8List _key = Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));
final Uint8List _otherKey =
    Uint8List.fromList(List<int>.generate(32, (int i) => i + 40));

/// A parent that mounts `store` as federated, with whatever manifest and
/// trust the test wants.
Directory workspace({
  String? manifestDocument,
  String trust = 'publisher: KEY',
  bool declareManifest = true,
}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_federated_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: federated
${declareManifest ? '      manifest: store-manifest.json' : ''}
      trust:
        ${trust.replaceAll('KEY', dvModuleSigningPublicKey(_key))}
''');

  final Directory module = Directory(p.join(root.path, 'modules', 'store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
    version: 1.0.0
    location: https://store.example.com
''');
  File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);

  if (manifestDocument != null) {
    File(p.join(root.path, 'store-manifest.json'))
        .writeAsStringSync(manifestDocument);
  }
  return root;
}

String signedManifest({
  String id = 'store',
  String version = '2.0.0',
  List<String> routes = const <String>['/', '/products/:id'],
  String? location = 'https://store.example.com',
  Uint8List? key,
}) =>
    dvSignModuleManifest(
      DVModuleManifest(
        id: id,
        version: version,
        routes: routes,
        location: location,
      ),
      privateKey: key ?? _key,
      keyId: 'publisher',
    );

void main() {
  test('a verified module is mounted, with the manifest\'s routes', () {
    // The manifest's, not the source's. The deployed module is at 2.0.0 and
    // serves /products/:id; the source beside it is 1.0.0 with one page, and
    // compiling that in would mount a version nobody deployed.
    final DVModuleMount mount =
        dvDiscoverModuleMounts(workspace(manifestDocument: signedManifest()).path)
            .single;

    expect(mount.problems, isEmpty);
    expect(mount.version, '2.0.0');
    expect(mount.routes.map((DVModuleRoute r) => r.mounted),
        containsAll(<String>['/store', '/store/products/:id']));
    expect(mount.location, 'https://store.example.com');
  });

  test('the parent knows where each federated route answers', () {
    // The parent generates no page for these, so they are not in the router
    // source the route index and sitemap are built from. The specification
    // still asks for them to appear in both, which they cannot do unless the
    // build can say, for each mounted path, the address that answers it.
    final Map<String, String> answered =
        dvFederatedRoutes(workspace(manifestDocument: signedManifest()).path);

    expect(answered, <String, String>{
      '/store': 'https://store.example.com',
      '/store/products/:id': 'https://store.example.com/products/:id',
    });
  });

  test('an embedded module contributes no federated route', () {
    // It is compiled in, so the parent answers those paths itself. Listing
    // them as somewhere else to go would send readers off a site that has
    // the page.
    final Directory root = workspace(manifestDocument: signedManifest());
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: embedded
''');

    expect(dvFederatedRoutes(root.path), isEmpty);
  });

  test('its pages are not compiled into the parent', () {
    // The whole difference between federated and embedded. An import of the
    // module's source would build a second copy of a module that is already
    // deployed, and the two would drift.
    final DVModuleMount mount =
        dvDiscoverModuleMounts(workspace(manifestDocument: signedManifest()).path)
            .single;

    expect(mount.compiledIntoParent, isFalse);
    for (final DVModuleRoute route in mount.routes) {
      expect(route.import, isEmpty,
          reason: '${route.mounted} would be compiled in');
    }
  });

  test('an embedded module is still compiled in', () {
    final Directory root = workspace(manifestDocument: signedManifest());
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: embedded
''');

    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.compiledIntoParent, isTrue);
    expect(mount.routes.single.import, isNotEmpty);
  });

  test('a federated module with no manifest is refused', () {
    // There is nothing to verify, so there is nothing to trust; mounting the
    // source instead would quietly turn it into an embedded module.
    final DVModuleMount mount =
        dvDiscoverModuleMounts(workspace(declareManifest: false).path).single;

    expect(mount.problems, isNotEmpty);
    expect(mount.problems.join(' '), contains('manifest'));
    expect(mount.routes, isEmpty);
  });

  test('a manifest that is not where it says it is, is refused', () {
    final DVModuleMount mount =
        dvDiscoverModuleMounts(workspace().path).single;

    expect(mount.problems.join(' '), contains('store-manifest.json'));
    expect(mount.routes, isEmpty);
  });

  test('a manifest signed by an untrusted key is refused, with the reason', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(
      workspace(manifestDocument: signedManifest(key: _otherKey)).path,
    ).single;

    expect(mount.problems.join(' '), contains('signature'));
    expect(mount.routes, isEmpty);
  });

  test('a manifest for another module is refused', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(
      workspace(manifestDocument: signedManifest(id: 'documentation')).path,
    ).single;

    expect(mount.problems.join(' '), contains('documentation'));
    expect(mount.routes, isEmpty);
  });

  test('a parent that trusts no key mounts nothing federated', () {
    final Directory root = workspace(manifestDocument: signedManifest());
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: federated
      manifest: store-manifest.json
''');

    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.problems, isNotEmpty);
    expect(mount.routes, isEmpty);
  });

  test('a verified module with nowhere to answer from is refused', () {
    // Verified, trusted, and there is no address to send anybody to: the
    // routes would be in the sitemap and lead nowhere.
    final DVModuleMount mount = dvDiscoverModuleMounts(
      workspace(manifestDocument: signedManifest(location: null)).path,
    ).single;

    expect(mount.problems.join(' '), contains('location'));
  });

  group('what the parent generates for it', () {
    Future<String> generate(Directory root) async {
      Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
          .writeAsStringSync(_page);
      Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
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

    test('no import of a module that is deployed somewhere else', () async {
      // An import would compile a second copy of a running application into
      // this one, and the day the two versions differ nobody would think to
      // look at the parent's build.
      final String router =
          await generate(workspace(manifestDocument: signedManifest()));

      expect(router, isNot(contains("package:store/")));
    });

    test('its routes are in the manifest, and say where they answer', () async {
      // Listed without a location, a sitemap would send a crawler to a path
      // this application answers with its own not-found page.
      final String router =
          await generate(workspace(manifestDocument: signedManifest()));

      expect(router, contains("path: '/store/products/:id'"));
      expect(router, contains("location: 'https://store.example.com'"));
    });

    test('and it builds no page for them', () async {
      final String router =
          await generate(workspace(manifestDocument: signedManifest()));

      expect(router, isNot(contains('NoTransitionPage<void>(\n        child: const store')));
    });
  });
}
