// Each page's code in a part of its own, fetched when the page is.
//
// Every page is imported `deferred`, and on the web that was meant to split
// the bundle: main.dart.js carries the shell, and a page's code arrives when
// something calls its loadLibrary(). A built site showed it doing nothing.
// dart2js reported `deferredLibraryParts:{p0:[],p1:[],p2:[0],p3:[]}` -- three
// of four pages with no part at all -- because the generator lowered each
// private page's body into router.g.dart. The router is eager, so everything
// the body built was reachable from main() and landed in main.dart.js; the
// deferred import was left guarding a few constants.
//
// dart2js assigns code to a part by what reaches it, so the fix is to make the
// body reachable only through the deferred import: it goes into a library of
// its own, and the router imports that.
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _project(Map<String, String> files) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_page_split_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  files.forEach((String rel, String source) {
    File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  return root;
}

Future<void> _generate(Directory root) => ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'split_app',
      buildId: 'test-build',
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

String _read(Directory root, String rel) =>
    File(p.join(root.path, rel)).readAsStringSync();

/// A package:split_app/ URI as a path under the project.
String _pathOf(String uri) => uri.replaceFirst('package:split_app/', 'lib/');

const String _docsPage = "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "import '../components/banner.dart';\n"
    "const List<String> rows = <String>['one', 'two'];\n"
    "@DVPage(title: 'Docs')\n"
    'Widget _docsPage(BuildContext context) =>\n'
    "    DVBox.list(<Widget>[const Banner('docs body marker'), DVText(rows.first)]);\n";

const String _banner = "import 'package:flutter/widgets.dart';\n"
    'class Banner extends StatelessWidget {\n'
    '  const Banner(this.label, {super.key});\n'
    '  final String label;\n'
    '  @override\n'
    '  Widget build(BuildContext context) => Text(label);\n'
    '}\n';

/// The library the router imports under [alias], as a path under lib/.
String _deferredLibraryFor(String router, String alias) {
  final RegExpMatch? m =
      RegExp("import '([^']+)' deferred as $alias;").firstMatch(router);
  expect(m, isNotNull, reason: 'the router has no deferred import as $alias');
  return m!.group(1)!;
}

void main() {
  test('a lowered page body is not in the router', () async {
    final Directory root = await _project(<String, String>{
      'lib/pages/docs.dart': _docsPage,
      'lib/components/banner.dart': _banner,
    });
    await _generate(root);

    final String router = _read(root, 'lib/dartvel_client/router.g.dart');
    // The body's own text. In the router it is reachable from main() and
    // lands in main.dart.js whatever the deferred import says.
    expect(router, isNot(contains('docs body marker')));
    // And the page's imports with it: nothing in the router uses them now,
    // and an eager import of a component is how the next body leaks back.
    expect(router, isNot(contains('package:split_app/components/banner.dart')));
  });

  test('the body lives in the library the router imports deferred', () async {
    final Directory root = await _project(<String, String>{
      'lib/pages/docs.dart': _docsPage,
      'lib/components/banner.dart': _banner,
    });
    await _generate(root);

    final String router = _read(root, 'lib/dartvel_client/router.g.dart');
    final String library = _deferredLibraryFor(router, 'p0');
    expect(library, isNot('package:split_app/pages/docs.dart'),
        reason: 'the page file itself is deferred, but its body is not in it');

    final String body = _read(root, _pathOf(library));
    expect(body, contains('docs body marker'));
    // Imported normally in here: this library is only ever reached through
    // the router's deferred import, so nothing it imports is eager, and a
    // const expression cannot name a type through a deferred prefix.
    expect(body, contains("import 'package:split_app/components/banner.dart';"));
    expect(body,
        contains("import 'package:split_app/pages/docs.dart' as p0;"));
    // The page's own public symbol, still reached through its prefix.
    expect(body, contains('p0.rows.first'));

    // The router calls it only once the library is loaded, and the shapes a
    // build reads the route-to-part mapping from are unchanged.
    expect(router, contains('p0.dvPageBody(context)'));
    expect(router, contains('_libraryFuture ??= p0.loadLibrary()'));
    expect(
        router,
        contains("DVRoutePreloaders.register(\n"
            "    '/docs',\n"
            '    DocsPageGeneratedPage.loadLibrary,\n'
            '  );'));
  });

  test('a body that is not lowered keeps the page file deferred', () async {
    // A public page function or a page class is called, not copied: its code
    // is already only reachable through the deferred import.
    final Directory root = await _project(<String, String>{
      'lib/pages/index.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget homePage(BuildContext context) => const DVText('hi');\n",
    });
    await _generate(root);

    final String router = _read(root, 'lib/dartvel_client/router.g.dart');
    expect(_deferredLibraryFor(router, 'p0'),
        'package:split_app/pages/index.dart');
    expect(Directory(p.join(root.path, 'lib', 'dartvel_client', 'pages'))
        .existsSync(), isFalse);
  });

  test('a body library for a page that is gone is removed', () async {
    final Directory root = await _project(<String, String>{
      'lib/pages/docs.dart': _docsPage,
      'lib/components/banner.dart': _banner,
    });
    await _generate(root);
    final String router = _read(root, 'lib/dartvel_client/router.g.dart');
    final File stale =
        File(p.join(root.path, _pathOf(_deferredLibraryFor(router, 'p0'))));
    expect(stale.existsSync(), isTrue);

    File(p.join(root.path, 'lib', 'pages', 'docs.dart')).deleteSync();
    File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync(
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
        "@DVPage(title: 'Home')\n"
        "Widget _homePage(BuildContext context) => const DVText('hi');\n");
    await _generate(root);

    // Left behind, it still imports a page that no longer exists, and the
    // application stops analysing over a file nobody wrote.
    expect(stale.existsSync(), isFalse);
  });

  group('the parts are precached', () {
    // A page's code used to be in main.dart.js, which every visit fetches, so
    // the worker cached it on the way past and every page worked offline.
    // Once it is in a part of its own, a page nobody has opened yet has never
    // been fetched, and opening it offline is a load error.
    test('every deferred part in the build, and nothing else', () async {
      final Directory web =
          await Directory.systemTemp.createTemp('dartvel_parts_');
      addTearDown(() => web.deleteSync(recursive: true));
      for (final String name in <String>[
        'main.dart.js',
        'main.dart.js_2.part.js',
        'main.dart.js_1.part.js',
        'main.dart.js_1.part.js.map',
        'flutter_bootstrap.js',
      ]) {
        File(p.join(web.path, name)).writeAsStringSync('');
      }

      expect(dvDeferredPartFiles(web), <String>[
        '/main.dart.js_1.part.js',
        '/main.dart.js_2.part.js',
      ]);
    });

    test('a build without deferred code has none', () async {
      final Directory web =
          await Directory.systemTemp.createTemp('dartvel_parts_');
      addTearDown(() => web.deleteSync(recursive: true));
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync('');
      expect(dvDeferredPartFiles(web), isEmpty);
    });
  });
}
