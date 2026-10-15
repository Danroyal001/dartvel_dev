// dartvel.hosts on the web-server binary: one process, several hostnames,
// each showing a part of the one route tree, with canonical URLs on the host
// that owns the page, 301s from the old locations and a robots.txt and
// sitemap per host.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVClientAddress, DVHosts, DVRoutePage;
import 'package:dartvel_core/framework.dart' show dvPurgeRenderedPages;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell =
    '<!DOCTYPE html>\n<html><head><!-- dartvel:seo -->\n'
    '<title>Example</title>\n<!-- /dartvel:seo -->\n'
    '</head><body></body></html>\n';

const Map<String, Object?> _hosts = <String, Object?>{
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

const String _sitemap =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    '  <url>\n    <loc>https://example.com</loc>\n  </url>\n'
    '  <url>\n    <loc>https://example.com/pricing</loc>\n  </url>\n'
    '  <url>\n    <loc>https://docs.example.com</loc>\n  </url>\n'
    '  <url>\n    <loc>https://docs.example.com/x</loc>\n  </url>\n'
    '  <url>\n    <loc>https://foo.apps.example.com</loc>\n  </url>\n'
    '  <url>\n    <loc>https://foo.apps.example.com/settings</loc>\n  </url>\n'
    '</urlset>\n';

Directory site({bool hosts = true}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_hosts_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'robots.txt')).writeAsStringSync(
    'User-agent: *\nAllow: /\n\nSitemap: https://example.com/sitemap.xml\n',
  );
  File(p.join(root.path, 'sitemap.xml')).writeAsStringSync(_sitemap);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'siteUrl': 'https://example.com',
      'signIn': '/sign-in',
      'site': <String, Object?>{
        'name': 'Example',
        'description': 'Site-wide description.',
      },
      if (hosts) 'hosts': DVHosts.parse(_hosts).hosts.toJson(),
      'server': <String, Object?>{},
      'routes': <String, Object?>{
        '/': <String, Object?>{'title': 'Home'},
        '/pricing': <String, Object?>{'title': 'Pricing'},
        '/sign-in': <String, Object?>{'title': 'Sign in'},
        '/docs': <String, Object?>{'title': 'Docs home'},
        '/docs/x': <String, Object?>{
          'title': 'X',
          'page': const DVRoutePage(
            route: '/docs/x',
            title: 'X',
            description: 'The page about X.',
            siteUrl: 'https://example.com',
            siteName: 'Example Docs',
          ).toJson(),
        },
        '/docs/private': <String, Object?>{'title': 'Private', 'guarded': true},
        '/apps/foo': <String, Object?>{'title': 'Foo'},
        '/apps/foo/settings': <String, Object?>{'title': 'Foo settings'},
      },
    }),
  );
  return root;
}

Request request(
  String url, {
  Map<String, String> headers = const <String, String>{},
  String? peer,
}) {
  final Uri uri = Uri.parse(url);
  return Request(
    method: 'GET',
    // What the native server builds: its own bind address, never the Host.
    url: Uri.parse(
      'http://127.0.0.1:8080${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
    ),
    headers: Headers(<String, String>{'host': uri.authority, ...headers}),
    bodyStream: const Stream<List<int>>.empty(),
    peerAddress: peer == null ? null : DVPeerAddress.tryParse(peer),
  );
}

Future<String> body(Response response) async => utf8.decode(
  await response.body!.stream.expand((List<int> c) => c).toList(),
);

String? canonical(String html) =>
    RegExp(r'<link rel="canonical" href="([^"]*)"').firstMatch(html)?.group(1);
String? ogUrl(String html) =>
    RegExp(r'<meta property="og:url" content="([^"]*)"')
        .firstMatch(html)
        ?.group(1);
String? description(String html) =>
    RegExp(r'<meta name="description" content="([^"]*)"')
        .firstMatch(html)
        ?.group(1);
String? siteName(String html) =>
    RegExp(r'<meta property="og:site_name" content="([^"]*)"')
        .firstMatch(html)
        ?.group(1);

