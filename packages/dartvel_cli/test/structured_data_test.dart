// Structured data, which the spec lists under SEO and no page carried.
//
// dvSeoHead has always written OpenGraph and Twitter tags. Neither tells a
// search engine what the page *is*: og:type is "website" for every page on
// every site. Schema.org is the vocabulary that does, and it is what produces
// a site name in results, a breadcrumb trail under a link, and a sitelinks
// search box.
import 'dart:convert';

import 'package:dartvel_cli/src/build/structured_data.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> parse(String html) {
  final matches = RegExp(
    r'<script type="application/ld\+json">(.*?)</script>',
    dotAll: true,
  ).allMatches(html);
  return <Map<String, Object?>>[
    for (final Match m in matches)
      jsonDecode(m.group(1)!) as Map<String, Object?>,
  ];
}

void main() {
  group('the home page', () {
    final blocks = parse(dvStructuredData(
      route: '/',
      title: 'Dartvel — Flutter, full stack',
      description: 'A full-stack platform.',
      siteName: 'Dartvel',
      siteUrl: 'https://dartvel.dev',
      image: 'https://dartvel.dev/icons/Icon-512.png',
    ));

    test('it declares the site itself', () {
      // WebSite belongs on the root and nowhere else. Repeating it on every
      // page tells a crawler the site begins again at each URL.
      expect(blocks.map((b) => b['@type']), contains('WebSite'));
    });

    test('the site is named and located', () {
      final site = blocks.firstWhere((b) => b['@type'] == 'WebSite');

      expect(site['name'], 'Dartvel');
      expect(site['url'], 'https://dartvel.dev');
      expect(site['@context'], 'https://schema.org');
    });

    test('there is no breadcrumb, because there is no trail', () {
      expect(blocks.map((b) => b['@type']), isNot(contains('BreadcrumbList')));
    });
  });

  group('an inner page', () {
    final blocks = parse(dvStructuredData(
      route: '/docs',
      title: 'Documentation — Dartvel',
      description: 'From nothing to a running app.',
      siteName: 'Dartvel',
      siteUrl: 'https://dartvel.dev',
    ));

    test('it is a page, not the site', () {
      expect(blocks.map((b) => b['@type']), contains('WebPage'));
      expect(blocks.map((b) => b['@type']), isNot(contains('WebSite')));
    });

    test('the page points back at the site it belongs to', () {
      final page = blocks.firstWhere((b) => b['@type'] == 'WebPage');

      expect((page['isPartOf']! as Map<String, Object?>)['@type'], 'WebSite');
      expect(page['url'], 'https://dartvel.dev/docs');
      expect(page['name'], 'Documentation — Dartvel');
    });

    test('it carries a trail back to the root', () {
      final crumbs = blocks.firstWhere((b) => b['@type'] == 'BreadcrumbList');
      final items = crumbs['itemListElement']! as List<Object?>;

      expect(items, hasLength(2));
      expect((items.first as Map<String, Object?>)['name'], 'Home');
      expect((items.first as Map<String, Object?>)['position'], 1);
      expect((items.last as Map<String, Object?>)['position'], 2);
    });
  });

  group('a nested page', () {
    test('every segment is a step in the trail', () {
      final blocks = parse(dvStructuredData(
        route: '/guides/forms',
        title: 'Forms',
        siteName: 'Dartvel',
        siteUrl: 'https://dartvel.dev',
      ));
      final crumbs = blocks.firstWhere((b) => b['@type'] == 'BreadcrumbList');
      final items = (crumbs['itemListElement']! as List<Object?>)
          .cast<Map<String, Object?>>();

      expect(items.map((i) => i['name']), <String>['Home', 'Guides', 'Forms']);
      expect(items.map((i) => i['item']), <String>[
        'https://dartvel.dev',
        'https://dartvel.dev/guides',
        'https://dartvel.dev/guides/forms',
      ]);
    });
  });

  group('what it refuses to emit', () {
    test('no site URL means no structured data at all', () {
      // Every identifier in this vocabulary is an absolute URL. Emitting it
      // with relative ones produces a block that validates and describes
      // nothing.
      expect(dvStructuredData(route: '/docs', title: 'T', siteName: 'D'),
          isEmpty);
    });

    test('markup in a name cannot escape the script element', () {
      // A </script> inside JSON ends the element early and everything after
      // it becomes markup in the page. Checked on the site name, because the
      // root block is built from that and not from the page title -- the
      // first version of this test put the payload in the title and proved
      // nothing.
      final html = dvStructuredData(
        route: '/',
        title: 'T',
        siteName: 'A </script><img src=x> B',
        siteUrl: 'https://example.com',
      );

      expect(html, isNot(contains('</script><img')));
      expect(html, contains(r'<\/script>'));
    });

    test('markup in a page title cannot either', () {
      final html = dvStructuredData(
        route: '/docs',
        title: 'A </script><img src=x> B',
        siteName: 'D',
        siteUrl: 'https://example.com',
      );

      expect(html, isNot(contains('</script><img')));
      expect(html, contains(r'<\/script>'));
    });
  });
}
