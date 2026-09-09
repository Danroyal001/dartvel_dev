// A federated micro-site's routes, in the parent that mounts it.
//
// The specification asks for exactly this: "A federated micro-site may serve
// its own HTML while still appearing in the parent route index and sitemap."
//
// They were in the route index and nowhere else. Left out of the sitemap they
// are invisible, which is the whole point of mounting a micro-site under a
// parent's domain; put in it without the parent serving the path, a crawler
// follows the link and gets the parent's not-found page. The parent answers
// the path and sends the reader on; the module serves the HTML, which is what
// makes it federated rather than embedded.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const Map<String, String> mounted = <String, String>{
  '/store': 'https://store.example.com/',
  '/store/products/:id': 'https://store.example.com/products/:id',
};

Map<String, Object?> manifestOf({Map<String, String> federated = mounted}) =>
    jsonDecode(dvWebServerManifest(
      routes: <String>['/', '/about'],
      titles: const <String, String>{'/': 'Home'},
      text: const <String, List<String>>{},
      siteUrl: 'https://example.com',
      federated: federated,
    )) as Map<String, Object?>;

void main() {
  group('the manifest', () {
    test('carries a federated route with where it answers', () {
      final Map<String, Object?> routes =
          (manifestOf()['routes']! as Map<String, Object?>);

      expect(routes.keys, contains('/store'));
      expect((routes['/store']! as Map<String, Object?>)['location'],
          'https://store.example.com/');
    });

    test('a route the parent serves itself carries no location', () {
      // The presence of one is what tells the server to send the reader on,
      // so putting it on every route would send every reader away.
      final Map<String, Object?> routes =
          (manifestOf()['routes']! as Map<String, Object?>);

      expect((routes['/']! as Map<String, Object?>).containsKey('location'),
          isFalse);
    });

    test('a project with nothing federated is unchanged', () {
      final Map<String, Object?> routes = (manifestOf(
        federated: const <String, String>{},
      )['routes']! as Map<String, Object?>);

      expect(routes.keys, <String>['/', '/about']);
    });
  });

  group('the sitemap', () {
    test('lists a federated route under the parent, not the module', () {
      // Under the parent, because that is the URL a reader has and the one
      // the parent answers. A cross-domain entry is ignored by crawlers and
      // would make mounting a micro-site pointless.
      final String xml = dvSitemap(
        routes: <String>['/'],
        siteUrl: 'https://example.com',
        federated: mounted.keys.toList(),
      );

      expect(xml, contains('https://example.com/store'));
      expect(xml, isNot(contains('store.example.com')));
    });

    test('leaves out the ones nobody can visit', () {
      // A parameterised route is a pattern, not a page, wherever it is
      // served from.
      final String xml = dvSitemap(
        routes: <String>['/'],
        siteUrl: 'https://example.com',
        federated: mounted.keys.toList(),
      );

      expect(xml, isNot(contains('/store/products/:id')));
    });
  });

  group('the preview server', () {
    // The build writes the location and the deployed backend acts on it.
    // This server read the same manifest and had no idea the key existed, so
    // `dartvel preview` answered /store with the parent's own shell: a page
    // titled with the site name, no module content, and no sign anything was
    // wrong. A developer checking a mounted micro-site locally saw a blank
    // app and had nothing to go on.
    late Directory root;
    late HttpServer server;
    late String base;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('dartvel_fed_preview_');
      File(p.join(root.path, 'index.html')).writeAsStringSync(
          '<html><head><title>Parent</title></head><body></body></html>');
      File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(
        dvWebServerManifest(
          routes: <String>['/'],
          titles: const <String, String>{'/': 'Home'},
          text: const <String, List<String>>{},
          siteUrl: 'https://example.com',
          federated: <String, String>{
            ...mounted,
            '/bad': 'javascript:alert(1)',
          },
        ),
      );
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

    Future<HttpClientResponse> get(String path) async {
      final client = HttpClient()..autoUncompress = false;
      final HttpClientRequest request =
          await client.getUrl(Uri.parse('$base$path'));
      request.followRedirects = false;
      return request.close();
    }

    test('sends the reader to the module rather than rendering a page',
        () async {
      final HttpClientResponse response = await get('/store');

      expect(response.statusCode, 302);
      expect(response.headers.value('location'), 'https://store.example.com/');
    });

    test('carries the request parameters across', () async {
      // The reader asked for one product. Handing them the module's index
      // loses the only part of the request that mattered.
      final HttpClientResponse response = await get('/store/products/pro-kit');

      expect(response.statusCode, 302);
      expect(response.headers.value('location'),
          'https://store.example.com/products/pro-kit');
    });

    test('a location that is not an address is not a redirect', () async {
      // A manifest is data and can be edited. Sending a reader wherever the
      // string points is how an open redirect starts.
      final HttpClientResponse response = await get('/bad');

      expect(response.statusCode, isNot(302));
    });

    test('the parent still renders its own pages', () async {
      final HttpClientResponse response = await get('/');

      expect(response.statusCode, 200);
    });
  });
}
