// A web-server build calls the backend it was served by.
//
// The binary serves the web app and its API on one origin. The generated
// runtime sent every call of a release web build to dartvel.prodBackendHost
// instead -- https://api.example.com in the example -- so signing in through
// the application's own /login page on the binary posted to a host that does
// not exist, and so did every generated backend call.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> runtimeSource() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_same_origin_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage(title: 'Home')
Widget _home(BuildContext context) => const Text('home');
''');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'same_origin_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 8080,
    devBackendHost: 'http://127.0.0.1:8080',
    prodBackendHost: 'https://api.example.com',
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
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  test('a release web build served by its own server uses the page origin',
      () async {
    final String source = await runtimeSource();
    final int start = source.indexOf('static String get baseUrl');
    final String baseUrl = source.substring(start, source.indexOf('\n  }\n', start));

    expect(baseUrl, contains("bool.fromEnvironment('DARTVEL_WEB_SERVER')"));
    expect(baseUrl, contains('Uri.base.origin'));
    // Before the production host is read, or it never applies.
    expect(baseUrl.indexOf('Uri.base.origin'),
        lessThan(baseUrl.indexOf('dvProdBackendHost')));
  });
}
