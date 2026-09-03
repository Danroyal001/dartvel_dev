// The SSR fallback, which injects prerendered metadata into the served page.
//
// Two things it did are worth a test each. It interpolated a prerendered
// title and body straight into HTML, and those values come from prerendering
// model pages -- so their content is whatever is in the database. And it wrote
// the finished page as `html.codeUnits`, which is UTF-16, so anything outside
// ASCII was served as the wrong bytes. That one is invisible until a page
// title has an accent in it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/src/ssr_helper.dart';
// Three names, which is what this test uses. The show list named Body,
// URLPattern and Router as well, and the main barrel stopped exporting them
// when the wire surface moved to http.dart -- so the list was stale and the
// analyzer said so, while nothing here ever referenced them.
import 'package:dartvel_core/dartvel.dart'
    show DVCacheAdapter, DVPageData, DVPageDataCache, DVPageRequest, DVPageVisibility, Headers, Request, Response;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Request get(String path) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<List<int>> bytesOf(Response response) async {
  final chunks = <int>[];
  await for (final List<int> chunk in response.body!.stream) {
    chunks.addAll(chunk);
  }
  return chunks;
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel-ssr-');
    File(p.join(root.path, 'index.html')).writeAsStringSync(
        '<html><head><title>Default</title></head><body></body></html>');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void prerender(String route, Map<String, Object?> meta) {
    final dir = Directory(p.join(root.path, 'prerender', route))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'meta.json')).writeAsStringSync(jsonEncode(meta));
  }

  group('serving the page', () {
    test('a missing index is a 404 rather than an empty page', () async {
      final empty = Directory.systemTemp.createTempSync('dartvel-ssr-none-');
      addTearDown(() => empty.deleteSync(recursive: true));

      final response = await handleSsrFallback(get('/'), empty.path);

      expect(response.status, 404);
    });

    test('a route with no prerender is served unchanged', () async {
      final response = await handleSsrFallback(get('/nothing'), root.path);

      expect(utf8.decode(await bytesOf(response)), contains('<title>Default'));
    });

    test('a prerendered title replaces the default', () async {
      prerender('about', <String, Object?>{'title': 'About us'});

      final response = await handleSsrFallback(get('/about'), root.path);

      expect(utf8.decode(await bytesOf(response)), contains('<title>About us'));
    });
  });

  group('bytes on the wire', () {
    // codeUnits is UTF-16. For 'é' it emits 233, which is not a valid UTF-8
    // lead byte, and for anything above U+00FF it emits a value that is not a
    // byte at all. ASCII pages look fine, which is why this survives.
    test('a non-ASCII title survives the round trip', () async {
      prerender('cafe', <String, Object?>{'title': 'Café Münster'});

      final response = await handleSsrFallback(get('/cafe'), root.path);

      expect(utf8.decode(await bytesOf(response)), contains('Café Münster'));
    });

    test('characters outside the Latin range survive too', () async {
      prerender('zh', <String, Object?>{'title': '中文标题'});

      final bytes = await bytesOf(await handleSsrFallback(get('/zh'), root.path));

      expect(bytes.every((int b) => b >= 0 && b <= 255), isTrue,
          reason: 'a byte stream cannot carry UTF-16 code units');
      expect(utf8.decode(bytes), contains('中文标题'));
    });

    test('the response says which encoding it used', () async {
      final response = await handleSsrFallback(get('/'), root.path);

      expect(response.headers.get('content-type'), contains('charset=utf-8'));
    });
  });

  group('untrusted prerendered values', () {
    // meta.json is written by prerendering model pages, so a title is
    // whatever is in the database. Interpolated raw, a title can close the
    // title element and open a script.
    test('a title cannot break out of the title element', () async {
      prerender('evil', <String, Object?>{
        'title': '</title><script>alert(1)</script><title>',
      });

      final html =
          utf8.decode(await bytesOf(await handleSsrFallback(get('/evil'), root.path)));

      // The property is that no markup forms. HtmlEscape also escapes the
      // slash, so the closing tag reads &lt;&#47;title&gt; -- checking for a
      // particular entity spelling would test the escaper, not the safety.
      expect(html, isNot(contains('<script')));
      // The page still has exactly one title element -- the injected value
      // did not close it and open another.
      expect('<title>'.allMatches(html).length, 1);
      expect(html, contains('&lt;'));
    });

    test('prerendered content cannot inject markup', () async {
      prerender('post', <String, Object?>{
        'content': '<img src=x onerror=alert(1)>',
      });

      final html =
          utf8.decode(await bytesOf(await handleSsrFallback(get('/post'), root.path)));

      // onerror=alert(1) survives as text, which is harmless: it is inside
      // an escaped string, not an attribute of a tag that exists.
      expect(html, isNot(contains('<img')));
      expect(html, contains('&lt;img'));
    });

    test('ordinary punctuation still reads correctly', () async {
      // Escaping must not mangle the common case into entity soup.
      prerender('quote', <String, Object?>{'title': "Dartvel's \"guide\" & more"});

      final html =
          utf8.decode(await bytesOf(await handleSsrFallback(get('/quote'), root.path)));

      expect(html, contains('&amp;'));
      expect(html, isNot(contains('&amp;amp;')),
          reason: 'escaping twice turns & into &amp;amp;');
    });

    test('a route cannot escape the prerender directory', () async {
      // The route becomes a path segment. A traversal would read any
      // meta.json on the disk.
      final outside = Directory(p.join(root.path, 'secret'))..createSync();
      File(p.join(outside.path, 'meta.json'))
          .writeAsStringSync(jsonEncode(<String, Object?>{'title': 'LEAKED'}));

      final html = utf8.decode(await bytesOf(
          await handleSsrFallback(get('/../secret'), root.path)));

      expect(html, isNot(contains('LEAKED')));
    });
  });
  manifestTests();
  sharedAndDeclaredTests();
}

