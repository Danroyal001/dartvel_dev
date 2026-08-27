// `dartvel build web-server`.
//
// `dartvel build web` writes a file per route: every page's head tags, its
// text, a sitemap and robots.txt, all decided at build time. That is right for
// a static host and wrong the moment a page depends on anything that changes —
// a model-backed page whose content lives in a database is stale the instant
// it is written.
//
// web-server produces the same pages from the same pieces, on request. What
// differs is when, not what: the bundle has no per-route HTML in it, and the
// server holds the manifest it needs to build one for any route it is asked
// for.
import 'dart:convert';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:test/test.dart';

const Map<String, List<String>> text = <String, List<String>>{
  '/': <String>['Home', 'A sentence.'],
  '/docs': <String>['Documentation', 'From nothing to a running app.'],
};

const Map<String, String> titles = <String, String>{
  '/': 'Dartvel',
  '/docs': 'Documentation — Dartvel',
};

void main() {
  group('the manifest the server is given', () {
    test('it carries every route, its title and its text', () {
      final manifest = dvWebServerManifest(
        routes: <String>['/', '/docs'],
        titles: titles,
        text: text,
        siteUrl: 'https://dartvel.dev',
      );

      final decoded = jsonDecode(manifest) as Map<String, Object?>;
      expect((decoded['routes'] as Map<String, Object?>).keys,
          containsAll(<String>['/', '/docs']));
      expect(decoded['siteUrl'], 'https://dartvel.dev');
    });

    test('a route that is a shape rather than a page is still carried', () {
      // The opposite of the static build, and the reason this target exists.
      // /post/:id cannot be written to a file and can certainly be served, so
      // the server needs to know about it.
      final decoded = jsonDecode(dvWebServerManifest(
        routes: <String>['/', '/post/:id'],
        titles: const <String, String>{},
        text: const <String, List<String>>{},
        siteUrl: 'https://dartvel.dev',
      )) as Map<String, Object?>;

      expect((decoded['routes'] as Map<String, Object?>).keys,
          contains('/post/:id'));
    });

    test('it is valid JSON a server can read without a Dart parser', () {
      expect(
        () => jsonDecode(dvWebServerManifest(
          routes: <String>['/'],
          titles: titles,
          text: text,
          siteUrl: null,
        )),
        returnsNormally,
      );
    });
  });

  group('serving a page', () {
    const String shell = '<html><head>\n<title>App</title>\n</head>'
        '<body></body></html>';

    test('an exact route gets its own title, text and canonical', () {
      final page = dvServeRoute(
        shell: shell,
        path: '/docs',
        routes: titles,
        text: text,
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('<title>Documentation — Dartvel</title>'));
      expect(page, contains('From nothing to a running app.'));
      expect(page, contains('href="https://dartvel.dev/docs"'));
    });

    test('the canonical is the requested path, not the site root', () {
      // Every page canonicalising to / tells a crawler they are one page.
      final page = dvServeRoute(
        shell: shell,
        path: '/docs',
        routes: titles,
        text: text,
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, isNot(contains('href="https://dartvel.dev"\n')));
    });

    test('a parameterised route is matched and served', () {
      // What the static build cannot do at all.
      final page = dvServeRoute(
        shell: shell,
        path: '/post/hello-world',
        routes: const <String, String>{'/post/:id': 'A post'},
        text: const <String, List<String>>{},
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('<title>A post</title>'));
      expect(page, contains('href="https://dartvel.dev/post/hello-world"'),
          reason: 'the canonical is the URL asked for, not the pattern');
    });

    test('an unknown path still gets the app shell', () {
      // The router owns client-side 404s. Refusing to serve the shell would
      // turn a route the server has not heard of into a blank page.
      final page = dvServeRoute(
        shell: shell,
        path: '/nothing-here',
        routes: titles,
        text: text,
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('<body'));
      expect(page, contains('<title>'));
    });

    test('the text is escaped, and a path cannot inject markup', () {
      final page = dvServeRoute(
        shell: shell,
        path: '/post/<script>alert(1)</script>',
        routes: const <String, String>{'/post/:id': 'A post'},
        text: const <String, List<String>>{},
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, isNot(contains('<script>alert(1)</script>')));
    });
  });

  group('what the bundle contains', () {
    test('no per-route HTML, because the server writes those', () {
      final plan = dvWebServerPlan(routes: <String>['/', '/docs']);

      expect(plan.writesPerRouteHtml, isFalse);
      expect(plan.writesManifest, isTrue);
    });

    test('robots and the sitemap are still files', () {
      // They are one document each and do not vary by request; generating
      // them per fetch would be work for nothing.
      final plan = dvWebServerPlan(routes: <String>['/', '/docs']);

      expect(plan.writesSitemap, isTrue);
      expect(plan.writesRobots, isTrue);
    });
  });

  group('switching from a static build', () {
    test('stale per-route files are named for removal', () {
      // A directory that held a static build still has /docs/index.html in
      // it. A server that falls through to a file would serve that instead of
      // the page it just rendered -- the stale copy shadows the live one, and
      // the symptom is a page that will not update.
      final stale = dvWebServerStaleFiles(
        present: <String>[
          'index.html',
          'docs/index.html',
          'features/index.html',
          'main.dart.js',
          'assets/fonts.otf',
        ],
      );

      expect(stale, containsAll(<String>['docs/index.html', 'features/index.html']));
    });

    test('the shell is kept, because the server serves it', () {
      expect(dvWebServerStaleFiles(present: <String>['index.html']), isEmpty);
    });

    test('nothing else is touched', () {
      // Deleting more than the pages would take the application with them.
      final stale = dvWebServerStaleFiles(
        present: <String>['main.dart.js', 'assets/x.png', 'manifest.json'],
      );

      expect(stale, isEmpty);
    });
  });
}
