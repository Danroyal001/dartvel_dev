// A block-bodied page, generated end to end.
//
// The unit tests over dvFunctionBodyAfter prove the scanner reads a body. This
// proves the generator carries one across into the widget that runs it, which
// is the part that was refused outright and the part every page in every
// Dartvel project has been shaped around.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> generateRouterFor(String pageSource) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_block_body_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
      .writeAsStringSync(pageSource);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'block_app',
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

  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

const String _imports =
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n";

void main() {
  test('a block body reaches the generated widget', () async {
    final String router = await generateRouterFor('$_imports'
        "@DVPage(title: 'Home')\n"
        'Widget _homePage(BuildContext context) {\n'
        '  final int count = 2;\n'
        "  return DVText('count: ' + count.toString());\n"
        '}\n');

    // The statements, not a call back into the source file: the page function
    // is private, so there is nothing public to call.
    expect(router, contains('final int count = 2;'));
    expect(router, contains('count.toString()'));
  });

  test('a loop and a conditional survive', () async {
    // The things an expression body cannot express, which is the whole reason
    // this restriction was worth removing.
    final String router = await generateRouterFor('$_imports'
        "@DVPage(title: 'Home')\n"
        'Widget _homePage(BuildContext context) {\n'
        '  final List<Widget> children = <Widget>[];\n'
        '  for (int i = 0; i < 3; i++) {\n'
        '    children.add(DVText(i.toString()));\n'
        '  }\n'
        '  if (children.isEmpty) {\n'
        "    return const DVText('none');\n"
        '  }\n'
        '  return DVBox.list(children);\n'
        '}\n');

    expect(router, contains('for (int i = 0; i < 3; i++)'));
    expect(router, contains('if (children.isEmpty)'));
    expect(router, contains('return DVBox.list(children);'));
  });

  test('a map literal does not truncate the body', () async {
    // The brace in a map literal is the one that breaks a scanner counting
    // braces naively, and it would cut the body off mid-statement.
    final String router = await generateRouterFor('$_imports'
        "@DVPage(title: 'Home')\n"
        'Widget _homePage(BuildContext context) {\n'
        "  const Map<String, int> counts = <String, int>{'a': 1, 'b': 2};\n"
        '  return DVText(counts.length.toString());\n'
        '}\n');

    expect(router, contains("<String, int>{'a': 1, 'b': 2}"));
    expect(router, contains('counts.length'));
  });

  test('an expression body still works', () async {
    // The shape every existing page uses. Lowering blocks must not change it.
    final String router = await generateRouterFor("$_imports@DVPage(title: 'Home')\nWidget _homePage(BuildContext context) => const DVText('hello');\n");

    expect(router, contains("return const DVText('hello');"));
  });
}
