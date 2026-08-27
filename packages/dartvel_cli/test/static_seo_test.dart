// Per-route HTML, a sitemap and robots.txt for a static build.
//
// `dartvel build web` produced one index.html for every route. On a static
// host that is what a crawler gets: four URLs, one title, one description,
// one body. `dartvel prerender` already captures a title and semantic content
// per route, but it writes prerender/<route>/meta.json for a *server* to
// inject -- and a static host has no server to do it.
//
// So the thing that distinguishes this from `flutter build web` was only true
// when a Dartvel server was in front of it.
import 'dart:convert';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:test/test.dart';

const String shell = '<html><head>\n<title>App</title>\n</head>'
    '<body></body></html>';

void main() {
  group('where a route is written', () {
    test('the root stays index.html', () {
      expect(dvStaticRoutePath('/'), 'index.html');
    });

    test('a route becomes a directory with an index inside it', () {
      // /docs/index.html, not /docs.html: it lets the server serve /docs and
      // /docs/ from the same place without a rewrite.
      expect(dvStaticRoutePath('/docs'), 'docs/index.html');
      expect(dvStaticRoutePath('/docs/'), 'docs/index.html');
    });

    test('a nested route keeps its shape', () {
      expect(dvStaticRoutePath('/blog/first-post'), 'blog/first-post/index.html');
    });

    test('a parameterised route is not written, because it has no one value', () {
      // /post/:id names a shape, not a page. Writing it would produce a file
      // literally called ":id".
      expect(dvStaticRoutePath('/post/:id'), isNull);
      expect(dvStaticRoutePath('/user/:id/posts'), isNull);
    });

    test('a route cannot escape the output directory', () {
      expect(dvStaticRoutePath('/../etc/passwd'), isNull);
      expect(dvStaticRoutePath('//evil'), isNull);
    });
  });

  group('what each page carries', () {
    test('its own title and description, not the shell’s', () {
      final page = dvStaticPage(
        shell: shell,
        route: '/docs',
        title: 'Documentation — Dartvel',
        description: 'From nothing to a running app.',
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('<title>Documentation — Dartvel</title>'));
      expect(page, contains('From nothing to a running app.'));
      expect(page, isNot(contains('<title>App</title>')));
    });

    test('a canonical URL pointing at itself, not at the site root', () {
      // Every page canonicalising to / tells a crawler they are all the same
      // page, which is worse than having no canonical at all.
      final page = dvStaticPage(
        shell: shell,
        route: '/docs',
        title: 'T',
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('href="https://dartvel.dev/docs"'));
    });

    test('the root canonicalises without a trailing slash artefact', () {
      final page = dvStaticPage(
        shell: shell,
        route: '/',
        title: 'T',
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('href="https://dartvel.dev"'));
      expect(page, isNot(contains('dartvel.dev//')));
    });

    test('prerendered content reaches the body, escaped', () {
      // The body is empty until JavaScript runs, so without this a crawler
      // sees nothing. It comes from the page, so it is escaped like any other
      // untrusted value.
      final page = dvStaticPage(
        shell: shell,
        route: '/docs',
        title: 'T',
        content: 'Install with <brew> & go',
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('&lt;brew&gt;'));
      expect(page, contains('&amp;'));
      expect(page, isNot(contains('<brew>')));
    });

    test('the base href is rewritten so assets still resolve one level down',
        () {
      // /docs/index.html is one directory deep. A relative asset path would
      // resolve to /docs/main.dart.js and 404.
      final page = dvStaticPage(
        shell: '<html><head><base href="/"><title>App</title></head>'
            '<body></body></html>',
        route: '/docs',
        title: 'T',
        siteUrl: 'https://dartvel.dev',
      );

      expect(page, contains('<base href="/">'));
    });
  });

  group('the sitemap', () {
    test('it lists every static route, absolute', () {
      final xml = dvSitemap(
        routes: <String>['/', '/docs', '/features'],
        siteUrl: 'https://dartvel.dev',
      );

      expect(xml, contains('<loc>https://dartvel.dev</loc>'));
      expect(xml, contains('<loc>https://dartvel.dev/docs</loc>'));
      expect(xml, contains('<loc>https://dartvel.dev/features</loc>'));
    });

    test('it omits routes that are shapes rather than pages', () {
      final xml = dvSitemap(
        routes: <String>['/', '/post/:id'],
        siteUrl: 'https://dartvel.dev',
      );

      expect(xml, isNot(contains(':id')));
    });

    test('it is well-formed XML with the right namespace', () {
      final xml = dvSitemap(routes: <String>['/'], siteUrl: 'https://x.dev');

      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('http://www.sitemaps.org/schemas/sitemap/0.9'));
      expect('<url>'.allMatches(xml).length, '</url>'.allMatches(xml).length);
    });

    test('an ampersand in a route is escaped, or the XML is invalid', () {
      final xml = dvSitemap(
        routes: <String>['/a&b'],
        siteUrl: 'https://x.dev',
      );

      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('/a&b<')));
    });
  });

  group('robots.txt', () {
    test('it allows crawling and points at the sitemap', () {
      final robots = dvRobots(siteUrl: 'https://dartvel.dev');

      expect(robots, contains('User-agent: *'));
      expect(robots, contains('Allow: /'));
      expect(robots, contains('Sitemap: https://dartvel.dev/sitemap.xml'));
    });

    test('a trailing slash on the site URL does not double up', () {
      expect(dvRobots(siteUrl: 'https://dartvel.dev/'),
          contains('https://dartvel.dev/sitemap.xml'));
    });
  });

  group('reading what prerender captured', () {
    test('a meta.json supplies the title and content for its route', () {
      final meta = jsonEncode(<String, Object?>{
        'title': 'Docs — Dartvel',
        'content': 'Getting started',
        'route': '/docs',
      });

      final parsed = dvPrerenderedMeta(meta);

      expect(parsed?.title, 'Docs — Dartvel');
      expect(parsed?.content, 'Getting started');
    });

    test('malformed JSON is ignored rather than failing the build', () {
      // A prerender that half-ran should not stop a release; the page simply
      // falls back to the configured title.
      expect(dvPrerenderedMeta('{not json'), isNull);
      expect(dvPrerenderedMeta(''), isNull);
    });
  });

  // Each page declares its own title in @DVPage, and the generator puts it in
  // the router. Deriving one from the path instead produced "Docs — Dartvel —
  // Flutter, full stack": the page's real title, thrown away, replaced by a
  // capitalised path segment glued to the site title that already contained
  // the site name.
  group('titles the pages actually declare', () {
    const String router = """
class CloudPageGeneratedPage extends DVGeneratedPage {
  DVPageScaffoldSpec get pageScaffold => const DVPageScaffoldSpec(title: 'Cloud — Dartvel', showAppBar: false);
}
class DocsPageGeneratedPage extends DVGeneratedPage {
  DVPageScaffoldSpec get pageScaffold => const DVPageScaffoldSpec(title: 'Documentation — Dartvel', showAppBar: false);
}
      path: '/cloud',
        final page = const CloudPageGeneratedPage();
      path: '/docs',
        final page = const DocsPageGeneratedPage();
""";

    test('a route resolves to the title its page declares', () {
      final titles = dvRouteTitles(router);

      expect(titles['/docs'], 'Documentation — Dartvel');
      expect(titles['/cloud'], 'Cloud — Dartvel');
    });

    test('a route whose page declares none is simply absent', () {
      // Absent rather than empty, so the caller falls back rather than
      // setting a blank title.
      expect(dvRouteTitles(router)['/nothing'], isNull);
      expect(dvRouteTitles('')['/'], isNull);
    });

    test('it does not confuse two pages whose classes look alike', () {
      const String tricky = """
class FeaturesPageGeneratedPage extends DVGeneratedPage {
  DVPageScaffoldSpec get pageScaffold => const DVPageScaffoldSpec(title: 'Features');
}
class FeaturePageGeneratedPage extends DVGeneratedPage {
  DVPageScaffoldSpec get pageScaffold => const DVPageScaffoldSpec(title: 'One feature');
}
      path: '/features',
        final page = const FeaturesPageGeneratedPage();
      path: '/feature',
        final page = const FeaturePageGeneratedPage();
""";

      final titles = dvRouteTitles(tricky);

      expect(titles['/features'], 'Features');
      expect(titles['/feature'], 'One feature');
    });
  });
}
