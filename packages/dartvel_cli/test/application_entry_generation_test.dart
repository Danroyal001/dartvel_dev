// A page's declared middleware reaches the router it was declared for.
//
// NEW_SPEC.md opens the Middleware section with the page form:
//
//     @DVUseMiddleware([DVMiddlewares.auth, ...])
//     @DVPage()
//     Widget _checkoutPage(BuildContext context) => Checkout.Page();
//
// and the router generator had never heard of the annotation. The only
// reader anywhere was the backend generator's spelling check, which walks
// every file under lib/ and so did validate the names on a page -- against
// the sets written for an HTTP chain. So a page declaring auth got a green
// build, a whitelisted key, and a route anybody could open.
//
// These assert on the generated router rather than on the parser. A correct
// parser with nothing calling it is the mistake this repository has already
// made twice, most recently with @DVPage(policy:).
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'generated_router.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'middleware_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Middleware App',
    seoTitle: 'Middleware App',
    seoDesc: 'Middleware App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

Future<Directory> _project() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_page_middleware_',
  );
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  return root;
}

void _page(Directory root, String name, String source) {
  File(p.join(root.path, 'lib', 'pages', name)).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$source
''');
}

void main() {
  test('pure application generates its root without an app argument', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    await _routerFor(root);
    final entry = File(
      p.join(root.path, 'lib/dartvel_client/application.g.dart'),
    );
    expect(entry.existsSync(), isTrue);
    final output = entry.readAsStringSync();
    expect(output, contains('MaterialApp.router('));
    expect(output, contains('createDartvelRouter(arguments: args)'));
    expect(output, contains('run([List<String> args'));
    expect(output, isNot(contains('run(Widget')));
    expect(
      File(p.join(root.path, 'lib/dartvel_client/dartvel_client.dart'))
          .readAsStringSync(),
      contains("export 'application.g.dart'"),
    );
  });
  test(
    'boot hooks and optional host root are lowered in stable order',
    () async {
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
      File(p.join(root.path, 'lib/boot.dart')).writeAsStringSync('''
import 'dartvel_client/dartvel_client.dart';
@DVBoot()
void _first(DVBoot boot) { DV.log('first'); }
@DVBoot(entries: {DVEntryKind.app})
Future<void> _second(DVBoot boot) async => DV.log('second');
@DVAppRoot()
Widget _root(BuildContext context, DVAppParts parts) => MaterialApp.router(routerConfig: parts.router);
''');
      await _routerFor(root);
      final output = File(
        p.join(root.path, 'lib/dartvel_client/application.g.dart'),
      ).readAsStringSync();
      expect(output, contains("DV.log('first')"));
      expect(output, contains("DV.log('second')"));
      expect(
        output.indexOf("DV.log('first')"),
        lessThan(output.indexOf("DV.log('second')")),
      );
      expect(output, contains('routerConfig: parts.router'));
    },
  );
  test('a host root that drops the router is refused', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'lib/boot.dart')).writeAsStringSync(
      '@DVAppRoot() Widget _root(BuildContext context, DVAppParts parts) => MaterialApp();',
    );
    await expectLater(
      _routerFor(root),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('DV-RUN-006'),
        ),
      ),
    );
  });
}
