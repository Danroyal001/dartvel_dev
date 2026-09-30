// What was made in Studio and committed ships with the next build.
//
// The project's studio/ files -- pages, components, shortcuts -- are
// bundled into the client the generator writes, as JSON strings a server can
// seed itself from and an application can fall back on with no server at
// all. Nothing else a release needs to carry them.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _project(Map<String, String> studio) async {
  final Directory root = await Directory.systemTemp.createTemp('dv_studio_docs_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _home(BuildContext context) => const Text('home');
''');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  studio.forEach((String path, String text) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shop',
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
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );
  return root;
}

String _read(Directory root, String name) =>
    File(p.join(root.path, 'lib', 'dartvel_client', name)).readAsStringSync();

/// The strings in the generated list, read back the way Dart reads them.
List<String> _bundled(String source) => <String>[
      for (final RegExpMatch m
          in RegExp(r'^  "((?:[^"\\]|\\.)*)",$', multiLine: true).allMatches(source))
        jsonDecode('"${m.group(1)!.replaceAll(r'\$', r'$')}"') as String,
    ];

void main() {
  test('the studio/ files are bundled into the client, each as it is',
      () async {
    final String landing = jsonEncode(<String, Object?>{
      'route': '/landing',
      'title': 'Costs \$5 "today"',
    });
    final String card = jsonEncode(<String, Object?>{
      'route': '/_dartvel/components/Card',
      'title': 'Card',
    });
    final Directory root = await _project(<String, String>{
      'studio/pages/landing.json': landing,
      'studio/components/Card.json': card,
      'studio/README.md': 'not a document',
    });
    final String source = _read(root, 'studio_documents.g.dart');
    expect(source, contains('const List<String> dartvelStudioDocuments'));
    // A dollar sign is not interpolated, and a quote does not end the string.
    expect(_bundled(source), unorderedEquals(<String>[landing, card]));
  });

  test('a project with no studio/ files bundles none', () async {
    final Directory root = await _project(const <String, String>{});
    expect(_read(root, 'studio_documents.g.dart'),
        contains('const List<String> dartvelStudioDocuments = <String>[];'));
  });

  test('the application falls back on them, where nothing else has the '
      'route', () async {
    final Directory root = await _project(const <String, String>{});
    expect(_read(root, 'router.g.dart'),
        contains('DVPageStore.bundled = dartvelStudioDocuments;'));
  });
}
