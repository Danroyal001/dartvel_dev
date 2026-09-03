// Page data on request: the Web Server Rendering pipeline past the manifest.
//
// The spec: request received, route resolved, page data resolved, auth and
// visibility checked, SEO and structured data generated, favicon selected,
// raw semantic text generated, Flutter bootstrap embedded. The manifest
// gave every request the title the build knew; a product page's title is
// the product's, known only when asked for. A resolver supplies it, and the
// mode says how it is waited for: awaited, cached, served stale and
// refreshed, streamed, or deferred to the client.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' show DVCacheAdapter;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html><head><title>App</title><link rel="icon" href="favicon.png"></head><body><div id="app"></div></body></html>
''';

const String _manifest = '''
{
  "siteUrl": "https://example.com",
  "routes": {
    "/": {"title": "Home", "text": ["Welcome in"]},
    "/products/:id": {"title": "A product", "text": []}
  }
}
''';

void main() {
  late Directory root;
  HttpServer? server;
  late String base;
  late List<DVPageRequest> asked;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_page_data_');
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(_manifest);
    asked = <DVPageRequest>[];
  });

  tearDown(() async {
    await server?.close(force: true);
    root.deleteSync(recursive: true);
  });

  Future<void> serve({
    required DVPageDataResolver resolver,
    DVPageDataMode mode = DVPageDataMode.await_,
    Duration cacheTtl = const Duration(seconds: 60),
    Duration? staleFor,
    bool streaming = false,
  }) async {
    server = await shelf_io.serve(
      dvWebServerHandler(
        webRoot: root.path,
        pageData: (DVPageRequest request) {
          asked.add(request);
          return resolver(request);
        },
        pageDataMode: mode,
        cacheTtl: cacheTtl,
        staleFor: staleFor,
        streaming: streaming,
      ),
      InternetAddress.loopbackIPv4,
      0,
    );
    base = 'http://${server!.address.host}:${server!.port}';
  }

  Future<HttpClientResponse> fetch(String path) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$base$path'));
    return request.close();
  }

  Future<String> get(String path) async {
    final response = await fetch(path);
    return response.transform(utf8.decoder).join();
  }

  DVPageData product(DVPageRequest r) => DVPageData(
        title: 'Product ${r.params['id']}',
        description: 'The best product ${r.params['id']}',
        image: 'https://cdn.example.com/${r.params['id']}.png',
        favicon: '/icons/product.png',
        text: <String>['Product ${r.params['id']}', 'In stock'],
        structuredData: <String, Object?>{'@type': 'Product', 'name': 'Product ${r.params['id']}'},
      );

  group('resolved on request', () {
    test('the page carries the data\'s title, description, image, text, structured data and favicon', () async {
      await serve(resolver: (DVPageRequest r) async => product(r));
      final String html = await get('/products/123');

      expect(html, contains('<title>Product 123</title>'));
      expect(html, contains('The best product 123'));
      expect(html, contains('https://cdn.example.com/123.png'));
      expect(html, contains('In stock'));
      expect(html, contains('<script type="application/ld+json">'));
      expect(html, contains('"@type":"Product"'));
      expect(html, contains('href="/icons/product.png"'));
      expect(html, isNot(contains('favicon.png')));
      expect(html, contains('<div id="app">'), reason: 'the Flutter bootstrap is still there');
    });

    test('the resolver is told the pattern, the parameters and the path', () async {
      await serve(resolver: (DVPageRequest r) async => product(r));
      await get('/products/42');
      expect(asked.single.pattern, '/products/:id');
      expect(asked.single.params, <String, String>{'id': '42'});
      expect(asked.single.path, '/products/42');
    });

    test('a route the resolver has nothing for keeps the manifest\'s page', () async {
      await serve(resolver: (DVPageRequest r) async => null);
      final String html = await get('/products/9');
      expect(html, contains('<title>A product</title>'));
    });

    test('untrusted data is escaped', () async {
      await serve(resolver: (DVPageRequest r) async => const DVPageData(title: '</title><script>x()</script>', text: <String>['<b>']));
      final String html = await get('/products/1');
      expect(html, isNot(contains('<script>x()')));
      expect(html, contains('&lt;b&gt;'));
    });
  });

  group('visibility', () {
    test('hidden is not found, and shows none of the data', () async {
      await serve(resolver: (DVPageRequest r) async => const DVPageData(title: 'Secret', visibility: DVPageVisibility.hidden));
      final HttpClientResponse response = await fetch('/products/7');
      expect(response.statusCode, 404);
      expect(await response.transform(utf8.decoder).join(), isNot(contains('Secret')));
    });

    test('unauthorized is 401 with the shell, so the client can sign the person in', () async {
      await serve(resolver: (DVPageRequest r) async => const DVPageData(title: 'Private', visibility: DVPageVisibility.unauthorized));
      final HttpClientResponse response = await fetch('/products/7');
      expect(response.statusCode, 401);
      final String html = await response.transform(utf8.decoder).join();
      expect(html, contains('<div id="app">'));
      expect(html, isNot(contains('Private')));
    });
  });

  group('modes', () {
    test('cache: the resolver is asked once within the ttl', () async {
      await serve(resolver: (DVPageRequest r) async => product(r), mode: DVPageDataMode.cache);
      await get('/products/1');
      await get('/products/1');
      await get('/products/2');
      expect(asked.map((DVPageRequest r) => r.path), <String>['/products/1', '/products/2']);
    });

    test('cache: past the ttl the resolver is asked again', () async {
      await serve(resolver: (DVPageRequest r) async => product(r), mode: DVPageDataMode.cache, cacheTtl: Duration.zero);
      await get('/products/1');
      await get('/products/1');
      expect(asked, hasLength(2));
    });

    test('stale-while-revalidate: a stale page is served at once and refreshed behind it', () async {
      var version = 0;
      await serve(
        resolver: (DVPageRequest r) async => DVPageData(title: 'v${++version}'),
        mode: DVPageDataMode.staleWhileRevalidate,
        cacheTtl: Duration.zero,
        // Stale at once, and servable stale while it is refreshed. A stale
        // window of nothing is a page that cannot be kept at all.
        staleFor: const Duration(minutes: 5),
      );
      expect(await get('/products/1'), contains('<title>v1</title>'));
      // Stale now; served as v1 while v2 is resolved.
      expect(await get('/products/1'), contains('<title>v1</title>'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await get('/products/1'), contains('<title>v2</title>'));
    });

    test('defer: the resolver is never asked; the client renders', () async {
      await serve(resolver: (DVPageRequest r) async => product(r), mode: DVPageDataMode.defer);
      final String html = await get('/products/1');
      expect(asked, isEmpty);
      expect(html, contains('<title>A product</title>'));
    });

    test('streaming: the response is chunked and still carries the data', () async {
      await serve(resolver: (DVPageRequest r) async => product(r), streaming: true);
      final HttpClientResponse response = await fetch('/products/5');
      expect(response.headers.value('transfer-encoding'), 'chunked');
      final String html = await response.transform(utf8.decoder).join();
      expect(html, contains('<title>Product 5</title>'));
      expect(html, contains('In stock'));
    });
  });

  test('the manifest carries the server settings from the declaration', () {
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{'/': 'Home'},
      text: const <String, List<String>>{},
      siteUrl: null,
      server: const DVWebServerSettings(pageDataMode: DVPageDataMode.staleWhileRevalidate, cacheTtl: Duration(seconds: 30), streaming: true),
    )) as Map<String, Object?>;
    expect(manifest['server'], <String, Object?>{
      'pageDataMode': 'stale-while-revalidate',
      'cacheTtlSeconds': 30,
      'staleForSeconds': 30,
      'streaming': true,
    });
    final DVWebServerSettings parsed = DVWebServerSettings.parse(<String, Object?>{'pageDataMode': 'cache', 'cache': 'redis', 'streaming': false});
    expect(parsed.pageDataMode, DVPageDataMode.cache);
    expect(parsed.cache, 'redis');
  });
  sharedPagesTests();
}

/// One store two servers share, standing in for redis.
class SharedStore implements DVCacheAdapter {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<int> purgeExpired() async => 0;
}

// Two servers behind one address is the ordinary deployment, and each was
// resolving every page for itself: `cache: redis` in the declaration was
// carried into the manifest and then ignored. Given a store, the second
// server serves what the first kept.
void sharedPagesTests() {
  test('a second server serves the page the first kept', () async {
    final Directory root = await Directory.systemTemp.createTemp('dartvel_shared_pages_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(_manifest);

    final SharedStore store = SharedStore();
    var asked = 0;
    Future<DVPageData?> resolver(DVPageRequest r) async {
      asked++;
      return DVPageData(title: 'Product $asked');
    }

    final List<HttpServer> servers = <HttpServer>[];
    for (var i = 0; i < 2; i++) {
      servers.add(await shelf_io.serve(
        dvWebServerHandler(
          webRoot: root.path,
          pageData: resolver,
          pageDataMode: DVPageDataMode.cache,
          pageStore: store,
        ),
        InternetAddress.loopbackIPv4,
        0,
      ));
    }
    addTearDown(() async {
      for (final HttpServer s in servers) {
        await s.close(force: true);
      }
    });

    Future<String> fetchFrom(HttpServer server) async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request =
          await client.getUrl(Uri.parse('http://${server.address.host}:${server.port}/products/9'));
      final HttpClientResponse response = await request.close();
      return response.transform(utf8.decoder).join();
    }

    expect(await fetchFrom(servers.first), contains('<title>Product 1</title>'));
    expect(await fetchFrom(servers.last), contains('<title>Product 1</title>'));
    expect(asked, 1, reason: 'the second server found the page in the shared store');
  });
}
