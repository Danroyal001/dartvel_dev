// What a statically generated model page says it is.
//
// The same shape the favicon was in. `@DVModel(schemaType: 'Product')` is
// parsed, written into the page spec, and read by the web server's resolver
// -- and by nothing on the static side, so `dartvel build web` announced
// every product, recipe and job posting as a plain WebPage. That type is what
// a rich result is keyed off, so the declaration bought nothing on exactly
// the deployment that most needs it, and the page validated cleanly while
// saying the wrong thing.
import 'package:dartvel_cli/src/build/static_generation.dart';
import 'package:dartvel_cli/src/build/structured_data.dart';
import 'package:test/test.dart';

const String generated = '''
const List<DVModelPageSpec> dartvelModelPages = <DVModelPageSpec>[
  DVModelPageSpec(
    model: 'Product',
    route: '/products/:slug',
    keyField: 'slug',
    schemaType: 'Product',
    favicon: null,
  ),
  DVModelPageSpec(
    model: 'Article',
    route: '/articles/:slug',
    keyField: 'slug',
    schemaType: null,
    favicon: null,
  ),
];
''';

void main() {
  group('the declared type reaches the page', () {
    test('a model page announces what the model said it is', () {
      final String ld = dvStructuredData(
        route: '/products/pro-kit',
        title: 'Pro Kit',
        siteName: 'Shop',
        siteUrl: 'https://shop.example.com',
        schemaType: 'Product',
      );

      expect(ld, contains('"@type": "Product"'));
      expect(ld, isNot(contains('"@type": "WebPage"')));
    });

    test('the breadcrumb trail is still there', () {
      // The type replaces what the page calls itself, not the trail that
      // says where it sits. Dropping the breadcrumbs would trade one rich
      // result for another.
      final String ld = dvStructuredData(
        route: '/products/pro-kit',
        title: 'Pro Kit',
        siteName: 'Shop',
        siteUrl: 'https://shop.example.com',
        schemaType: 'Product',
      );

      expect(ld, contains('BreadcrumbList'));
    });

    test('a page with no declared type is still a WebPage', () {
      final String ld = dvStructuredData(
        route: '/about',
        title: 'About',
        siteName: 'Shop',
        siteUrl: 'https://shop.example.com',
      );

      expect(ld, contains('"@type": "WebPage"'));
    });

    test('the root stays the site, whatever a model claims', () {
      // WebSite belongs to the root and to nothing else. A model page
      // mounted at / that overwrote it would tell a crawler the site has no
      // home.
      final String ld = dvStructuredData(
        route: '/',
        title: 'Shop',
        siteName: 'Shop',
        siteUrl: 'https://shop.example.com',
        schemaType: 'Product',
      );

      expect(ld, contains('"@type": "WebSite"'));
    });
  });

  group('reading the types the models declared', () {
    test('a declared type comes back under the model\'s route', () {
      expect(
        dvModelPageSchemaTypes(generated),
        containsPair('/products/:slug', 'Product'),
      );
    });

    test('a model that declared none is absent', () {
      expect(dvModelPageSchemaTypes(generated).containsKey('/articles/:slug'),
          isFalse);
    });
  });
}
