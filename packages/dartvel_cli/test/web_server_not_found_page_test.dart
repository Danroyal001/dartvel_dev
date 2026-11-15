// `dartvel dev --release` answers a missing path with the application's own
// not-found page, as the deployed server does (dartvel_shelf's SSR).
//
// Both answered a 404 with the bare shell: the splash over an empty body,
// and nothing at all without JavaScript. The page the build captured for
// /404 is rendered instead, by the same function as every other route, with
// the status kept and the path the reader asked for named on it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><title>App</title></head>'
    '<body><div id="app"></div></body></html>';

final String _manifest = jsonEncode(<String, Object?>{
  'siteUrl': 'https://example.com',
  'routes': <String, Object?>{
    '/': <String, Object?>{'title': 'Home', 'text': <String>['Welcome in']},
    '/docs': <String, Object?>{'title': 'Documentation'},
    '/404': <String, Object?>{
      'title': 'Page not found',
      'page': <String, Object?>{
        'route': '/404',
        'title': 'Page not found',
        'siteUrl': 'https://example.com',
        'html': '<h1>Page not found</h1><p>Nothing is at /404.</p>'
            '<a href="/">Go to the home page</a>',
      },
    },
  },
});

void main() {
  late Directory root;
  late HttpServer server;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_web_server_404_');
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(_manifest);
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

  Future<(int, String)> get(String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse('$base$path'))).close();
      return (
        response.statusCode,
        await response.transform(utf8.decoder).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  test('a missing path is the captured not-found page, with a 404', () async {
    final (int status, String html) = await get('/no-such-page');

    expect(status, 404);
    expect(html, contains('<h1>Page not found</h1>'));
    expect(html, contains('Nothing is at /no-such-page.'));
    expect(html, contains('Go to the home page'));
  });

  test('/404 itself still answers 200 at its own path', () async {
    final (int status, String html) = await get('/404');

    expect(status, 200);
    expect(html, contains('Nothing is at /404.'));
  });
}
