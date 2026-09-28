// HEAD on a page answers as GET does, without the body.
//
// A web-server build renders its pages in the SPA fallback, and that fallback
// ran for GET only. HEAD / on dartvel.dev answered 404 while GET / answered
// 200 -- an uptime monitor, a link checker and a crawler that asks HEAD
// first all saw a site with no pages on it.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _index = '<!DOCTYPE html><html><head><title>Shop</title>'
    '</head><body><div id="app"></div></body></html>';

void main() {
  late Directory site;

  setUp(() {
    site = Directory.systemTemp.createTempSync('dv_head_page_');
    File(p.join(site.path, 'index.html')).writeAsStringSync(_index);
  });

  tearDown(() => site.deleteSync(recursive: true));

  Future<({int status, String? type, int bodyBytes})> ask(
      String method, int port, String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      final HttpClientResponse response = await request.close();
      final int bytes = await response.fold<int>(
          0, (int n, List<int> part) => n + part.length);
      return (
        status: response.statusCode,
        type: response.headers.contentType?.mimeType,
        bodyBytes: bytes,
      );
    } finally {
      client.close(force: true);
    }
  }

  test('HEAD on a page is the GET status and headers, with no body', () async {
    final ServerHandle server = await serve(
      Router().call,
      host: '127.0.0.1',
      port: 0,
      spaRoot: site.path,
    );
    addTearDown(server.stop);

    for (final String path in <String>['/', '/products/42']) {
      final get = await ask('GET', server.port, path);
      final head = await ask('HEAD', server.port, path);
      expect(get.status, 200, reason: 'GET $path');
      expect(head.status, get.status, reason: 'HEAD $path');
      expect(head.type, get.type, reason: 'HEAD $path');
      expect(head.bodyBytes, 0, reason: 'HEAD $path carries no body');
    }
  });
}
