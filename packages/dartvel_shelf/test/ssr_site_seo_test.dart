// The site's declared SEO on the server that ships, not just in preview.
//
// dvSeoApply replaces the marked block the build wrote into index.html. Given
// only a title and a canonical, the replacement drops the site's description,
// image and name -- so the backend served worse metadata than the untouched
// shell it started from, on every page, silently.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageDataResolver, DVPageRequest;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html><head><!-- dartvel:seo -->
<title>Acme — Everything, delivered</title>
<meta name="description" content="Everything, delivered">
<meta property="og:site_name" content="Acme">
<!-- /dartvel:seo -->
</head><body></body></html>
''';

Directory site() {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_seo_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://acme.example',
      'site': <String, Object?>{
        'name': 'Acme',
        'description': 'Everything, delivered',
        'image': '/social.png',
      },
      'server': <String, Object?>{},
      'routes': <String, Object?>{
        '/docs': <String, Object?>{'title': 'Documentation'},
        '/products/:id': <String, Object?>{'title': 'A product'},
      },
    },
  ));
  return root;
}

Future<String> get(String path, {DVPageDataResolver? pageData}) async {
  final Response response = await handleSsrFallback(
    Request(
      method: 'GET',
      url: Uri.parse('http://acme.example$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    ),
    site().path,
    pageData: pageData,
  );
  return utf8.decode(
    <int>[for (final List<int> chunk in await response.body!.stream.toList()) ...chunk],
  );
}

void main() {
  test('a rendered page keeps the site description and image', () async {
    final String html = await get('/docs');

    expect(html, contains('<title>Documentation</title>'));
    expect(
        html,
        contains(
            '<meta property="og:description" content="Everything, delivered">'));
    expect(
        html,
        contains(
            '<meta property="og:image" content="https://acme.example/social.png">'));
  });

  test('the site name is the declared one, not the shell title', () async {
    // The shell's title is the homepage's title. Falling back to it names the
    // site "Acme — Everything, delivered" in every link preview, which is a
    // sentence where a name belongs.
    final String html = await get('/docs');

    expect(html, contains('<meta property="og:site_name" content="Acme">'));
  });

  test("resolved page data wins over the site's values", () async {
    final String html = await get(
      '/products/9',
      pageData: (DVPageRequest request) => DVPageData(
        title: 'Product ${request.params['id']}',
        description: 'One product',
        image: '/products/9.png',
      ),
    );

    expect(html, contains('<meta property="og:description" content="One product">'));
    expect(
        html,
        contains(
            '<meta property="og:image" content="https://acme.example/products/9.png">'));
    expect(html, isNot(contains('Everything, delivered')));
  });
}
