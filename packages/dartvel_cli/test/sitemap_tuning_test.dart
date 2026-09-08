// Per-route sitemap tuning: what a page says about itself, and what the
// project says about the rest.
//
// NEW_SPEC.md writes both halves --
//
//     @DVPage(sitemap: DVPageSitemap(priority: 0.8,
//         changeFrequency: DVSitemapChangeFrequency.daily))
//
// and, in pubspec.yaml,
//
//     dartvel:
//       seo:
//         sitemap:
//           enabled: true
//           exclude: [/admin/**, /account/**]
//           defaults: { priority: 0.5, changeFrequency: weekly }
//
// -- and neither reached sitemap.xml. Every route was written out as a <loc>
// and nothing else, which is a sitemap that tells a crawler the site exists
// and nothing about which page is worth its time.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'sitemap_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Sitemap App',
    seoTitle: 'Sitemap App',
    seoDesc: 'Sitemap App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
  ).readAsStringSync();
}

void main() {
  group('a page says how it should be crawled', () {
    test('the generator writes down what the page declared', () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_sitemap_entries_',
      );
      try {
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);

        File(p.join(root.path, 'lib', 'pages', 'blog.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.daily,
  ),
)
Widget blogPage(BuildContext context) => const SizedBox.shrink();
''');
        File(p.join(root.path, 'lib', 'pages', 'about.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget aboutPage(BuildContext context) => const SizedBox.shrink();
''');

        final String router = await _routerFor(root);
        final Map<String, DVSitemapEntry> entries = dvSitemapEntries(router);

        expect(entries['/blog']?.priority, 0.8);
        expect(entries['/blog']?.changeFrequency, 'daily');
        // A page that said nothing gets no entry rather than an empty one,
        // so the project defaults apply to it.
        expect(entries.containsKey('/about'), isFalse);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a page with a sitemap argument is still a page', () async {
      // The nested call used to end the annotation as far as every parser
      // here was concerned, and the route vanished from the router with
      // nothing said.
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_sitemap_nested_',
      );
      try {
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
        File(p.join(root.path, 'lib', 'pages', 'blog.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(
  sitemap: DVPageSitemap(priority: 0.8),
  title: 'Blog',
  policy: DVPolicies.viewAdmin,
)
Widget blogPage(BuildContext context) => const SizedBox.shrink();
''');

        final String router = await _routerFor(root);

        expect(router, contains("path: '/blog'"));
        // The arguments after the nested one are read too.
        expect(router, contains("title: 'Blog'"));
        expect(dvGuardedRoutes(router), contains('/blog'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('an empty map parses as empty, and an absent one is not an error',
        () {
      expect(
        dvSitemapEntries(
          'const Map<String, DVPageSitemap> dartvelSitemapEntries = '
          '<String, DVPageSitemap>{};',
        ),
        isEmpty,
      );
      expect(dvSitemapEntries('void main() {}'), isEmpty);
    });
  });

  group('the sitemap carries priority and change frequency', () {
    test("a page's own values are written out", () {
      final String xml = dvSitemap(
        routes: <String>['/', '/blog'],
        siteUrl: 'https://example.test',
        entries: <String, DVSitemapEntry>{
          '/blog': const DVSitemapEntry(priority: 0.8, changeFrequency: 'daily'),
        },
      );

      expect(xml, contains('<priority>0.8</priority>'));
      expect(xml, contains('<changefreq>daily</changefreq>'));
    });

    test('a route that declared nothing takes the project defaults', () {
      final String xml = dvSitemap(
        routes: <String>['/about'],
        siteUrl: 'https://example.test',
        defaults: const DVSitemapEntry(priority: 0.5, changeFrequency: 'weekly'),
      );

      expect(xml, contains('<priority>0.5</priority>'));
      expect(xml, contains('<changefreq>weekly</changefreq>'));
    });

    test('a page beats the defaults on the half it declared', () {
      // Half, not all of it: a page that only says it changes daily should
      // keep the project's priority rather than losing it to null.
      final String xml = dvSitemap(
        routes: <String>['/blog'],
        siteUrl: 'https://example.test',
        entries: <String, DVSitemapEntry>{
          '/blog': const DVSitemapEntry(changeFrequency: 'daily'),
        },
        defaults: const DVSitemapEntry(priority: 0.5, changeFrequency: 'weekly'),
      );

      expect(xml, contains('<changefreq>daily</changefreq>'));
      expect(xml, contains('<priority>0.5</priority>'));
      expect(xml, isNot(contains('weekly')));
    });

    test('with nothing declared anywhere a url is still just a url', () {
      // A priority nobody asked for is not a neutral default: 0.5 on every
      // page says the same thing as no priority at all, in more bytes, and a
      // crawler that reads it cannot tell it was invented.
      final String xml = dvSitemap(
        routes: <String>['/about'],
        siteUrl: 'https://example.test',
      );

      expect(xml, contains('<loc>https://example.test/about</loc>'));
      expect(xml, isNot(contains('<priority>')));
      expect(xml, isNot(contains('<changefreq>')));
    });

    test('a priority outside 0..1 is refused, not clamped', () {
      // A 5 that silently became a 1 reads as working, and the page it was
      // written on is the one the author cared most about.
      expect(
        () => dvSitemap(
          routes: <String>['/blog'],
          siteUrl: 'https://example.test',
          entries: <String, DVSitemapEntry>{
            '/blog': const DVSitemapEntry(priority: 5),
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('/blog'),
          ),
        ),
      );
    });

    test('an unknown change frequency is refused', () {
      // sitemaps.org defines seven words. A crawler drops the whole <url>
      // element when one of its children will not validate, so a typo here
      // removes the page rather than the hint.
      expect(
        () => dvSitemap(
          routes: <String>['/blog'],
          siteUrl: 'https://example.test',
          entries: <String, DVSitemapEntry>{
            '/blog': const DVSitemapEntry(changeFrequency: 'often'),
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the project can exclude routes by pattern', () {
    test('a section pattern excludes the section and everything under it', () {
      // /admin/** takes /admin with it. Publishing the front door of a
      // section whose every child is hidden discloses the same thing the
      // pattern was written to hide.
      final String xml = dvSitemap(
        routes: <String>['/', '/admin', '/admin/users', '/about'],
        siteUrl: 'https://example.test',
        exclude: const <String>['/admin/**'],
      );

      expect(xml, contains('/about'));
      expect(xml, isNot(contains('/admin')));
    });

    test('a single-segment pattern does not take the whole subtree', () {
      expect(
        dvSitemapExcluded('/blog/2026/january', const <String>['/blog/*']),
        isFalse,
      );
      expect(
        dvSitemapExcluded('/blog/hello', const <String>['/blog/*']),
        isTrue,
      );
    });

    test('a pattern is anchored, so /admin does not exclude /superadmin', () {
      expect(
        dvSitemapExcluded('/superadmin', const <String>['/admin/**']),
        isFalse,
      );
    });
  });

  group('reading the project configuration', () {
    test('the shape the specification writes is the shape that is read', () {
      final DVSitemapConfig config = dvSitemapConfig(
        YamlMap.wrap(<String, Object?>{
          'seo': <String, Object?>{
            'sitemap': <String, Object?>{
              'enabled': true,
              'exclude': <String>['/admin/**', '/account/**'],
              'defaults': <String, Object?>{
                'priority': 0.5,
                'changeFrequency': 'weekly',
              },
            },
          },
        }),
      );

      expect(config.enabled, isTrue);
      expect(config.exclude, <String>['/admin/**', '/account/**']);
      expect(config.defaults?.priority, 0.5);
      expect(config.defaults?.changeFrequency, 'weekly');
    });

    test('a project that says nothing gets a sitemap', () {
      // The default is on. A site that never configured SEO is the one that
      // needs the file written for it.
      final DVSitemapConfig config =
          dvSitemapConfig(YamlMap.wrap(<String, Object?>{}));

      expect(config.enabled, isTrue);
      expect(config.exclude, isEmpty);
      expect(config.defaults, isNull);
    });

    test('enabled: false is honoured', () {
      final DVSitemapConfig config = dvSitemapConfig(
        YamlMap.wrap(<String, Object?>{
          'seo': <String, Object?>{
            'sitemap': <String, Object?>{'enabled': false},
          },
        }),
      );

      expect(config.enabled, isFalse);
    });

    test('changefreq: is accepted as well as changeFrequency:', () {
      // The XML element is <changefreq>. A developer who copied it from the
      // file they are configuring should not get silence.
      final DVSitemapConfig config = dvSitemapConfig(
        YamlMap.wrap(<String, Object?>{
          'seo': <String, Object?>{
            'sitemap': <String, Object?>{
              'defaults': <String, Object?>{'changefreq': 'monthly'},
            },
          },
        }),
      );

      expect(config.defaults?.changeFrequency, 'monthly');
    });
  });

  group('robots.txt agrees with what was written', () {
    test('a sitemap that was written is named', () {
      expect(
        dvRobots(siteUrl: 'https://example.test'),
        contains('Sitemap: https://example.test/sitemap.xml'),
      );
    });

    test('a sitemap that was turned off is not named', () {
      // Pointing a crawler at a 404 is worse than saying nothing.
      expect(
        dvRobots(siteUrl: 'https://example.test', sitemap: false),
        isNot(contains('Sitemap:')),
      );
    });
  });
}
