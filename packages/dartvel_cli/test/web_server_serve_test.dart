// The server half of `dartvel build web-server`.
//
// That target writes dartvel_routes.json instead of prerendering a file per
// route, and dvServeRoute knows how to build a page from it. Nothing called
// dvServeRoute: the manifest was written, unit-tested, and never read, so the
// target produced a description of a site nobody served. `dartvel preview`
// fell through to the static files that the same build had just deleted.
//
// These drive a real HTTP server over a real request, because the whole point
// of the target is that the page is assembled when it is asked for.
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html><head><title>App</title></head><body><div id="app"></div></body></html>
''';

const String _manifest = '''
{
  "siteUrl": "https://example.com",
  "routes": {
    "/": {"title": "Home", "text": ["Welcome in"]},
    "/docs": {"title": "Documentation", "text": ["Read the docs", "Second line"]},
    "/post/:id": {"title": "A post", "text": ["Post body"]}
  }
}
''';

void main() {
  late Directory root;
  late HttpServer server;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_web_server_');
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(_manifest);
    File(p.join(root.path, 'main.dart.js')).writeAsStringSync('console.log(1)');

    server = await shelf_io.serve(
      dvWebServerHandler(webRoot: root.path),
      InternetAddress.loopbackIPv4,
      0,
    );
    base = 'http://${server.address.host}:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  Future<String> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$base$path'));
      final response = await request.close();
      // Awaited before the client is closed. Returning the future and closing
      // in `finally` tears the socket down mid-body and reports
      // "Connection closed while receiving data" as though the server did it.
      return await response.transform(const SystemEncoding().decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  test('a route is served with its own title', () async {
    expect(await get('/docs'), contains('<title>Documentation</title>'));
  });

  test('a route is served with its own crawler-visible text', () async {
    final body = await get('/docs');

    expect(body, contains('<noscript>'));
    expect(body, contains('Read the docs'));
    expect(body, contains('Second line'));
  });

  test('one route does not leak into another', () async {
    // The failure a single shared shell produces: every page correct in the
    // file and identical over the wire.
    expect(await get('/'), contains('<title>Home</title>'));
    expect(await get('/'), isNot(contains('Read the docs')));
  });

  test('a parameterised route canonicalises to the URL asked for', () async {
    // Not to /post/:id, which is not a URL anyone can visit.
    final body = await get('/post/hello-world');

    expect(body, contains('<title>A post</title>'));
    expect(body, contains('https://example.com/post/hello-world'));
    expect(body, isNot(contains('/post/:id')));
  });

  test('assets are still served from disk', () async {
    expect(await get('/main.dart.js'), contains('console.log(1)'));
  });

  test('an unknown path still returns the application shell', () async {
    // A single-page app owns its own 404s; returning the server's would show
    // a blank page where the app has a not-found route.
    expect(await get('/nothing-here'), contains('<div id="app">'));
  });

  test('an unknown path keeps the site title rather than showing the URL',
      () async {
    // dvServeRoute falls back to siteName and then to the path itself, so
    // with no site name a missing route titled the tab "/nothing-here". The
    // shell already carries the site's own title; that is the fallback.
    final body = await get('/nothing-here');

    expect(body, contains('<title>App</title>'));
    expect(body, isNot(contains('<title>/nothing-here</title>')));
  });
}
