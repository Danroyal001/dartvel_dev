// An app whose project runs Studio reads the pages Studio deployed.
//
// Studio deploys a page to phones, desktops and TVs as well as the website,
// and an installed app can only see it by asking its backend. The generated
// runtime turns that on for a project whose pubspec turns Studio on, and
// only for one: an app with no Studio behind it would ask on every launch
// for a list that cannot exist.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> runtimeFor(Map<String, Object?> dartvel) async {
  final Directory root = await Directory.systemTemp.createTemp('dv_deployed_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shop',
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
    dv: YamlMap.wrap(dartvel),
  );
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  test('a project that turns Studio on reads deployed pages', () async {
    final String runtime = await runtimeFor(<String, Object?>{
      'admin': <String, Object?>{'enabled': true},
    });

    expect(runtime, contains('DVPageStore.fromBackend = true;'));
  });

  test('a project without Studio never asks', () async {
    expect(await runtimeFor(<String, Object?>{}),
        isNot(contains('DVPageStore.fromBackend = true;')));
    expect(
        await runtimeFor(<String, Object?>{
          'admin': <String, Object?>{'enabled': false},
        }),
        isNot(contains('DVPageStore.fromBackend = true;')));
  });
}
