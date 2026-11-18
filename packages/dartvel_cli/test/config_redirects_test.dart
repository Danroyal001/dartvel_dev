import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' show DVHostRedirect, dvHostRedirectTarget, dvRedirectLocation;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' show Request, Response;
import 'package:test/test.dart';

void main() {
  test('dartvel.redirects reaches the manifest, with problems reported and left out', () {
    final List<String> problems = <String>[];
    final Map<String, DVConfiguredRedirectDeclaration> redirects = dvParseRedirects(<String, Object?>{
      '/downloads': '/downloads/',
      '/botm': <String, Object?>{'to': '/book-of-the-month/', 'status': 302},
      'nope': '/x',
      '/loop': '/loop',
      '/bad-status': <String, Object?>{'to': '/x', 'status': 200},
      '/no-target': 42,
    }, problems);
    expect(redirects.keys, <String>['/downloads', '/botm']);
    expect(problems, hasLength(4));
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{},
      text: const <String, List<String>>{},
      siteUrl: null,
      redirects: redirects,
    )) as Map<String, Object?>;
    expect(manifest['redirects'], <String, Object?>{
      '/downloads': <String, Object?>{'to': '/downloads/', 'status': 301},
      '/botm': <String, Object?>{'to': '/book-of-the-month/', 'status': 302},
    });
  });

  test('a dartvel.hosts entry that only redirects reaches the manifest', () {
    final hosts = dvHostsConfig(<Object?, Object?>{
      'hosts': <Object?, Object?>{
        'example.com': <Object?, Object?>{'siteUrl': 'https://example.com'},
        'old.example.net': <Object?, Object?>{'redirect': 'https://example.com/new'},
      },
    });
    expect(hosts.problems, isEmpty);
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{},
      text: const <String, List<String>>{},
      siteUrl: 'https://example.com',
      hosts: hosts.hosts,
    )) as Map<String, Object?>;
    expect(
      dvHostRedirectTarget(DVHostRedirect.listFromJson(manifest['hostRedirects']), host: 'old.example.net', rawPath: '/x'),
      'https://example.com/new',
    );
  });

  // `dartvel dev --release` previews with dvWebServerHandler and production
  // answers with dartvel_shelf's SSR fallback. Each spelled out its own
  // "keep the query" rule, and only production kept it for dartvel.redirects:
  // /old?ref=mail went to /new?ref=mail when deployed and to /new in preview.
  group('the preview answers a redirect with the query the deployed server keeps', () {
    late Directory webRoot;

    setUp(() {
      webRoot = Directory.systemTemp.createTempSync('dartvel_redirect_query_');
      File(p.join(webRoot.path, 'index.html'))
          .writeAsStringSync('<!DOCTYPE html><html><head><title>App</title></head><body></body></html>');
      File(p.join(webRoot.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
        'routes': <String, Object?>{'/': <String, Object?>{'title': 'Home'}},
        'redirects': <String, Object?>{
          '/old': <String, Object?>{'to': '/new', 'status': 301},
          '/search': <String, Object?>{'to': '/find?from=search', 'status': 302},
        },
      }));
    });

    tearDown(() => webRoot.deleteSync(recursive: true));

    Future<Response> ask(String path) async =>
        await dvWebServerHandler(webRoot: webRoot.path)(Request('GET', Uri.parse('http://localhost$path')));

    test('a target without a query of its own carries the request\'s', () async {
      final Response response = await ask('/old?ref=mail');
      expect(response.statusCode, 301);
      expect(response.headers['location'], '/new?ref=mail');
    });

    test('a target with its own query keeps it and adds the request''s', () async {
      final Response response = await ask('/search?q=x');
      expect(response.statusCode, 302);
      expect(response.headers['location'], '/find?from=search&q=x');
    });

    test('the request''s tracking parameters win over the target''s defaults', () async {
      // An ad links to a short link whose target tags a WhatsApp catalogue
      // tap: the ad's own utm_* and fbclid must reach the page.
      final Response response = await ask('/search?from=ad&fbclid=abc');
      expect(response.statusCode, 302);
      expect(response.headers['location'], '/find?from=ad&fbclid=abc');
    });

    test('the location is the shared core rule production answers with', () {
      expect(dvRedirectLocation('/new', 'ref=mail'), '/new?ref=mail');
      expect(dvRedirectLocation('/new', ''), '/new');
      expect(dvRedirectLocation('/find?from=search', 'q=x'), '/find?from=search&q=x');
      expect(
        dvRedirectLocation(
          '/p?utm_source=whatsapp&utm_medium=catalog&utm_campaign=store',
          'utm_source=fb&utm_medium=paid&fbclid=Iw%2B1&utm_campaign=120',
        ),
        '/p?utm_source=fb&utm_medium=paid&utm_campaign=120&fbclid=Iw%2B1',
      );
      expect(dvRedirectLocation('https://a.example/p?x=1#top', 'y=2'), 'https://a.example/p?x=1&y=2#top');
    });
  });
}
