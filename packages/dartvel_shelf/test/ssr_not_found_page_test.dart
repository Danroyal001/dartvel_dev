// A path no route serves gets the application's own not-found page.
//
// The server answered a missing path with a 404 and the bare shell: the
// splash and "Loading…" over an empty body until Flutter drew the page,
// and nothing at all with JavaScript off. Every other route is a real
// document from the first frame, rendered from what the build captured, so
// the not-found page is too: the page the build captured for /404, rendered
// by the same function, at the path that was asked for. The status stays
// 404, and the path the page names is the one the reader typed.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageDataResolver, DVPageRequest, DVPageVisibility;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><title>Acme</title></head>'
    '<body><div id="app"></div></body></html>';

const String _notFoundDocument = '<h1>Page not found</h1>'
    '<p>Nothing is at /404.</p>'
    '<p>The link may be wrong, or the page may have moved.</p>'
    '<a href="/">Go to the home page</a>';

Directory site({bool withNotFoundPage = true}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_404_page_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://acme.example',
      'routes': <String, Object?>{
        '/': <String, Object?>{'title': 'Home'},
        '/docs': <String, Object?>{'title': 'Documentation'},
        '/products/:id': <String, Object?>{'title': 'A product'},
        if (withNotFoundPage)
          '/404': <String, Object?>{
            'title': 'Page not found',
            'page': <String, Object?>{
              'route': '/404',
              'title': 'Page not found',
              'siteUrl': 'https://acme.example',
              'html': _notFoundDocument,
            },
          },
      },
    },
  ));
  return root;
}

Future<Response> get(String path, Directory root, {DVPageDataResolver? pageData}) => handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://acme.example$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
      pageData: pageData,
    );

Future<String> body(Response response) async => utf8.decode(<int>[
      for (final List<int> chunk in await response.body!.stream.toList())
        ...chunk,
    ]);

void main() {
  test('a missing path is the captured not-found page, with a 404', () async {
    final Response response = await get('/no-such-page', site());
    final String html = await body(response);

    expect(response.status, 404);
    expect(html, contains('<h1>Page not found</h1>'));
    expect(html, contains('The link may be wrong'));
    expect(html, contains('<a href="/">Go to the home page</a>'));
    expect(html, contains('<title>Page not found'));
  });

  test('the page names the path that was asked for, escaped', () async {
    final Response response = await get('/no-such-page', site());
    final String html = await body(response);

    expect(html, contains('Nothing is at /no-such-page.'));
    expect(html, isNot(contains('Nothing is at /404.')));

    final String tricky =
        await body(await get('/a%3Cb%3E', site()));
    expect(tricky, isNot(contains('<b>')));
  });

  test('/404 itself is still the page at its own path', () async {
    final Response response = await get('/404', site());

    expect(response.status, 200);
    expect(await body(response), contains('Nothing is at /404.'));
  });

  test('a record its page hides is the not-found page too', () async {
    final Response response = await get('/products/7', site(),
        pageData: (DVPageRequest request) async =>
            const DVPageData(title: 'Secret', visibility: DVPageVisibility.hidden));
    final String html = await body(response);

    expect(response.status, 404);
    expect(html, contains('<h1>Page not found</h1>'));
    expect(html, contains('Nothing is at /products/7.'));
    expect(html, isNot(contains('Secret')));
  });

  test('without a captured not-found page the shell is still answered', () async {
    final Response response = await get('/no-such-page', site(withNotFoundPage: false));

    expect(response.status, 404);
    expect(await body(response), contains('<div id="app">'));
  });
}
