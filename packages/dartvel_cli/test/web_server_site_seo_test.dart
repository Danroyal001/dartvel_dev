// The site's declared SEO, on a server-rendered page.
//
// `_writeSeoHead` reads dartvel.seo and writes the description, the image and
// the site name into build/web/index.html as a marked block. Rendering a
// route replaces that block: dvSeoApply strips the old one along with the
// shell's title and description, then writes what the render was given. The
// web-server target gave it a title and a canonical and nothing else, so
// every page it served came out with no og:description, no og:image and no
// og:site_name -- values the static target keeps and the shell had a moment
// earlier.
//
// Nothing about the page looks wrong. It renders, it has a title, and the
// loss only shows up in a link preview or a crawler's index.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// The shell as a finished web build leaves it: the site's tags already in a
/// marked block, which is what a render is about to replace.
const String _shell = '''
<!DOCTYPE html>
<html><head><!-- dartvel:seo -->
<title>Acme — Everything, delivered</title>
<meta name="description" content="Everything, delivered">
<meta property="og:site_name" content="Acme">
<meta property="og:image" content="https://acme.example/social.png">
<!-- /dartvel:seo -->
</head><body><div id="app"></div></body></html>
''';

const DVSiteSeo _site = DVSiteSeo(
  name: 'Acme',
  description: 'Everything, delivered',
  image: '/social.png',
);

void main() {
  late Directory root;
  HttpServer? server;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_site_seo_');
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(
      dvWebServerManifest(
        routes: <String>['/', '/docs'],
        titles: const <String, String>{'/': 'Home', '/docs': 'Documentation'},
        text: const <String, List<String>>{},
        siteUrl: 'https://acme.example',
        site: _site,
      ),
    );
  });

  tearDown(() async {
    await server?.close(force: true);
    root.deleteSync(recursive: true);
  });

  Future<String> get(String path, {DVPageDataResolver? pageData}) async {
    server = await shelf_io.serve(
      dvWebServerHandler(webRoot: root.path, pageData: pageData),
      InternetAddress.loopbackIPv4,
      0,
    );
    base = 'http://${server!.address.host}:${server!.port}';
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$base$path'));
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  test('the manifest carries what dartvel.seo declared', () {
    // The server has no pubspec to read; whatever it needs has to travel in
    // the artifact beside the shell.
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{'/': 'Home'},
      text: const <String, List<String>>{},
      siteUrl: 'https://acme.example',
      site: _site,
    )) as Map<String, Object?>;

    expect(manifest['site'], <String, Object?>{
      'name': 'Acme',
      'description': 'Everything, delivered',
      'image': '/social.png',
    });
  });

  test('a project that declared none writes no site block', () {
    // An empty object in the manifest would read as "declared, and empty",
    // which is a different thing from "never declared".
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{'/': 'Home'},
      text: const <String, List<String>>{},
      siteUrl: null,
    )) as Map<String, Object?>;

    expect(manifest.containsKey('site'), isFalse);
  });

  test('a rendered page keeps the description the shell had', () async {
    final String html = await get('/docs');

    expect(html, contains('<title>Documentation</title>'));
    expect(html,
        contains('<meta name="description" content="Everything, delivered">'));
    expect(
        html,
        contains(
            '<meta property="og:description" content="Everything, delivered">'));
  });

  test('and the image, made absolute against the site', () async {
    // A link preview fetches the image with no base, so a relative path
    // resolves against whoever is previewing and 404s.
    final String html = await get('/docs');

    expect(
        html,
        contains(
            '<meta property="og:image" content="https://acme.example/social.png">'));
    expect(html, contains('twitter:card" content="summary_large_image"'));
  });

  test('and the site name, which is not the page title', () async {
    // Falling back to the shell's <title> names the site
    // "Acme — Everything, delivered" in every link preview.
    final String html = await get('/docs');

    expect(html, contains('<meta property="og:site_name" content="Acme">'));
  });

  test("a page's own description wins over the site's", () async {
    // The site's values are a floor, not an override: a product page that
    // resolved its own description should not be given the homepage's.
    final String html = await get(
      '/docs',
      pageData: (DVPageRequest request) => const DVPageData(
        title: 'Getting started',
        description: 'Install it in a minute',
      ),
    );

    expect(
        html,
        contains(
            '<meta property="og:description" content="Install it in a minute">'));
    expect(html, isNot(contains('Everything, delivered')));
    // The site name is still the site's -- a page does not rename the site.
    expect(html, contains('<meta property="og:site_name" content="Acme">'));
  });
}
