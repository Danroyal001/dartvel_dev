// dartvel.startRoutes: the page a target opens on.
//
// A desktop desk and its website are one project: the site opens on its
// home page and the desktop app on the editor. The browser's address decides
// where a web page opens, so only installed targets read the table.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String page = '''
import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Page')
Widget _page(BuildContext context) => const SizedBox();
''';

Future<String> _generate(Map<String, Object?> dartvel) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_start_routes_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  for (final String name in <String>['index.dart', 'editor.dart']) {
    File(p.join(root.path, 'lib', 'pages', name))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(page.replaceFirst('_page', '_${name.split('.').first}Page'));
  }
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'desk_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Desk',
    seoTitle: 'Desk',
    seoDesc: 'Desk',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  test('each target opens on the page named for it', () async {
    final String client = await _generate(<String, Object?>{
      'startRoutes': <String, Object?>{'linux': '/editor', 'windows': '/editor'},
    });
    expect(client, contains("'linux': '/editor'"));
    expect(client, contains("'windows': '/editor'"));
    expect(client, contains('initialLocation: dvStartRoute(_dartvelStartRoutes)'));
  });

  test('without a table every target opens on /', () async {
    final String client = await _generate(const <String, Object?>{});
    expect(client, contains('const Map<String, String> _dartvelStartRoutes = <String, String>{};'));
  });

  test('a route no page has is refused, naming it', () async {
    await expectLater(
      _generate(<String, Object?>{
        'startRoutes': <String, Object?>{'linux': '/desk'},
      }),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('startRoutes'), contains('/desk')))),
    );
  });

  test('a target that is not one is refused', () async {
    await expectLater(
      _generate(<String, Object?>{
        'startRoutes': <String, Object?>{'linuks': '/editor'},
      }),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          contains('linuks'))),
    );
  });
}
