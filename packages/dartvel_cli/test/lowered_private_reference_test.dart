// A lowered body that reaches for a private symbol fails with a message.
//
// The body is moved into the generated router, where a private top-level
// symbol from the page's file is simply not visible. Emitting the reference
// anyway produced generated code that does not compile, and the error named a
// line in a file the developer never wrote:
//
//   router.g.dart:300: The getter '_shipped' isn't defined for the type
//   'FeaturesPageGeneratedPage'.
//
// Which is true, unhelpful, and points at the wrong file.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<void> generate(String pageSource) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_private_ref_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
      .writeAsStringSync(pageSource);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'private_app',
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
}

const String _imports = "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n";

void main() {
  test('a private helper is named, with what to do about it', () async {
    await expectLater(
      generate('$_imports'
          "@DVPage(title: 'Home')\n"
          'Widget _homePage(BuildContext context) => _section();\n'
          "Widget _section() => const DVText('hi');\n"),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        allOf(
          contains('_section'),
          contains('@DVFunctionalWidget'),
        ),
      )),
    );
  });

  test('a private constant is named too', () async {
    await expectLater(
      generate('$_imports'
          "const List<String> _rows = <String>['a'];\n"
          "@DVPage(title: 'Home')\n"
          'Widget _homePage(BuildContext context) => DVText(_rows.first);\n'),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('_rows'),
      )),
    );
  });

  test('a public symbol is fine, because it can be reached', () async {
    await generate('$_imports'
        "const List<String> rows = <String>['a'];\n"
        "@DVPage(title: 'Home')\n"
        'Widget _homePage(BuildContext context) => DVText(rows.first);\n');
  });

  test('the page function itself is not mistaken for a reference', () async {
    // `_homePage` is private and appears in its own body's scope; flagging the
    // page for being private would refuse every page there is.
    await generate('$_imports'
        "@DVPage(title: 'Home')\n"
        "Widget _homePage(BuildContext context) => const DVText('hi');\n");
  });

  test('a private local inside the body is not a top-level reference',
      () async {
    // Locals are moved with the body and stay in scope.
    await generate('$_imports'
        "@DVPage(title: 'Home')\n"
        'Widget _homePage(BuildContext context) {\n'
        "  final String _label = 'hi';\n"
        '  return DVText(_label);\n'
        '}\n');
  });
}
