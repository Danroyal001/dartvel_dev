// `@DVPage(findable: false)` reaches the page shell.
//
// Every page is findable by the browser's find unless it says otherwise, and
// nothing an application adds makes it so: the shell carries it, as it
// carries selection and keyboard scrolling. The one thing a page can say is
// no -- for content that should never be copied into the document -- and a
// `findable: false` the generator dropped would be a page that says no and is
// mirrored anyway, which is the silent kind of wrong.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> routerFor(String annotation) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_find_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

$annotation
Widget _homePage(BuildContext context) => const DVText('hi');
''');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shopfront\n');

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

  // Wherever the page's spec is written, it is written into the client.
  final StringBuffer client = StringBuffer();
  for (final FileSystemEntity file
      in Directory(p.join(root.path, 'lib')).listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.g.dart')) {
      client.writeln(file.readAsStringSync());
    }
  }
  return client.toString();
}

void main() {
  test('a page that opts out of find says so in its shell', () async {
    final String client =
        await routerFor("@DVPage(title: 'Vault', findable: false)");

    expect(client, contains('DVPageScaffoldSpec('));
    expect(client, contains('findable: false'));
  });

  test('a page that says nothing is findable, with nothing written', () async {
    // The default is the shell's own; writing `findable: true` into every
    // page would be noise that hides the pages that did opt out.
    final String client = await routerFor("@DVPage(title: 'Home')");

    expect(client, contains('DVPageScaffoldSpec('));
    expect(client, isNot(contains('findable')));
  });
}
