import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    dvPurgeRenderedPages();
    root = Directory.systemTemp.createTempSync('ssr-document-cache-');
    File('${root.path}/index.html').writeAsStringSync(
      '<html><head><title>App</title></head><body>héllo</body></html>',
    );
    File('${root.path}/dartvel_routes.json').writeAsStringSync(
      jsonEncode({
        'routes': {
          '/login': {'title': 'Login'},
          '/private': {'guarded': true},
          '/clock': {'title': 'Clock', 'cache': false},
        },
      }),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));
  Request request(
    String path, {
    Map<String, String> headers = const {},
    String method = 'GET',
  }) => Request(
    method: method,
    url: Uri.parse('http://localhost$path'),
    headers: Headers(headers),
    bodyStream: const Stream<List<int>>.empty(),
  );
  Future<List<int>> bytes(Response response) async =>
      await response.body!.bytes();

  test(
    'cached public bytes match uncached render, validators return bodyless 304',
    () async {
      final uncached = await handleSsrFallback(
        request('/login', headers: {'cookie': 'session=x'}),
        root.path,
      );
      expect(uncached.headers.get('cache-control'), 'no-store');
      final first = await handleSsrFallback(request('/login'), root.path);
      final etag = first.headers.get('etag');
      expect(etag, isNotNull);
      expect(await bytes(first), await bytes(uncached));
      final hit = await handleSsrFallback(request('/login'), root.path);
      expect(
        await bytes(hit),
        await bytes(await handleSsrFallback(request('/login'), root.path)),
      );
      final conditional = await handleSsrFallback(
        request('/login', headers: {'if-none-match': etag!}),
        root.path,
      );
      expect(conditional.status, 304);
      expect(await bytes(conditional), isEmpty);
    },
  );
  test(
    'guarded, cookies, auth, opt-out, unknown and non-GET never cache',
    () async {
      for (final req in [
        request('/private'),
        request('/clock'),
        request('/missing'),
        request('/login', headers: {'cookie': 'theme=dark'}),
        request('/login', headers: {'authorization': 'Bearer x'}),
        request('/login', method: 'POST'),
      ]) {
        final response = await handleSsrFallback(req, root.path);
        expect(
          response.headers.get('etag'),
          isNull,
          reason: req.url.toString(),
        );
        expect(response.headers.get('cache-control'), 'no-store');
      }
    },
  );
  test('custom data resolver remains request-scoped; generated unmatched resolver is safe', () async {
    var calls = 0;
    Future<DVPageData?> resolver(DVPageRequest r) async =>
        DVPageData(title: 'Reader ${++calls}');
    final a = await handleSsrFallback(
      request('/login'),
      root.path,
      pageData: resolver,
    );
    final b = await handleSsrFallback(
      request('/login'),
      root.path,
      pageData: resolver,
    );
    expect(a.headers.get('etag'), isNull);
    expect(await bytes(a), isNot(await bytes(b)));
    expect(calls, 2);
    final generated = dvModelPageResolver(
      [],
      (sql, params) async => throw StateError('must not query'),
    );
    final safe = await handleSsrFallback(
      request('/login'),
      root.path,
      pageData: generated,
    );
    expect(safe.headers.get('etag'), isNotNull);
  });
}
