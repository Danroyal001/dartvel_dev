import 'dart:io';

import 'package:dartvel_cli/src/build/document_slots.dart';
import 'package:dartvel_cli/src/config/dartvel_section.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `dartvel.platforms.web.document` written into the shell every page is made
/// from, refused when it would break the page, and listed in the policy.
void main() {
  late Directory project;

  void write(String path, String text) => File(p.join(project.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  String read(String path) => File(p.join(project.path, path)).readAsStringSync();

  const String shell = '<!DOCTYPE html><html><head><title>App</title></head>'
      '<body><script src="flutter_bootstrap.js" async></script></body></html>';

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_slots_');
    write('build/web/index.html', shell);
  });
  tearDown(() => project.deleteSync(recursive: true));

  void pubspec(String dartvel) => write('pubspec.yaml', 'name: shop\ndartvel:\n$dartvel');

  test('inline and file snippets land in the built shell, in order', () {
    write('html/head.html', '<meta name="from-file" content="1">\n');
    pubspec('''
  platforms:
    web:
      document:
        head:
          - html: <meta name="inline" content="1">
          - file: html/head.html
        bodyEnd:
          - html: <script>window.chat = true;</script>
''');
    final DVDocumentSlotsWrite result = dvWriteDocumentSlots(project.path, dvDartvelSection(project.path).values);
    expect(result.problems, isEmpty);
    expect(result.snippets, 3);
    final String html = read('build/web/index.html');
    expect(html.indexOf('name="inline"'), lessThan(html.indexOf('name="from-file"')));
    expect(html.indexOf('name="from-file"'), lessThan(html.indexOf('</head>')));
    expect(html.indexOf('window.chat'), greaterThan(html.indexOf('flutter_bootstrap.js')));
  });

  test('the older home, dartvel.web.document, still works', () {
    pubspec('''
  web:
    document:
      bodyStart:
        - html: <noscript>Tag</noscript>
''');
    final DVDocumentSlotsWrite result = dvWriteDocumentSlots(project.path, dvDartvelSection(project.path).values);
    expect(result.problems, isEmpty);
    expect(read('build/web/index.html'), contains('<body><!-- dartvel:body-start --><noscript>Tag</noscript>'));
  });

  test('a missing file is a build error naming it, and the shell is left alone', () {
    pubspec('''
  platforms:
    web:
      document:
        head:
          - file: html/missing.html
''');
    final DVDocumentSlotsWrite result = dvWriteDocumentSlots(project.path, dvDartvelSection(project.path).values);
    expect(result.problems.single, contains('html/missing.html'));
    expect(read('build/web/index.html'), shell);
  });

  test("a file whose HTML would swallow the page is a build error naming the file", () {
    write('html/banner.html', '<div class="banner">Sale');
    pubspec('''
  platforms:
    web:
      document:
        bodyStart:
          - file: html/banner.html
''');
    final DVDocumentSlotsWrite result = dvWriteDocumentSlots(project.path, dvDartvelSection(project.path).values);
    expect(result.problems.single, allOf(contains('html/banner.html'), contains('<div>')));
    expect(read('build/web/index.html'), shell);
  });

  test('a project with none leaves the shell byte for byte', () {
    pubspec('  seo:\n    siteName: Shop\n');
    final DVDocumentSlotsWrite result = dvWriteDocumentSlots(project.path, dvDartvelSection(project.path).values);
    expect(result.problems, isEmpty);
    expect(result.snippets, 0);
    expect(read('build/web/index.html'), shell);
  });

  group('typed references to the files under html/', () {
    test('one enum value per HTML file, the shell left out', () {
      write('html/head.html', '');
      write('html/tag-manager.html', '');
      write('web/index.html', '');
      write('web/favicon.png', '');
      final String source = dvWebFileRefsSource(project.path);
      expect(source, contains("enum DVWebFile implements DVWebFileRef"));
      expect(source, contains("head('html/head.html')"));
      expect(source, contains("tagManager('html/tag-manager.html')"));
      expect(source, isNot(contains('index.html')));
      expect(source, isNot(contains('favicon')));
      expect(source, contains("import 'package:dartvel_core/config.dart';"));
    });

    test('a project with none still compiles', () {
      expect(dvWebFileRefsSource(project.path), contains('none('));
    });
  });

  test('the policy gains the hosts and hashes the snippets need', () {
    pubspec('''
  security:
    pageCsp: "default-src 'self'; script-src 'self'"
  platforms:
    web:
      document:
        head:
          - html: <script async src="https://www.googletagmanager.com/gtag/js?id=G-1"></script>
''');
    expect(
      dvPageCspWithProjectSlots(project.path, "default-src 'self'; script-src 'self'"),
      "default-src 'self'; script-src 'self' https://www.googletagmanager.com",
    );
  });
}
