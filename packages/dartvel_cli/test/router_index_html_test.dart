// Landing on /index.html is a route, not a file, once the application is
// running.
//
// A browser extension opens its page as moz-extension://<uuid>/index.html,
// and anyone who reaches a static host's file directly gets the same path. The
// router treated it as a route nobody had declared and rendered its own 404 --
// which is what a Dartvel extension showed in Firefox, on top of an engine
// that was by then working perfectly.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> routerSource() async {
  final root = await Directory.systemTemp.createTemp('dartvel_index_html_');
  try {
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
        .writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _home(BuildContext context) => const Text('home');
''');
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);

    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'index_html_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 8080,
      devBackendHost: 'http://127.0.0.1:8080',
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
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('the router sends /index.html to the root', () async {
    final router = await routerSource();

    expect(router, contains("if (path == '/index.html') return '/';"));
  });

  test('a nested index.html resolves to its directory', () async {
    // /docs/index.html is /docs, which is where a static host's directory
    // listing and an extension's sub-page both land.
    final router = await routerSource();

    expect(router, contains("path.endsWith('/index.html')"));
  });
}
