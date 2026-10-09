import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVPublishedPages, dvPublishedPagesPath;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a framework data endpoint is never treated as a rendered HTML page',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'preview-endpoint-cache-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/index.html').writeAsStringSync(
        '<html><head><title>App</title></head><body></body></html>',
      );
      File('${root.path}/dartvel_routes.json').writeAsStringSync(
        jsonEncode({
          'routes': {
            dvPublishedPagesPath: {'title': 'Not a page'},
          },
        }),
      );
      final handler = dvWebServerHandler(
        webRoot: root.path,
        publishedPages: DVPublishedPages(database: () => null),
      );
      final response = await handler(
        Request('GET', Uri.parse('http://localhost$dvPublishedPagesPath')),
      );
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(response.headers['etag'], isNull);
      expect(jsonDecode(await response.readAsString()), {'pages': []});
    },
  );

  test(
    'preview hits keep bytes; purge rerenders and opt-out bypasses',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'preview-document-cache-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final shell = File('${root.path}/index.html');
      shell.writeAsStringSync(
        '<html><head><title>App</title></head><body>original</body></html>',
      );
      File('${root.path}/dartvel_routes.json').writeAsStringSync(
        jsonEncode({
          'routes': {
            '/login': {'title': 'Login'},
            '/clock': {'title': 'Clock', 'cache': false},
          },
        }),
      );
      final handler = dvWebServerHandler(webRoot: root.path, streaming: false);
      Future<Response> get(
        String path, {
        Map<String, String> headers = const {},
      }) async => await handler(
        Request('GET', Uri.parse('http://localhost$path'), headers: headers),
      );
      final first = await get('/login');
      final original = await first.readAsString();
      expect(first.headers['etag'], isNotNull);
      shell.writeAsStringSync(
        '<html><head><title>App</title></head><body>updated</body></html>',
      );
      final hit = await get('/login');
      expect(await hit.readAsString(), original);
      final cookie = await get('/login', headers: {'cookie': 'session=reader'});
      expect(cookie.headers['etag'], isNull);
      expect(await cookie.readAsString(), contains('updated'));
      final clock = await get('/clock');
      expect(clock.headers['etag'], isNull);
      dvPurgeRenderedPages();
      final fresh = await get('/login');
      expect(await fresh.readAsString(), contains('updated'));
      expect(fresh.headers['etag'], isNot(first.headers['etag']));
      final conditional = await get(
        '/login',
        headers: {'if-none-match': fresh.headers['etag']!},
      );
      expect(conditional.statusCode, 304);
      expect(await conditional.readAsString(), isEmpty);
    },
  );
}