void main() {
  setUp(dvPurgeRenderedPages);
  tearDown(DVClientAddress.reset);

  group('redirects to the host that owns the page', () {
    test('primary /docs/x is 301 to docs.example.com/x, query kept', () async {
      final Directory root = site();
      final Response r = await handleSsrFallback(
        request('https://example.com/docs/x?a=1'),
        root.path,
      );
      expect(r.status, 301);
      expect(r.headers.get('location'), 'https://docs.example.com/x?a=1');
    });

    test('primary /apps/foo is 301 to foo.apps.example.com', () async {
      final Response r = await handleSsrFallback(
        request('https://example.com/apps/foo'),
        site().path,
      );
      expect(r.status, 301);
      expect(r.headers.get('location'), 'https://foo.apps.example.com');
    });

    test('a path no route serves is not redirected; it is not found', () async {
      final Response r = await handleSsrFallback(
        request('https://example.com/docs/nope'),
        site().path,
      );
      expect(r.status, 404);
      expect(r.headers.get('location'), isNull);
    });

    test('docs.example.com/ stays and shows /docs', () async {
      final Response r = await handleSsrFallback(
        request('https://docs.example.com/'),
        site().path,
      );
      expect(r.status, 200);
      final String html = await body(r);
      expect(html, contains('<title>Docs home</title>'));
      expect(canonical(html), 'https://docs.example.com');
      expect(ogUrl(html), 'https://docs.example.com');
    });

    test('a path of another host asked on a mounted host goes there', () async {
      final Response r = await handleSsrFallback(
        request('https://docs.example.com/x'),
        site().path,
      );
      expect(r.status, 200);
      // docs.example.com/pricing is /docs/pricing, which is no route: 404.
      final Response other = await handleSsrFallback(
        request('https://docs.example.com/pricing'),
        site().path,
      );
      expect(other.status, 404);
    });
  });

  group('canonical URLs', () {
    test(
      'a mounted page canonicalises to its host, page description wins',
      () async {
        final String html = await body(
          await handleSsrFallback(
            request('https://docs.example.com/x'),
            site().path,
          ),
        );
        expect(canonical(html), 'https://docs.example.com/x');
        expect(ogUrl(html), 'https://docs.example.com/x');
        expect(description(html), 'The page about X.');
      },
    );

    test('a wildcard host page canonicalises to its own label', () async {
      final String html = await body(
        await handleSsrFallback(
          request('https://foo.apps.example.com/settings'),
          site().path,
        ),
      );
      expect(html, contains('<title>Foo settings</title>'));
      expect(canonical(html), 'https://foo.apps.example.com/settings');
    });

    test(
      'an unknown host is served as the primary; Host is never echoed',
      () async {
        for (final String host in <String>[
          '203.0.113.9',
          'evil.example.net',
          '[::1]:8080',
        ]) {
          final Response r = await handleSsrFallback(
            request('http://$host/pricing'),
            site().path,
          );
          expect(r.status, 200, reason: host);
          final String html = await body(r);
          expect(canonical(html), 'https://example.com/pricing', reason: host);
          expect(html, isNot(contains('evil.example.net')));
        }
      },
    );

    test('the host description replaces only the site-wide one', () async {
      final Directory root = site();
      final String docsHome = await body(
        await handleSsrFallback(
          request('https://docs.example.com/'),
          root.path,
        ),
      );
      expect(description(docsHome), 'Reference for Example.');
      expect(siteName(docsHome), 'Example Docs');
      final String pricing = await body(
        await handleSsrFallback(
          request('https://example.com/pricing'),
          root.path,
        ),
      );
      expect(description(pricing), 'Site-wide description.');
      expect(siteName(pricing), 'Example');
    });

    test(
      'without hosts a page\'s own description still wins, canonical unchanged',
      () async {
        final Directory root = site(hosts: false);
        final String html = await body(
          await handleSsrFallback(
            request('https://docs.example.com/docs/x'),
            root.path,
          ),
        );
        expect(description(html), 'The page about X.');
        expect(canonical(html), 'https://example.com/docs/x');
        // No hosts: nothing redirects, whatever the Host says.
        final Response apps = await handleSsrFallback(
          request('https://example.com/apps/foo'),
          root.path,
        );
        expect(apps.status, 200);
        expect(canonical(await body(apps)), 'https://example.com/apps/foo');
      },
    );
  });

  group('the effective host behind a proxy', () {
    test('X-Forwarded-Host is honoured from a trusted proxy', () async {
      DVClientAddress.install(DVClientAddress.parse(<String>['10.0.0.0/8']));
      final String html = await body(
        await handleSsrFallback(
          request(
            'http://backend:8080/',
            headers: <String, String>{'x-forwarded-host': 'docs.example.com'},
            peer: '10.1.2.3:5000',
          ),
          site().path,
        ),
      );
      expect(canonical(html), 'https://docs.example.com');
    });

    test('and ignored from anybody else', () async {
      DVClientAddress.install(DVClientAddress.parse(<String>['10.0.0.0/8']));
      final String html = await body(
        await handleSsrFallback(
          request(
            'http://example.com/',
            headers: <String, String>{'x-forwarded-host': 'docs.example.com'},
            peer: '198.51.100.7:5000',
          ),
          site().path,
        ),
      );
      expect(canonical(html), 'https://example.com');
    });
  });

  test('two hosts never share a cached document', () async {
    final Directory root = site();
    final Response primary = await handleSsrFallback(
      request('https://example.com/'),
      root.path,
    );
    expect(
      primary.headers.get('etag'),
      isNotNull,
      reason: 'the home page is cacheable',
    );
    final String a = await body(primary);
    final String b = await body(
      await handleSsrFallback(request('https://docs.example.com/'), root.path),
    );
    final String c = await body(
      await handleSsrFallback(request('https://example.com/'), root.path),
    );
    expect(canonical(a), 'https://example.com');
    expect(canonical(b), 'https://docs.example.com');
    expect(c, a);
    // The same Host header, a different effective host behind a trusted proxy.
    DVClientAddress.install(DVClientAddress.parse(<String>['10.0.0.0/8']));
    final String viaProxy = await body(
      await handleSsrFallback(
        request(
          'http://backend/',
          headers: <String, String>{'x-forwarded-host': 'foo.apps.example.com'},
          peer: '10.0.0.2:1',
        ),
        root.path,
      ),
    );
    final String direct = await body(
      await handleSsrFallback(
        request('http://backend/', peer: '10.0.0.2:1'),
        root.path,
      ),
    );
    expect(canonical(viaProxy), 'https://foo.apps.example.com');
    expect(canonical(direct), 'https://example.com');
    // Identical headers, a different peer: a client that wrote the header
    // itself is the primary, and must not be handed the document kept for
    // the proxy's request, nor the other way round.
    const Map<String, String> same = <String, String>{
      'x-forwarded-host': 'docs.example.com',
    };
    final String spoofed = await body(
      await handleSsrFallback(
        request('http://example.com/', headers: same, peer: '198.51.100.7:1'),
        root.path,
      ),
    );
    final String proxied = await body(
      await handleSsrFallback(
        request('http://example.com/', headers: same, peer: '10.0.0.2:1'),
        root.path,
      ),
    );
    expect(canonical(spoofed), 'https://example.com');
    expect(canonical(proxied), 'https://docs.example.com');
  });

  test(
    'a guarded page sends a signed-out reader to the public sign-in URL',
    () async {
      final Response r = await handleSsrFallback(
        request('https://docs.example.com/private?tab=1'),
        site().path,
      );
      expect(r.status, 302);
      expect(
        r.headers.get('location'),
        'https://example.com/sign-in?from=%2Fdocs%2Fprivate%3Ftab%3D1',
      );
    },
  );

  group('robots.txt and sitemap.xml per host', () {
    Future<(int, String)> fetch(Directory root, String url) async {
      final Response? r = await dvHostSiteFile(request(url), root.path);
      if (r == null) return (0, '');
      return (r.status, await body(r));
    }

    test(
      'each host names its own sitemap and lists only its own URLs',
      () async {
        final Directory root = site();
        final (int rs, String robots) = await fetch(
          root,
          'https://docs.example.com/robots.txt',
        );
        expect(rs, 200);
        expect(
          robots,
          contains('Sitemap: https://docs.example.com/sitemap.xml'),
        );
        final (int ss, String sitemap) = await fetch(
          root,
          'https://docs.example.com/sitemap.xml',
        );
        expect(ss, 200);
        expect(sitemap, contains('<loc>https://docs.example.com/x</loc>'));
        expect(sitemap, contains('<loc>https://docs.example.com</loc>'));
        expect(sitemap, isNot(contains('https://example.com')));
        expect(sitemap, isNot(contains('apps.example.com')));
        expect(sitemap, contains('<urlset'));

        final (_, String primary) = await fetch(
          root,
          'https://example.com/sitemap.xml',
        );
        expect(primary, contains('<loc>https://example.com/pricing</loc>'));
        expect(primary, isNot(contains('docs.example.com')));

        final (_, String app) = await fetch(
          root,
          'https://foo.apps.example.com/sitemap.xml',
        );
        expect(
          app,
          contains('<loc>https://foo.apps.example.com/settings</loc>'),
        );
        expect(app, isNot(contains('<loc>https://example.com')));
      },
    );

    test('a wildcard label with no routes has neither', () async {
      final Directory root = site();
      expect(
        (await fetch(root, 'https://bar.apps.example.com/robots.txt')).$1,
        404,
      );
      expect(
        (await fetch(root, 'https://bar.apps.example.com/sitemap.xml')).$1,
        404,
      );
    });

    test('an unknown host is answered as the primary', () async {
      final (_, String robots) = await fetch(
        site(),
        'http://203.0.113.9/robots.txt',
      );
      expect(robots, contains('Sitemap: https://example.com/sitemap.xml'));
    });

    test('without hosts the files are left to the static handler', () async {
      final Directory root = site(hosts: false);
      expect(
        await dvHostSiteFile(
          request('https://docs.example.com/robots.txt'),
          root.path,
        ),
        isNull,
      );
      expect(
        await dvHostSiteFile(
          request('https://docs.example.com/sitemap.xml'),
          root.path,
        ),
        isNull,
      );
    });

    test('other paths are not its business', () async {
      expect(
        await dvHostSiteFile(
          request('https://docs.example.com/x'),
          site().path,
        ),
        isNull,
      );
    });
  });
}
