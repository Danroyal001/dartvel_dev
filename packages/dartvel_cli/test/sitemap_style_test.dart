// A sitemap someone can read.
//
// A bare urlset renders as the browser's XML tree view: a wall of angle
// brackets that says nothing about the site. Yoast and AIOSEO have shipped a
// styled one for years, and it costs one stylesheet instruction -- crawlers
// ignore it entirely, because XSLT is applied by browsers and not by them.
//
// The styling comes from the application's own theme, so a Dartvel site's
// sitemap looks like that site rather than like Dartvel.
import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:test/test.dart';

void main() {
  group('the sitemap points at its stylesheet', () {
    test('the instruction comes before the urlset', () {
      // A processing instruction after the root element is ignored, and the
      // page renders as the raw tree with no sign of why.
      final xml = dvSitemap(
        routes: <String>['/', '/docs'],
        siteUrl: 'https://dartvel.dev',
      );

      expect(xml, contains('<?xml-stylesheet type="text/xsl" '
          'href="/sitemap.xsl"?>'));
      expect(xml.indexOf('xml-stylesheet'), lessThan(xml.indexOf('<urlset')));
    });

    test('it is still a valid sitemap', () {
      final xml = dvSitemap(
        routes: <String>['/docs'],
        siteUrl: 'https://dartvel.dev',
      );

      expect(xml, contains('<loc>https://dartvel.dev/docs</loc>'));
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    });
  });

  group('the stylesheet', () {
    String sheet({String? accent, String? ink}) => dvSitemapStylesheet(
          siteName: 'Dartvel',
          tagline: 'Flutter, all the way down.',
          accent: accent ?? '#2563EB',
          ink: ink ?? '#0B1020',
        );

    test('it is a stylesheet, not a page', () {
      expect(sheet(), startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(sheet(), contains('xsl:stylesheet'));
      expect(sheet(), contains('http://www.sitemaps.org/schemas/sitemap/0.9'));
    });

    test('it names the site rather than the framework', () {
      expect(sheet(), contains('Dartvel'));
      expect(sheet(), contains('Flutter, all the way down.'));
    });

    test('it takes its colours from the application', () {
      final custom = sheet(accent: '#CBAB6B', ink: '#1D0E0A');

      expect(custom, contains('#CBAB6B'));
      expect(custom, contains('#1D0E0A'));
      expect(custom, isNot(contains('#2563EB')));
    });

    test('it renders a row per URL', () {
      expect(sheet(), contains('xsl:for-each'));
      expect(sheet(), contains('sitemap:loc'));
    });

    test('it counts what is in the file', () {
      // The number is the reason to open a sitemap at all.
      expect(sheet(), contains('count(') );
    });

    test('each URL is a link', () {
      // A sitemap you cannot click is a list of strings.
      expect(sheet(), contains('<a href="{sitemap:loc}"'));
    });

    test('it reads in both themes', () {
      // A sitemap opens in whatever the reader has, and a stylesheet with one
      // hard-coded background is unreadable in the other.
      expect(sheet(), contains('prefers-color-scheme'));
    });

    test('a name with markup in it cannot break the document', () {
      final risky = dvSitemapStylesheet(
        siteName: 'A & B <script>',
        tagline: 'x',
        accent: '#000000',
        ink: '#FFFFFF',
      );

      expect(risky, isNot(contains('<script>')));
      expect(risky, contains('&amp;'));
    });
  });
}
