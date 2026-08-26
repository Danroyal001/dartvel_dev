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
import 'package:dartvel_shelf/src/wintercg.dart';
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
}
