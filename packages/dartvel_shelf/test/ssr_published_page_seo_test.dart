// A page published from Studio is served with what it says about itself --
// its title, description, indexing rule, canonical address and structured
// data -- rather than the site's, and the sitemap lists it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPublishedPageSeo;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><title>Harbour</title></head>'
    '<body><div id="app"></div></body></html>';

Directory _site() {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_seo_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://harbour.example',
      'site': <String, Object?>{'name': 'Harbour', 'description': 'Boats, for hire.'},
      'routes': <String, Object?>{
        '/': <String, Object?>{'title': 'Home'},
      },
    },
  ));
  File(p.join(root.path, 'sitemap.xml')).writeAsStringSync(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    '<url><loc>https://harbour.example/</loc></url>\n'
    '</urlset>\n',
  );
  return root;
}

Request _get(String path) => Request(
      method: 'GET',
      url: Uri.parse('http://harbour.example$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<String> _body(Response response) async => utf8.decode(<int>[
      for (final List<int> chunk in await response.body!.stream.toList())
        ...chunk,
    ]);

void main() {
  Future<DVPublishedPageSeo?> published(String path) async => path == '/sale'
      ? const DVPublishedPageSeo(
          title: 'Autumn sale',
          description: 'Our autumn sale.',
          robots: 'noindex, follow',
          schemaType: 'Product',
          text: <String>['Everything half price'],
        )
      : null;

  test('a Studio page is served with its own head', () async {
    final Response response = await handleSsrFallback(
      _get('/sale'),
      _site().path,
      publishedRoutes: () async => <String>{'/sale'},
      publishedPage: published,
    );
    expect(response.status, 200);
    final String html = await _body(response);
    expect(html, contains('<title>Autumn sale</title>'));
    expect(html, contains('content="Our autumn sale."'));
    expect(html, contains('<meta name="robots" content="noindex, follow">'));
    expect(html, contains('href="https://harbour.example/sale"'));
    expect(html, contains('"@type":"Product"'));
    expect(html, contains('Everything half price'));
  });

  test('the sitemap lists the published pages with the built ones', () async {
    final Response? response = await dvPublishedSitemapResponse(
      _get('/sitemap.xml'),
      _site().path,
      routes: () async => <String>['/sale'],
    );
    expect(response!.status, 200);
    expect(response.headers.get('content-type'), contains('xml'));
    final String xml = await _body(response);
    expect(xml, contains('<loc>https://harbour.example/</loc>'));
    expect(xml, contains('<loc>https://harbour.example/sale</loc>'));
    expect(
      await dvPublishedSitemapResponse(_get('/other.xml'), _site().path,
          routes: () async => <String>['/sale']),
      isNull,
    );
  });
}
