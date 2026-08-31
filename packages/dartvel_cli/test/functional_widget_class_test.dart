// @DVFunctionalWidget generates a widget, not a function.
//
// It used to emit `Widget FeatureCard(String title, String body) { ... }`. A
// function is not a widget: it has no element, so it cannot be const, cannot
// hold state, cannot be rebuilt independently of its parent, and cannot reach
// a BuildContext unless every caller threads one in. "Dartvel decides whether
// a widget is stateless" is not something a function can ever do.
//
// Call sites are unaffected -- `FeatureCard('a', 'b')` reads the same whether
// it resolves to a function or a constructor -- so this is strictly more
// capable at the same syntax.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> widgetsFor(String source) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_fw_class_');
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
  File(p.join(root.path, 'lib', 'widgets.dart')).writeAsStringSync(source);

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

const String _imports = "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n";

void main() {
  test('it emits a widget class', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        "Widget _badge(String label) => DVText(label);\n");

    expect(widgets, contains('class Badge extends StatelessWidget'));
    expect(widgets, isNot(contains('Widget Badge(String label) {')));
  });

  test('the constructor is const, so a caller can be too', () async {
    // The whole reason a function was the wrong shape. A const widget is not
    // rebuilt when its parent is, and every page on a site is mostly these.
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        "Widget _badge(String label) => DVText(label);\n");

    expect(widgets, contains('const Badge('));
  });

  test('parameters become fields, positionally, in order', () async {
    // Call sites read the same as before or they all break at once.
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _card(String title, String body) => DVText(title + body);\n');

    expect(widgets, contains('final String title;'));
    expect(widgets, contains('final String body;'));
    expect(widgets, contains('const Card(this.title, this.body'));
  });

  test('named parameters with defaults survive', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _chip(String text, {bool onDark = false}) => DVText(text);\n');

    expect(widgets, contains('final bool onDark;'));
    expect(widgets, contains('this.onDark = false'));
  });

  test('a BuildContext parameter is supplied by build, not by the caller',
      () async {
    // A widget already has a context. Making it a constructor field would ask
    // every call site for something the framework hands over anyway, which is
    // exactly the threading a function forced.
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _tinted(BuildContext context, String text) =>\n'
        '    DVText(text);\n');

    expect(widgets, contains('class Tinted extends StatelessWidget'));
    expect(widgets, isNot(contains('final BuildContext context;')));
    expect(widgets, contains('Widget build(BuildContext context)'));
    // And the caller passes only the real arguments.
    expect(widgets, contains('const Tinted(this.text'));
  });

  test('a key is accepted, because every widget takes one', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        "Widget _badge(String label) => DVText(label);\n");

    expect(widgets, contains('super.key'));
  });

  test('a block body still lowers into the build method', () async {
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _stack(int count) {\n'
        '  final List<Widget> children = <Widget>[];\n'
        '  for (int i = 0; i < count; i++) {\n'
        '    children.add(DVText(i.toString()));\n'
        '  }\n'
        '  return DVBox.list(children);\n'
        '}\n');

    expect(widgets, contains('for (int i = 0; i < count; i++)'));
    expect(widgets, contains('return DVBox.list(children);'));
  });

  test('a helper declared in the same file still resolves', () async {
    // The natural shape: a component and the palette or formatter it is built
    // out of, side by side in one file. The body is lowered into the
    // generated widget, which carries the source file's imports -- but the
    // source file does not import itself, so a symbol declared right next to
    // the widget resolved to nothing.
    final String widgets = await widgetsFor('$_imports'
        'class Palette {\n'
        '  const Palette();\n'
        '  int get ink => 0xFF000000;\n'
        '}\n'
        '@DVFunctionalWidget()\n'
        'Widget _tinted(String text) => DVText(text);\n'
        '@DVFunctionalWidget()\n'
        'Widget _inked(String text) {\n'
        '  const Palette palette = Palette();\n'
        '  return DVText(text + palette.ink.toString());\n'
        '}\n');

    expect(widgets, contains('class Inked extends StatelessWidget'));
    // The symbol has to be qualified through the alias the generator gave the
    // source file, or it resolves to nothing in the generated library.
    expect(widgets, matches(RegExp(r"import 'package:fw_app/widgets\.dart' as (w\d+);")));
    final String alias = RegExp(r"import 'package:fw_app/widgets\.dart' as (w\d+);")
        .firstMatch(widgets)!
        .group(1)!;
    expect(widgets, contains('const $alias.Palette palette = $alias.Palette();'));
  });

  test('the generated library imports each URI once', () async {
    // Two annotated widgets in files that share an import used to emit that
    // import twice. It compiles, but only because duplicate_import is a lint
    // rather than an error -- a project that promotes its lints to errors, as
    // a framework's own generated output should survive, stops building.
    final String widgets = await widgetsFor('$_imports'
        '@DVFunctionalWidget()\n'
        'Widget _one(String text) {\n'
        '  return DVText(text);\n'
        '}\n');

    final List<String> imports = RegExp(r"^import [^;]+;", multiLine: true)
        .allMatches(widgets)
        .map((RegExpMatch m) => m.group(0)!)
        .toList();
    final Set<String> uris = <String>{};
    for (final String line in imports) {
      final String uri = RegExp(r"'([^']+)'").firstMatch(line)!.group(1)!;
      // An aliased import of the same URI is a different thing; a bare repeat
      // is not.
      if (line.contains(' as ')) continue;
      expect(uris.add(uri), isTrue, reason: 'duplicate import of $uri');
    }
  });
}
