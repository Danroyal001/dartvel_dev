// `dartvel build web` and the web-server binary answer a route with the same
// page: one renders it at build time, the other on request, with the same
// function and the same inputs.
//
// They used to differ. The binary rendered from source lines and skipped the
// minifier, so /docs/ai reached a crawler with no links, headings or code
// blocks and in 110 lines where the static build wrote 43.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVRoutePage, dvMinifyHtml, dvRenderRoutePage;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8">\n'
    '    <title>Site</title>\n  </head>\n  <body>\n    <script src="main.dart.js"></script>\n'
    '  </body>\n</html>\n';

final List<DVRoutePage> _pages = <DVRoutePage>[
  const DVRoutePage(
    route: '/docs/ai',
    title: 'AI — Site',
    description: 'Models that answer.',
    siteUrl: 'https://example.com',
    siteName: 'Site',
    html: '<main><h1>AI</h1><p>Ask the model.</p><h2>Structured output</h2>'
        '<p>Use <strong>schemas</strong>, see <a href="/docs">the docs</a>.</p>'
        '<pre><code>final x = 1;\n  final y = 2;</code></pre></main>',
  ),
  const DVRoutePage(
    route: '/features',
    title: 'Features — Site',
    siteUrl: 'https://example.com',
    siteName: 'Site',
    html: '<main><h1>Features</h1><ul><li><a href="/studio">Studio</a></li></ul></main>',
  ),
  const DVRoutePage(
    route: '/',
    title: 'Site',
    siteUrl: 'https://example.com',
    siteName: 'Site',
    html: '<main><h1>Site</h1><p>Home.</p></main>',
  ),
];

Map<String, int> _elements(String html) => <String, int>{
      for (final String tag in <String>['a', 'h1', 'h2', 'strong', 'pre', 'code', 'p', 'section', 'li'])
        tag: RegExp('<$tag[ >]').allMatches(html).length,
    };

void main() {
  late Directory site;

  setUp(() {
    site = Directory.systemTemp.createTempSync('dv_render_parity_');
    // The shell as the web-server build leaves it: minified, like every
    // other file it ships.
    File(p.join(site.path, 'index.html')).writeAsStringSync(dvMinifyHtml(_shell));
    File(p.join(site.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
      'siteUrl': 'https://example.com',
      'routes': <String, Object?>{
        for (final DVRoutePage page in _pages)
          page.route: <String, Object?>{'title': page.title, 'page': page.toJson()},
      },
    }));
  });

  tearDown(() => site.deleteSync(recursive: true));

  test('each route: the served page is the static build\'s page, byte for byte',
      () async {
    final ServerHandle server = await serve(Router().call,
        host: '127.0.0.1', port: 0, spaRoot: site.path);
    addTearDown(server.stop);
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));

    for (final DVRoutePage page in _pages) {
      // What `dartvel build web` writes for the route: rendered from the
      // unminified shell, then minified with every other file.
      final String static = dvMinifyHtml(dvRenderRoutePage(_shell, page));
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}${page.route}'))).close();
      final String served = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200, reason: page.route);
      expect(_elements(served), _elements(static), reason: page.route);
      expect(served, static, reason: page.route);
    }
  });
}
