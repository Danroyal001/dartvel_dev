// The page pipeline's pure parts, where every server can share them.
//
// Route parameters, the page assembled from a route's data, the cache the
// modes live in, and the page data a model row becomes. The preview server
// and the generated backend's server both render through these; a test
// here is a test of both.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html><html><head><title>App</title><link rel="icon" href="favicon.png"></head><body><div id="app"></div></body></html>';

void main() {
  group('route parameters', () {
    test('a literal matches itself with no parameters', () {
      expect(dvRouteParams('/docs', '/docs'), <String, String>{});
      expect(dvRouteParams('/docs', '/features'), isNull);
    });
    test('a pattern fills its parameters from the path, decoded', () {
      expect(dvRouteParams('/products/:id', '/products/12%20a'), <String, String>{'id': '12 a'});
      expect(dvRouteParams('/products/:id', '/products/1/x'), isNull);
    });
  });

  group('the page from a route\'s data', () {
    test('carries the head, the text, the structured data and the favicon', () {
      final String html = dvRenderPage(
        shell: shell,
        path: '/products/1',
        data: const DVPageData(
          title: 'Product 1',
          description: 'A fine product',
          image: '/img/1.png',
          favicon: '/icons/p.png',
          text: <String>['Product 1', 'In stock'],
          structuredData: <String, Object?>{'@type': 'Product', 'name': '</script>'},
        ),
        siteUrl: 'https://example.com',
      );
      expect(html, contains('<title>Product 1</title>'));
      expect(html, contains('content="A fine product"'));
      expect(html, contains('https://example.com/img/1.png'));
      expect(html, contains('<link rel="canonical" href="https://example.com/products/1">'));
      expect(html, contains('<p>In stock</p>'));
      expect(html, contains('href="/icons/p.png"'));
      expect(html, isNot(contains('favicon.png')));
      expect(html, contains('<script type="application/ld+json">'));
      expect(html, contains(r'<\/script>'), reason: 'a closing tag inside the JSON cannot end the script');
      expect(html, contains('<div id="app">'));
    });

    test('is the same page when rendered twice', () {
      const DVPageData data = DVPageData(title: 'T', favicon: '/f.png', structuredData: <String, Object?>{'a': 1}, text: <String>['x']);
      final String once = dvRenderPage(shell: shell, path: '/', data: data);
      final String twice = dvRenderPage(shell: once, path: '/', data: data);
      expect(twice, once);
    });
  });

  group('the cache the modes live in', () {
    late List<String> asked;
    late int now;
    late DVPageDataCache cache;
    Future<DVPageData?> resolver(DVPageRequest r) async {
      asked.add(r.path);
      return DVPageData(title: 'v${asked.length}');
    }

    setUp(() {
      asked = <String>[];
      now = 0;
      cache = DVPageDataCache(ttl: const Duration(seconds: 10), now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000));
    });

    DVPageRequest request() => const DVPageRequest(path: '/p/1', pattern: '/p/:id', params: <String, String>{'id': '1'});

    test('await asks every time', () async {
      await cache.resolve(request(), resolver, DVPageDataMode.await_);
      await cache.resolve(request(), resolver, DVPageDataMode.await_);
      expect(asked, hasLength(2));
    });

    test('cache asks once within the ttl and again after it', () async {
      await cache.resolve(request(), resolver, DVPageDataMode.cache);
      now = 5;
      expect((await cache.resolve(request(), resolver, DVPageDataMode.cache))!.title, 'v1');
      now = 11;
      expect((await cache.resolve(request(), resolver, DVPageDataMode.cache))!.title, 'v2');
    });

    test('stale-while-revalidate serves the stale page and refreshes behind it', () async {
      await cache.resolve(request(), resolver, DVPageDataMode.staleWhileRevalidate);
      now = 11;
      expect((await cache.resolve(request(), resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'v1');
      await Future<void>.delayed(Duration.zero);
      expect((await cache.resolve(request(), resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'v2');
    });

    test('defer never asks', () async {
      expect(await cache.resolve(request(), resolver, DVPageDataMode.defer), isNull);
      expect(asked, isEmpty);
    });
  });

  group('a model row as page data', () {
    const DVModelPageSpec spec = DVModelPageSpec(
      model: 'Product',
      route: '/products/:slug',
      param: 'slug',
      table: 'products',
      keyField: 'slug',
      titleField: 'name',
      contentFields: <String>['summary', 'body'],
      imageField: 'photo',
      publishedField: 'published',
    );

    test('takes the title, the longest content, the image, and structured data from the row', () {
      final DVPageData data = dvModelPageData(spec, <String, Object?>{
        'slug': 'lamp', 'name': 'Desk lamp', 'summary': 'Short', 'body': 'A much longer description', 'photo': '/p/lamp.png', 'published': 1,
      });
      expect(data.title, 'Desk lamp');
      expect(data.description, 'A much longer description');
      expect(data.text, <String>['Desk lamp', 'A much longer description']);
      expect(data.image, '/p/lamp.png');
      expect(data.structuredData, containsPair('@type', 'Thing'));
      expect(data.structuredData, containsPair('name', 'Desk lamp'));
      expect(data.visibility, DVPageVisibility.public);
    });

    test('the schema.org type is the one the model declares, and Thing when it declares none', () {
      // A search engine acts on the label. A Person labelled a Product
      // because the model is called Customer is worse than the honest
      // general type, so it is declared rather than guessed from the name.
      const DVModelPageSpec typed = DVModelPageSpec(
        model: 'Product',
        route: '/products/:slug',
        param: 'slug',
        table: 'products',
        keyField: 'slug',
        titleField: 'name',
        schemaType: 'Product',
      );
      expect(dvModelPageData(typed, <String, Object?>{'slug': 'lamp', 'name': 'Desk lamp'}).structuredData,
          containsPair('@type', 'Product'));
      expect(dvModelPageData(spec, <String, Object?>{'slug': 'lamp', 'name': 'Desk lamp'}).structuredData,
          containsPair('@type', 'Thing'));
    });

    test('an unpublished row is hidden', () {
      final DVPageData data = dvModelPageData(spec, <String, Object?>{'slug': 'x', 'name': 'Draft', 'published': 0});
      expect(data.visibility, DVPageVisibility.hidden);
    });

    test('the resolver finds the row by the route\'s parameter, and hides a row that is not there', () async {
      final List<List<Object?>> queries = <List<Object?>>[];
      final DVPageDataResolver resolve = dvModelPageResolver(<DVModelPageSpec>[spec], (String sql, List<Object?> params) async {
        queries.add(<Object?>[sql, ...params]);
        return params.first == 'lamp' ? <Map<String, Object?>>[<String, Object?>{'slug': 'lamp', 'name': 'Desk lamp', 'published': 1}] : <Map<String, Object?>>[];
      });
      final DVPageData? found = await resolve(const DVPageRequest(path: '/products/lamp', pattern: '/products/:slug', params: <String, String>{'slug': 'lamp'}));
      expect(found!.title, 'Desk lamp');
      expect(queries.single.first, 'SELECT * FROM products WHERE slug = ?');
      final DVPageData? missing = await resolve(const DVPageRequest(path: '/products/nope', pattern: '/products/:slug', params: <String, String>{'slug': 'nope'}));
      expect(missing!.visibility, DVPageVisibility.hidden);
      expect(await resolve(const DVPageRequest(path: '/docs', pattern: '/docs', params: <String, String>{})), isNull);
    });
  });
}
