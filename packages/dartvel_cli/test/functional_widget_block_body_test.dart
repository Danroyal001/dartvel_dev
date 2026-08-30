// A block-bodied @DVFunctionalWidget, generated end to end.
//
// The scanner that reads a block body already exists and @DVPage uses it. This
// covers the second of the three annotations that still refuse one, and the
// refusal is the reason every shared widget in a Dartvel project is written as
// a one-line wrapper around a public helper.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> generateWidgetsFor(String widgetSource) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_fw_block_');
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
  File(p.join(root.path, 'lib', 'widgets.dart')).writeAsStringSync(widgetSource);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'fw_app',
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

  return File(p.join(root.path, 'lib', 'dartvel_client', 'widgets.g.dart'))
      .readAsStringSync();
}

const String _imports =
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n";

void main() {
  test('a block body reaches the generated widget', () async {
    final String widgets = await generateWidgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _badge(String label) {\n'
        '  final String upper = label.toUpperCase();\n'
        '  return DVText(upper);\n'
        '}\n');

    // The statements themselves. The input is private, so there is nothing
    // public left to call back into.
    expect(widgets, contains('final String upper = label.toUpperCase();'));
    expect(widgets, contains('return DVText(upper);'));
  });

  test('a loop and a conditional survive', () async {
    final String widgets = await generateWidgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _stack(int count) {\n'
        '  final List<Widget> children = <Widget>[];\n'
        '  for (int i = 0; i < count; i++) {\n'
        '    children.add(DVText(i.toString()));\n'
        '  }\n'
        '  if (children.isEmpty) {\n'
        "    return const DVText('none');\n"
        '  }\n'
        '  return DVBox.list(children);\n'
        '}\n');

    expect(widgets, contains('for (int i = 0; i < count; i++)'));
    expect(widgets, contains('if (children.isEmpty)'));
    expect(widgets, contains('return DVBox.list(children);'));
  });

  test('a brace inside a string does not truncate the body', () async {
    // A scanner counting braces naively cuts the body off here, and the
    // generated file then fails to compile somewhere unrelated.
    final String widgets = await generateWidgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _labelled(String name) {\n'
        "  const String brace = '{';\n"
        '  return DVText(brace + name);\n'
        '}\n');

    expect(widgets, contains("const String brace = '{';"));
    expect(widgets, contains('return DVText(brace + name);'));
  });

  test('an expression body still works', () async {
    // The shape every existing widget uses; lowering must not disturb it.
    final String widgets = await generateWidgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        "Widget _badge(String label) => DVText(label);\n");

    expect(widgets, contains('return DVText(label);'));
  });

  test('a symbol inside a string interpolation stays interpolated', () async {
    // Qualifying `$suffix` to `$w0.suffix` changes what Dart parses: in the
    // simple `$identifier` form the name ends at `w0`, so `.suffix` becomes
    // literal text and the analyzer rejects the prefix. It has to be braced.
    final String widgets = await generateWidgetsFor('$_imports'
        "const String suffix = '!';\n"
        '@DVFunctionalWidget()\n'
        'Widget _badge(String label) {\n'
        "  return DVText('\$label\$suffix');\n"
        '}\n');

    expect(widgets, contains(r'${w0.suffix}'));
    expect(widgets, isNot(contains(r'$w0.suffix')));
  });

  test('a symbol inside a plain string literal is left alone', () async {
    // The qualifier rewrites text, so a name that merely appears inside a
    // string gets rewritten too -- and the result still compiles, which is why
    // this is worth a test: the widget would just silently render the wrong
    // words.
    final String widgets = await generateWidgetsFor('$_imports'
        "const String suffix = '!';\n"
        '@DVFunctionalWidget()\n'
        'Widget _badge(String label) {\n'
        "  return DVText('suffix' + label + suffix);\n"
        '}\n');

    expect(widgets, contains("'suffix'"));
    expect(widgets, contains('w0.suffix'));
    expect(widgets, isNot(contains("'w0.suffix'")));
  });
}
