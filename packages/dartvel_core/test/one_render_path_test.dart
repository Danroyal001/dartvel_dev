// One render path for every page: a page backed by data -- a data model's
// page, a page Studio published -- goes through the same function as every
// other route, dvRenderRoutePage.
//
// It used to go through a second one, dvRenderPage -> dvRenderRoute, which
// passed no hreflang alternates and no robots to the head and wrote its
// JSON-LD in another place. A model page on a multilingual site had its
// language links and its robots meta in the static build and lost both when
// the web-server binary rendered the same URL, and a page rendered one way
// then the other could carry two structured-data blocks.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html><html><head><title>Shop</title>'
    '<link rel="icon" href="favicon.png"></head><body></body></html>';

/// What the build wrote into the manifest for the route `/products/:id`.
const DVRoutePage manifestPage = DVRoutePage(
  route: '/products/:id',
  title: 'Product',
  siteUrl: 'https://shop.example',
  siteName: 'Shop',
  alternates: <String, String>{
    'en': 'https://shop.example/products/7',
    'fr': 'https://shop.example/fr/products/7',
  },
  defaultAlternate: 'https://shop.example/products/7',
  robots: 'max-image-preview:large',
  schemaType: 'Product',
);

const DVPageData data = DVPageData(
  title: 'Blue mug',
  description: 'A mug, blue.',
  image: '/img/mug.png',
  text: <String>['Blue mug', 'Holds tea.'],
  structuredData: <String, Object?>{'@context': 'https://schema.org', '@type': 'Product', 'name': 'Blue mug'},
);

String rendered() => dvRenderPage(
      shell: shell,
      path: '/products/7',
      data: data,
      siteUrl: 'https://shop.example',
      siteName: 'Shop',
      route: manifestPage,
    );

void main() {
  test('a data-backed page keeps the route\'s hreflang alternates and robots', () {
    final String html = rendered();
    expect(html, contains('hreflang="fr"'));
    expect(html, contains('https://shop.example/fr/products/7'));
    expect(html, contains('hreflang="x-default"'));
    expect(html, contains('name="robots" content="max-image-preview:large"'));
  });

  test('its own title, description and image win over the route\'s', () {
    final String html = rendered();
    expect(html, contains('<title>Blue mug</title>'));
    expect(html, contains('A mug, blue.'));
    expect(html, contains('https://shop.example/img/mug.png'));
  });

  test('one structured-data block, the page\'s own', () {
    final String html = rendered();
    expect('application/ld+json'.allMatches(html).length, 1);
    expect(html, contains('"name":"Blue mug"'));
  });

  test('it is the same bytes as the one render function given the same page', () {
    final String direct = dvRenderRoutePage(
      shell,
      DVRoutePage(
        route: '/products/7',
        title: 'Blue mug',
        description: 'A mug, blue.',
        image: '/img/mug.png',
        siteUrl: 'https://shop.example',
        siteName: 'Shop',
        alternates: manifestPage.alternates,
        defaultAlternate: manifestPage.defaultAlternate,
        robots: manifestPage.robots,
        schemaType: manifestPage.schemaType,
        text: data.text,
        structuredData: data.structuredData,
      ),
    );
    expect(rendered(), direct);
  });

  test('with no manifest entry the data alone still renders the page', () {
    final String html = dvRenderPage(
      shell: shell,
      path: '/products/7',
      data: data,
      siteUrl: 'https://shop.example',
      siteName: 'Shop',
    );
    expect(html, contains('<title>Blue mug</title>'));
    expect('application/ld+json'.allMatches(html).length, 1);
  });
}
