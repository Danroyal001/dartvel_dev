// dartvel.hosts in the CLI: carried into the manifest, the sitemap written
// with each page's public URL, a static build warned, and `dartvel dev
// --release`'s own server answering hosts as the web-server binary does.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVHosts, DVHostsParse, DVRoutePage;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const Map<String, Object?> _hostsYaml = <String, Object?>{
  'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
  'docs.example.com': <String, Object?>{
    'mount': '/docs',
    'siteUrl': 'https://docs.example.com',
    'name': 'Example Docs',
    'description': 'Reference for Example.',
  },
  '*.apps.example.com': <String, Object?>{
    'mount': '/apps/{label}',
    'siteUrl': 'https://{label}.apps.example.com',
  },
};

DVHosts _hosts() => DVHosts.parse(_hostsYaml).hosts;

const List<String> _routes = <String>[
  '/',
  '/pricing',
  '/docs',
  '/docs/x',
  '/apps/foo',
  '/apps/foo/settings',
];

void main() {
  group('the manifest', () {
    test('carries the hosts when declared', () {
      final Map<String, Object?> manifest = (jsonDecode(
        dvWebServerManifest(
          routes: _routes,
          titles: const <String, String>{},
          text: const <String, List<String>>{},
          siteUrl: 'https://example.com',
          hosts: _hosts(),
        ),
      ) as Map).cast<String, Object?>();
      expect(manifest['hosts'], _hosts().toJson());
      expect(
        DVHosts.fromJson(manifest['hosts']).primary.pattern,
        'example.com',
      );
    });

    test('is byte-for-byte what it was without hosts', () {
      String write({DVHosts? hosts}) => hosts == null
          ? dvWebServerManifest(
              routes: _routes,
              titles: const <String, String>{'/': 'Home'},
              text: const <String, List<String>>{},
              siteUrl: 'https://example.com',
            )
          : dvWebServerManifest(
              routes: _routes,
              titles: const <String, String>{'/': 'Home'},
              text: const <String, List<String>>{},
              siteUrl: 'https://example.com',
              hosts: hosts,
            );
      expect(write(hosts: DVHosts.none), write());
      expect(write(), isNot(contains('"hosts"')));
    });
  });

  group('the sitemap', () {
    test('lists each page at its public URL when hosts are declared', () {
      final String sitemap = dvSitemap(
        routes: _routes,
        siteUrl: 'https://example.com',
        publicUrl: _hosts().publicUrl,
      );
      expect(sitemap, contains('<loc>https://example.com/pricing</loc>'));
      expect(sitemap, contains('<loc>https://docs.example.com/x</loc>'));
      expect(sitemap, contains('<loc>https://docs.example.com</loc>'));
      expect(
        sitemap,
        contains('<loc>https://foo.apps.example.com/settings</loc>'),
      );
      expect(sitemap, isNot(contains('https://example.com/docs')));
    });

    test('is unchanged without hosts', () {
      final String sitemap = dvSitemap(
        routes: _routes,
        siteUrl: 'https://example.com',
      );
      expect(sitemap, contains('<loc>https://example.com/docs/x</loc>'));
    });
  });

  group('page defaults per host', () {
    test("a page's own description always wins, with or without hosts", () {
      expect(
        dvHostPageDescription(
          DVHosts.none,
          '/docs/x',
          declared: 'Own.',
          site: 'Site.',
        ),
        'Own.',
      );
      expect(
        dvHostPageDescription(
          _hosts(),
          '/docs/x',
          declared: 'Own.',
          site: 'Site.',
        ),
        'Own.',
      );
    });

    test('the host description stands in only for the site-wide one', () {
      expect(
        dvHostPageDescription(_hosts(), '/docs/x', site: 'Site.'),
        'Reference for Example.',
      );
      expect(
        dvHostPageDescription(_hosts(), '/pricing', site: 'Site.'),
        'Site.',
      );
      expect(
        dvHostPageDescription(DVHosts.none, '/docs/x', site: 'Site.'),
        'Site.',
      );
    });

    test('the host name names the site on that host', () {
      expect(
        dvHostPageSiteName(_hosts(), '/docs/x', 'Example'),
        'Example Docs',
      );
      expect(dvHostPageSiteName(_hosts(), '/pricing', 'Example'), 'Example');
      expect(dvHostPageSiteName(DVHosts.none, '/docs/x', 'Example'), 'Example');
    });
  });

  group('reading dartvel.hosts', () {
    test('problems are reported for the build to fail on', () {
      final DVHostsParse parsed = dvHostsConfig(<String, Object?>{
        'hosts': <String, Object?>{
          'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
          'example.org': <String, Object?>{'siteUrl': 'https://example.org'},
        },
      });
      expect(parsed.problems, isNotEmpty);
    });

    test('the primary takes dartvel.seo.siteUrl', () {
      final DVHostsParse parsed = dvHostsConfig(<String, Object?>{
        'seo': <String, Object?>{'siteUrl': 'https://example.com'},
        'hosts': <String, Object?>{'example.com': null},
      });
      expect(parsed.problems, isEmpty);
      expect(parsed.hosts.primary.siteUrl, 'https://example.com');
    });

    test('a static build is told hosts need the web-server build', () {
      expect(
        dvStaticHostsWarning(<String, Object?>{'hosts': _hostsYaml}),
        contains('web-server'),
      );
      expect(dvStaticHostsWarning(const <String, Object?>{}), isNull);
    });
  });

  group('dartvel dev --release serves hosts as the binary does', () {
    late Directory root;
    HttpServer? server;
    late Uri base;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('dartvel_preview_hosts_');
      File(p.join(root.path, 'index.html')).writeAsStringSync(
        '<!DOCTYPE html>\n<html><head><!-- dartvel:seo -->\n'
        '<title>Example</title>\n<!-- /dartvel:seo -->\n'
        '</head><body></body></html>\n',
      );
      File(p.join(root.path, 'robots.txt'))
          .writeAsStringSync(dvRobots(siteUrl: 'https://example.com'));
      File(p.join(root.path, 'sitemap.xml')).writeAsStringSync(
        dvSitemap(
          routes: _routes,
          siteUrl: 'https://example.com',
          publicUrl: _hosts().publicUrl,
        ),
      );
      File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(
        dvWebServerManifest(
          routes: <String>[..._routes, '/docs/private', '/sign-in'],
          titles: const <String, String>{
            '/docs': 'Docs home',
            '/apps/foo/settings': 'Foo settings',
          },
          text: const <String, List<String>>{},
          siteUrl: 'https://example.com',
          site: const DVSiteSeo(name: 'Example', description: 'Site-wide.'),
          guarded: const <String>{'/docs/private'},
          signIn: '/sign-in',
          hosts: _hosts(),
          pages: <String, DVRoutePage>{
            '/docs/x': const DVRoutePage(
              route: '/docs/x',
              title: 'X',
              description: 'The page about X.',
              siteUrl: 'https://example.com',
            ),
          },
        ),
      );
      server = await shelf_io.serve(
        dvWebServerHandler(webRoot: root.path),
        InternetAddress.loopbackIPv4,
        0,
      );
      base = Uri.parse('http://127.0.0.1:${server!.port}');
    });

    tearDown(() async {
      await server?.close(force: true);
      root.deleteSync(recursive: true);
    });

    Future<http.Response> get(String host, String path) async {
      final http.Request request =
          http.Request(
              'GET',
              base.replace(
                path: Uri.parse(path).path,
                query: Uri.parse(path).hasQuery ? Uri.parse(path).query : null,
              ),
            )
            ..followRedirects = false
            ..headers['host'] = host;
      return http.Response.fromStream(await http.Client().send(request));
    }

    String? canonical(String html) =>
        RegExp(r'<link rel="canonical" href="([^"]*)"')
            .firstMatch(html)
            ?.group(1);

    test('a route of another host is 301 there, query kept', () async {
      final http.Response r = await get('example.com', '/docs/x?a=1');
      expect(r.statusCode, 301);
      expect(r.headers['location'], 'https://docs.example.com/x?a=1');
    });

    test('a mounted host shows its mount at its own canonical', () async {
      final http.Response r = await get('docs.example.com', '/');
      expect(r.statusCode, 200);
      expect(r.body, contains('<title>Docs home</title>'));
      expect(canonical(r.body), 'https://docs.example.com');
      final http.Response x = await get('docs.example.com', '/x');
      expect(canonical(x.body), 'https://docs.example.com/x');
      expect(x.body, contains('content="The page about X."'));
    });

    test('a wildcard host shows its label', () async {
      final http.Response r = await get('foo.apps.example.com', '/settings');
      expect(r.body, contains('<title>Foo settings</title>'));
      expect(canonical(r.body), 'https://foo.apps.example.com/settings');
    });

    test('an unknown host is the primary', () async {
      final http.Response r = await get('203.0.113.9', '/pricing');
      expect(r.statusCode, 200);
      expect(canonical(r.body), 'https://example.com/pricing');
    });

    test('a guarded page goes to the public sign-in URL', () async {
      final http.Response r = await get('docs.example.com', '/private');
      expect(r.statusCode, 302);
      expect(
        r.headers['location'],
        'https://example.com/sign-in?from=%2Fdocs%2Fprivate',
      );
    });

    test('two hosts never share a cached document', () async {
      final String a = (await get('example.com', '/')).body;
      final String b = (await get('docs.example.com', '/')).body;
      expect(canonical(a), 'https://example.com');
      expect(canonical(b), 'https://docs.example.com');
    });

    test('robots.txt and the sitemap per host', () async {
      final http.Response robots = await get('docs.example.com', '/robots.txt');
      expect(robots.statusCode, 200);
      expect(
        robots.body,
        contains('Sitemap: https://docs.example.com/sitemap.xml'),
      );
      final http.Response sitemap = await get(
        'docs.example.com',
        '/sitemap.xml',
      );
      expect(sitemap.body, contains('<loc>https://docs.example.com/x</loc>'));
      expect(sitemap.body, isNot(contains('<loc>https://example.com')));
      expect(
        (await get('bar.apps.example.com', '/robots.txt')).statusCode,
        404,
      );
      expect(
        (await get('bar.apps.example.com', '/sitemap.xml')).statusCode,
        404,
      );
    });
  });
}