// With a web-server manifest beside the shell, the fallback is the page
// pipeline: the route's title and text from the manifest, and the page's
// data from the resolver the backend was started with, by the declared
// mode. The prerender path stays for builds that wrote one.
void manifestTests() {
  group('with a manifest', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel-ssr-manifest-');
      File(p.join(root.path, 'index.html')).writeAsStringSync(
          '<html><head><title>Default</title></head><body><div id="app"></div></body></html>');
      File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
        'siteUrl': 'https://example.com',
        'server': <String, Object?>{'pageDataMode': 'await'},
        'routes': <String, Object?>{
          '/': <String, Object?>{'title': 'Home', 'text': <String>['Welcome']},
          '/products/:id': <String, Object?>{'title': 'A product', 'text': <String>[]},
        },
      }));
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a manifest route is served with its title and text', () async {
      final response = await handleSsrFallback(get('/'), root.path);
      final String html = utf8.decode(await bytesOf(response));
      expect(html, contains('<title>Home</title>'));
      expect(html, contains('Welcome'));
      expect(html, contains('<link rel="canonical" href="https://example.com">'));
    });

    test('a route with data is the page from the data', () async {
      final response = await handleSsrFallback(
        get('/products/7'),
        root.path,
        pageData: (DVPageRequest r) async => DVPageData(title: 'Product ${r.params['id']}', text: const <String>['In stock']),
      );
      final String html = utf8.decode(await bytesOf(response));
      expect(html, contains('<title>Product 7</title>'));
      expect(html, contains('In stock'));
    });

    test('hidden data is 404 without the data', () async {
      final response = await handleSsrFallback(
        get('/products/7'),
        root.path,
        pageData: (DVPageRequest r) async => const DVPageData(title: 'Secret', visibility: DVPageVisibility.hidden),
      );
      expect(response.status, 404);
      expect(utf8.decode(await bytesOf(response)), isNot(contains('Secret')));
    });

    test('the declared cache mode keeps the page between requests', () async {
      File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
        'server': <String, Object?>{'pageDataMode': 'cache', 'cacheTtlSeconds': 60},
        'routes': <String, Object?>{'/products/:id': <String, Object?>{'title': 'A product', 'text': <String>[]}},
      }));
      var asked = 0;
      final DVPageDataCache cache = DVPageDataCache(ttl: const Duration(seconds: 60));
      Future<DVPageData?> resolver(DVPageRequest r) async {
        asked++;
        return DVPageData(title: 'Product $asked');
      }
      await handleSsrFallback(get('/products/1'), root.path, pageData: resolver, cache: cache);
      final response = await handleSsrFallback(get('/products/1'), root.path, pageData: resolver, cache: cache);
      expect(asked, 1);
      expect(utf8.decode(await bytesOf(response)), contains('<title>Product 1</title>'));
    });
  });
}

/// One store two backends share, standing in for redis.
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

// The manifest says how long a page is kept and where. Both were ignored
// here: the fallback built one cache with the default ttl and kept every
// page in the process, so two backends resolved everything twice and a
// declaration of five minutes lasted sixty seconds.
void sharedAndDeclaredTests() {
  group('the kept pages', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel-ssr-shared-');
      File(p.join(root.path, 'index.html'))
          .writeAsStringSync('<html><head><title>Default</title></head><body><div id="app"></div></body></html>');
      File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
        'server': <String, Object?>{'pageDataMode': 'cache', 'cacheTtlSeconds': 300},
        'routes': <String, Object?>{'/products/:id': <String, Object?>{'title': 'A product', 'text': <String>[]}},
      }));
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a second backend serves what the first kept', () async {
      final SharedStore store = SharedStore();
      var asked = 0;
      Future<DVPageData?> resolver(DVPageRequest r) async {
        asked++;
        return DVPageData(title: 'Product $asked');
      }

      final response = await handleSsrFallback(get('/products/1'), root.path,
          pageData: resolver, pageStore: store, cache: DVPageDataCache(ttl: const Duration(minutes: 5), shared: store));
      expect(utf8.decode(await bytesOf(response)), contains('<title>Product 1</title>'));

      // A different backend: its own cache object, the same store.
      final second = await handleSsrFallback(get('/products/1'), root.path,
          pageData: resolver, pageStore: store, cache: DVPageDataCache(ttl: const Duration(minutes: 5), shared: store));
      expect(utf8.decode(await bytesOf(second)), contains('<title>Product 1</title>'));
      expect(asked, 1, reason: 'the second backend found the page in the shared store');
    });

    test('the declaration says how long a page is kept, not the default', () async {
      // Kept for five minutes by the manifest. A cache built with the
      // default sixty seconds would resolve again at two minutes.
      final SharedStore store = SharedStore();
      var asked = 0;
      Future<DVPageData?> resolver(DVPageRequest r) async {
        asked++;
        return DVPageData(title: 'Product $asked');
      }

      await handleSsrFallback(get('/products/1'), root.path, pageData: resolver, pageStore: store);
      final Map<String, Object?> kept =
          jsonDecode('${store.values.values.first}') as Map<String, Object?>;
      // Written back an hour ago: still fresh under a five-minute ttl only
      // if the declaration was read.
      kept['at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String();
      store.values.updateAll((String key, Object? value) => jsonEncode(kept));

      final response = await handleSsrFallback(get('/products/1'), root.path, pageData: resolver, pageStore: store);

      expect(utf8.decode(await bytesOf(response)), contains('<title>Product 1</title>'));
      expect(asked, 1);
    });
  });
}
