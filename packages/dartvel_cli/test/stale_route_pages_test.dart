// A route removed from the application stops being a page in build/web.
//
// build/web is not emptied between builds. When sites/dartvel_site turned
// off its auth pages, a rebuild wrote a sitemap without /login and /sign-up
// and left build/web/login/index.html and build/web/sign-up/index.html where
// they were, so an upload of build/web went on serving both.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String shell = '<html><head>\n<title>App</title>\n</head>'
    '<body></body></html>';

void main() {
  late Directory project;
  late Directory web;
  late Directory source;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dartvel_stale_pages');
    web = Directory(p.join(project.path, 'build', 'web'))
      ..createSync(recursive: true);
    source = Directory(p.join(project.path, 'web'))..createSync();
  });

  tearDown(() => project.deleteSync(recursive: true));

  void writeRoutePage(String route) {
    File(p.join(web.path, dvStaticRoutePath(route)!))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(dvStaticPage(shell: shell, route: route, title: route));
  }

  List<String> remove(List<String> routes) => dvRemoveStaleRoutePages(
        webRoot: web,
        sourceWeb: source,
        routes: routes,
      );

  test('a page for a route that no longer exists is removed with its folder',
      () {
    writeRoutePage('/docs');
    writeRoutePage('/login');
    writeRoutePage('/account/sign-up');

    final List<String> removed = remove(<String>['/', '/docs']);

    expect(removed, unorderedEquals(<String>[
      'login/index.html',
      'account/sign-up/index.html',
    ]));
    expect(File(p.join(web.path, 'docs', 'index.html')).existsSync(), isTrue);
    expect(Directory(p.join(web.path, 'login')).existsSync(), isFalse);
    expect(Directory(p.join(web.path, 'account')).existsSync(), isFalse);
  });

  test('a folder that holds anything else keeps it', () {
    writeRoutePage('/login');
    File(p.join(web.path, 'login', 'logo.png')).writeAsStringSync('png');

    remove(<String>['/']);

    expect(File(p.join(web.path, 'login', 'index.html')).existsSync(), isFalse);
    expect(File(p.join(web.path, 'login', 'logo.png')).existsSync(), isTrue);
  });

  test('a page the project placed in web/ is never removed', () {
    // Flutter copies web/ into build/web. A copy of a Dartvel page kept there
    // on purpose carries the same marker, and is still the project's file.
    writeRoutePage('/legal');
    File(p.join(source.path, 'legal', 'index.html'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('mine');

    expect(remove(<String>['/']), isEmpty);
    expect(File(p.join(web.path, 'legal', 'index.html')).existsSync(), isTrue);
  });

  test('HTML Dartvel did not write as a route page is left alone', () {
    // The offline and not-found pages, and anything a host or a person put
    // in build/web, carry no route page head.
    for (final String name in <String>['offline', '404', 'extra']) {
      File(p.join(web.path, name, 'index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<html><body>$name</body></html>');
    }
    File(p.join(web.path, 'index.html')).writeAsStringSync(
        dvStaticPage(shell: shell, route: '/', title: 'Home'));

    expect(remove(<String>['/docs']), isEmpty);
    expect(File(p.join(web.path, 'index.html')).existsSync(), isTrue);
    expect(File(p.join(web.path, 'offline', 'index.html')).existsSync(), isTrue);
  });
}
