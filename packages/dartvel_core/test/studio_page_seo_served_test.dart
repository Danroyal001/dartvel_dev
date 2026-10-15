// A page built in Studio carries its own title, description, picture,
// indexing rule, canonical address and structured-data type. They were saved
// with the page and then served nowhere: every Studio page went out with the
// site's description, indexable, with no structured data, and not in the
// sitemap. What a page says about itself has to reach what a crawler reads.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _shell =
    '<!DOCTYPE html><html><head><title>Harbour</title></head>'
    '<body><div id="app"></div></body></html>';

Future<void> _publish(MemoryDVDatabaseAdapter database, Map<String, Object?> document) async {
  final DVRecordAdapter records = DVRecordAdapter.over(database);
  await records.ensure(dvStudioPagesShape);
  await records.insert(dvStudioPagesTable, <String, Object?>{
    'route': document['route'],
    'title': document['title'],
    'document': jsonEncode(document),
  });
}

Map<String, Object?> _page(String route, Map<String, Object?> seo) =>
    <String, Object?>{
      'route': route,
      'title': 'Autumn sale',
      'root': <String, Object?>{
        'id': 'page',
        'type': 'box',
        'layout': 'list',
        'children': <Object?>[
          <String, Object?>{
            'id': 'h',
            'type': 'text',
            'properties': <String, Object?>{'text': 'Everything half price'},
          },
        ],
      },
      ...seo,
    };

void main() {
  late MemoryDVDatabaseAdapter database;
  late DVPublishedPages published;

  setUp(() {
    database = MemoryDVDatabaseAdapter();
    published = DVPublishedPages(database: () => database);
  });

  test('a published page\'s own SEO is read back', () async {
    await _publish(database, _page('/sale', <String, Object?>{
      'description': 'Our autumn sale.',
      'image': '/_dartvel/media/sale.png',
      'robots': 'noindex, follow',
      'canonicalUrl': 'https://harbour.example/sale',
      'schemaType': 'Product',
      'sitemap': false,
    }));
    final DVPublishedPageSeo seo = (await published.seo('/sale'))!;
    expect(seo.title, 'Autumn sale');
    expect(seo.description, 'Our autumn sale.');
    expect(seo.robots, 'noindex, follow');
    expect(seo.canonical, 'https://harbour.example/sale');
    expect(seo.schemaType, 'Product');
    expect(seo.inSitemap, isFalse);
    expect(seo.text, <String>['Everything half price']);
    expect(await published.seo('/nothing'), isNull);
  });

  test('the served page carries what the page says about itself', () {
    final String html = dvRenderPublishedPage(
      shell: _shell,
      path: '/sale',
      seo: const DVPublishedPageSeo(
        title: 'Autumn sale',
        description: 'Our autumn sale.',
        image: '/_dartvel/media/sale.png',
        robots: 'noindex, follow',
        canonical: 'https://harbour.example/sale',
        schemaType: 'Product',
        text: <String>['Everything half price'],
      ),
      siteUrl: 'https://harbour.example',
      siteName: 'Harbour',
    );
    expect(html, contains('<title>Autumn sale</title>'));
    expect(html, contains('<meta name="description" content="Our autumn sale.">'));
    expect(html, contains('<meta name="robots" content="noindex, follow">'));
    expect(html, contains('<link rel="canonical" href="https://harbour.example/sale">'));
    expect(html, contains('https://harbour.example/_dartvel/media/sale.png'));
    expect(html, contains('"@type":"Product"'));
    expect(html, contains('Everything half price'));
  });

  test('a page without its own description falls back to the site\'s', () {
    final String html = dvRenderPublishedPage(
      shell: _shell,
      path: '/about',
      seo: const DVPublishedPageSeo(title: 'About'),
      siteUrl: 'https://harbour.example',
      siteDescription: 'Boats, for hire.',
    );
    expect(html, contains('content="Boats, for hire."'));
    expect(html, contains('<link rel="canonical" href="https://harbour.example/about">'));
    expect(html, isNot(contains('name="robots"')));
  });

  test('what a page says about itself cannot write markup', () {
    final String html = dvRenderPublishedPage(
      shell: _shell,
      path: '/x',
      seo: const DVPublishedPageSeo(
        title: '</title><script>alert(1)</script>',
        description: '"><script>alert(2)</script>',
        schemaType: '</script><script>alert(3)</script>',
        text: <String>['<img src=x onerror=alert(4)>'],
      ),
    );
    expect(html, isNot(contains('<script>alert')));
    expect(html, isNot(contains('<img src=x')));
  });

  test('the sitemap lists published pages that ask to be listed', () async {
    await _publish(database, _page('/sale', <String, Object?>{}));
    await _publish(database, _page('/hidden', <String, Object?>{'sitemap': false}));
    await _publish(database, _page('/private', <String, Object?>{'robots': 'noindex'}));
    await _publish(database, _page('/q&a', <String, Object?>{}));

    const String built =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        '<url><loc>https://harbour.example/</loc></url>\n'
        '</urlset>\n';
    final String xml = dvSitemapWithRoutes(
      built,
      await published.sitemapRoutes(),
      siteUrl: 'https://harbour.example',
    );
    expect(xml, contains('<loc>https://harbour.example/</loc>'));
    expect(xml, contains('<loc>https://harbour.example/sale</loc>'));
    expect(xml, contains('<loc>https://harbour.example/q&amp;a</loc>'));
    expect(xml, isNot(contains('/hidden')));
    expect(xml, isNot(contains('/private')));
    expect(xml.indexOf('/sale'), lessThan(xml.indexOf('</urlset>')));

    // A build that wrote no sitemap still gets one.
    expect(
      dvSitemapWithRoutes(null, <String>['/sale'], siteUrl: 'https://harbour.example'),
      allOf(contains('<urlset'), contains('<loc>https://harbour.example/sale</loc>')),
    );
  });
}
