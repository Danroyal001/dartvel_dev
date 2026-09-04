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

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
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
}
