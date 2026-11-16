// A page is found by its declaration, never by words in its strings or
// comments.
//
// A function page on dartvel.dev explains class widgets in a sentence: "Put
// @DVPage on a class that extends DVClassWidget". The class-page pattern read
// that sentence as a declaration, took `that` for the page class, and the
// generated router called `that()` -- which does not compile, so the whole
// site stopped building over a line of prose.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/generators/page_names.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String functionPageExplainingClasses = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// A page may also be a class that extends DartvelPage.
@DVPage(title: 'Class widgets')
Widget _classWidgetsPage(BuildContext context) => const DVText(
      'Put @DVPage on a class that extends DVClassWidget, in a file under lib/pages.',
    );
''';

void main() {
  test('dvPageSymbol reads the function, not the sentence in its string', () {
    expect(dvPageSymbol(functionPageExplainingClasses), '_classWidgetsPage');
  });

  test('a real class page is still found', () {
    expect(
      dvPageSymbol('''
@DVPage(title: 'About')
class const AboutPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => const DVText('A class that extends DVClassWidget');
}
'''),
      'AboutPage',
    );
  });

  test('the generated router wraps the function page and calls no `that`', () async {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_page_strings_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'class-widgets.dart'))
        .writeAsStringSync(functionPageExplainingClasses);
    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'strings_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      devBackendHost: 'http://localhost:3000',
      prodBackendHost: 'https://api.example.test',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'Strings App',
      seoTitle: 'Strings App',
      seoDesc: 'Strings App',
      seoImage: '',
      seoTwitter: '',
      defaultTransition: 'fade',
      durationMs: 200,
      curve: 'easeInOut',
      normalizeTrailing: true,
      notFoundRedirect: '',
      plugins: const <String>[],
      ota: false,
      dv: YamlMap.wrap(<String, Object?>{}),
    );
    final String router =
        File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart')).readAsStringSync();
    expect(router, isNot(contains('.that(')));
    expect(router, contains('class ClassWidgetsPageGeneratedPage extends DartvelPage'));
  });
}
