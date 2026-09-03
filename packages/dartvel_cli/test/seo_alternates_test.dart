// hreflang: telling a crawler which language each page is, and where the
// others are.
//
// The i18n section promises SEO alternate locale tags and the head writer had
// canonical, OpenGraph and Twitter and nothing about language. So a site
// with /fr/pricing and /de/pricing showed a crawler three unrelated pages
// with the same content, which search engines treat as duplicates rather
// than translations, and a French searcher got the English one.
import 'package:dartvel_cli/src/build/seo_head.dart';
import 'package:test/test.dart';

void main() {
  group('the head', () {
    test('every alternate is a link with its hreflang', () {
      final String head = dvSeoHead(
        title: 'Pricing',
        siteUrl: 'https://example.com/pricing',
        alternates: <String, String>{
          'en': 'https://example.com/pricing',
          'fr': 'https://example.com/fr/pricing',
          'de': 'https://example.com/de/pricing',
        },
      );

      expect(head, contains('<link rel="alternate" hreflang="en" href="https://example.com/pricing">'));
      expect(head, contains('<link rel="alternate" hreflang="fr" href="https://example.com/fr/pricing">'));
      expect(head, contains('<link rel="alternate" hreflang="de" href="https://example.com/de/pricing">'));
    });

    test('x-default names where an unmatched language goes', () {
      // Without it a searcher in a language the site does not have lands on
      // whichever alternate the engine picks, which is often the wrong one.
      // Two languages, as any real hreflang set has: x-default beside a
      // single alternate would itself be the lone declaration the rule
      // below refuses to write.
      final String head = dvSeoHead(
        title: 'Pricing',
        alternates: <String, String>{
          'en': 'https://example.com/pricing',
          'fr': 'https://example.com/fr/pricing',
        },
        defaultAlternate: 'https://example.com/pricing',
      );
      expect(head, contains('<link rel="alternate" hreflang="x-default" href="https://example.com/pricing">'));
    });

    test('no alternates writes no hreflang at all', () {
      // A single-language site must not declare itself as one alternate of
      // itself; engines read a lone hreflang as a misconfiguration.
      expect(dvSeoHead(title: 'Pricing'), isNot(contains('hreflang')));
    });

    test('a region tag keeps its case the way hreflang wants it', () {
      final String head = dvSeoHead(
        title: 'x',
        alternates: <String, String>{'pt-BR': 'https://example.com/pt-br/x', 'en': 'https://example.com/x'},
      );
      expect(head, contains('hreflang="pt-BR"'));
    });

    test('the URL is escaped as an attribute', () {
      final String head = dvSeoHead(
        title: 'x',
        alternates: <String, String>{'en': 'https://example.com/x?a=1&b=2', 'fr': 'https://example.com/fr/x'},
      );
      expect(head, contains('href="https://example.com/x?a=1&amp;b=2"'));
    });
  });

  group('building the set for a route', () {
    test('a route gets one URL per locale, with the default locale unprefixed', () {
      final Map<String, String> alternates = dvSeoAlternatesFor(
        siteUrl: 'https://example.com',
        route: '/pricing',
        locales: <String>['en', 'fr', 'de'],
        defaultLocale: 'en',
      );
      expect(alternates, <String, String>{
        'en': 'https://example.com/pricing',
        'fr': 'https://example.com/fr/pricing',
        'de': 'https://example.com/de/pricing',
      });
    });

    test('the root route does not become a double slash', () {
      final Map<String, String> alternates = dvSeoAlternatesFor(
        siteUrl: 'https://example.com/',
        route: '/',
        locales: <String>['en', 'fr'],
        defaultLocale: 'en',
      );
      expect(alternates['en'], 'https://example.com/');
      expect(alternates['fr'], 'https://example.com/fr/');
    });

    test('a single locale yields nothing, so no lone hreflang is written', () {
      expect(
        dvSeoAlternatesFor(siteUrl: 'https://example.com', route: '/x', locales: <String>['en'], defaultLocale: 'en'),
        isEmpty,
      );
    });

    test('a locale prefix in the route is not doubled', () {
      // The prerender walks every generated route, including /fr/pricing
      // itself; its alternates are the same set as /pricing's.
      final Map<String, String> alternates = dvSeoAlternatesFor(
        siteUrl: 'https://example.com',
        route: '/fr/pricing',
        locales: <String>['en', 'fr'],
        defaultLocale: 'en',
      );
      expect(alternates['fr'], 'https://example.com/fr/pricing');
      expect(alternates['en'], 'https://example.com/pricing');
    });
  });
}
