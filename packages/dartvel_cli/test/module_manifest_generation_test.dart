// The manifest a module publishes about itself.
//
// A federated module is deployed on its own and mounted into somebody else's
// application, and the manifest is what that application reads before it
// agrees to mount it. It is generated from the module's own project, because
// a manifest written by hand goes stale the first time a page is added and
// nobody notices until a route 404s in production.
//
// The mistake worth guarding is the mount point. The same module answers at
// /products standalone and /store/products mounted, and a manifest that
// baked in one parent's mount would be wrong for every other parent -- and
// wrong in a way that reads as correct, because it works in the application
// it was generated against.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/graph/module_manifest.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

Directory moduleProject({
  String base = '/',
  String extra = '',
  Map<String, String> pages = const <String, String>{
    'index.page.dart': _page,
    'products/[id].page.dart': _page,
  },
}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_manifest_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
flutter:
  assets:
    - assets/logo.png
dartvel:
  pagesDir: lib/pages
  module:
    id: store
    name: Store
    version: 1.2.0
    routes:
      base: $base
$extra
''');
  pages.forEach((String rel, String source) {
    final File file = File(p.join(root.path, 'lib', 'pages', rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  });
  return root;
}

void main() {
  test('the manifest names the module and its version', () {
    final DVModuleManifest manifest = dvModuleManifestFor(moduleProject().path);

    expect(manifest.id, 'store');
    expect(manifest.version, '1.2.0');
  });

  test('the routes are the module\'s own, not any parent\'s mount', () {
    // This is the whole point. A manifest that carried /store/products would
    // be right for one application and quietly wrong for every other one.
    final DVModuleManifest manifest = dvModuleManifestFor(moduleProject().path);

    expect(manifest.routes, containsAll(<String>['/', '/products/:id']));
    expect(manifest.routes.where((String r) => r.startsWith('/store')), isEmpty);
  });

  test('a module with its own route base keeps that base', () {
    // The base is the module's, and it travels: /products standalone is
    // /store/products mounted, and the manifest describes the standalone.
    final DVModuleManifest manifest =
        dvModuleManifestFor(moduleProject(base: '/products').path);

    expect(manifest.routes, contains('/products'));
    expect(manifest.routes, contains('/products/products/:id'));
  });

  test('the assets it declares are in the manifest', () {
    final DVModuleManifest manifest = dvModuleManifestFor(moduleProject().path);

    expect(manifest.assets.keys, contains('assets/logo.png'));
    expect(manifest.assets['assets/logo.png'], 'packages/store/assets/logo.png');
  });

  test('the modes it declares are in the manifest, and the rest inherit', () {
    final DVModuleManifest manifest = dvModuleManifestFor(moduleProject(extra: '''
    auth: independent
    theme: isolated
    data: database-isolated
    capabilities: [camera]
    location: https://store.example.com
    requiresParent: ">=2.0.0"
''').path);

    expect(manifest.auth, 'independent');
    expect(manifest.theme, 'isolated');
    expect(manifest.data, 'database-isolated');
    expect(manifest.shell, 'inherit', reason: 'undeclared means inherit');
    expect(manifest.capabilities, contains('camera'));
    expect(manifest.location, 'https://store.example.com');
    expect(manifest.requiresParent, '>=2.0.0');
  });

  test('a generated manifest verifies against the key that signed it', () {
    // End to end: what the generator writes is what a parent will check, and
    // the two agreeing is the only thing that makes either useful.
    final DVModuleManifest manifest = dvModuleManifestFor(moduleProject().path);
    final key = List<int>.generate(32, (int i) => i + 1);
    final String document = dvSignModuleManifest(
      manifest,
      privateKey: Uint8List.fromList(key),
      keyId: 'publisher',
    );

    final DVModuleTrust trust = dvVerifyModuleManifest(
      document,
      trustedKeys: <String, String>{
        'publisher': dvModuleSigningPublicKey(Uint8List.fromList(key)),
      },
      expectedId: 'store',
    );

    expect(trust.accepted, isTrue, reason: trust.reason);
    expect(trust.manifest!.routes, containsAll(<String>['/', '/products/:id']));
  });

  group('writing the document', () {
    test('an unsigned manifest is written, and says it is unsigned', () {
      // Useful for reading and for embedded mounting, and it must not be
      // mistakable for a manifest a parent may trust.
      final Directory root = moduleProject();

      final DVModuleManifestWrite result =
          dvWriteModuleManifest(root.path, out: p.join(root.path, 'manifest.json'));

      expect(File(result.path).existsSync(), isTrue);
      expect(result.signed, isFalse);
      final Map<String, Object?> doc =
          jsonDecode(File(result.path).readAsStringSync()) as Map<String, Object?>;
      expect(doc['signature'], isNull);
      expect((doc['manifest']! as Map<String, Object?>)['id'], 'store');
    });

    test('a signed manifest is one a parent will accept', () {
      final Directory root = moduleProject();
      final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));

      final DVModuleManifestWrite result = dvWriteModuleManifest(
        root.path,
        out: p.join(root.path, 'manifest.json'),
        privateKey: key,
        keyId: 'publisher',
      );

      expect(result.signed, isTrue);
      final DVModuleTrust trust = dvVerifyModuleManifest(
        File(result.path).readAsStringSync(),
        trustedKeys: <String, String>{'publisher': dvModuleSigningPublicKey(key)},
        expectedId: 'store',
      );
      expect(trust.accepted, isTrue, reason: trust.reason);
    });
  });
}
