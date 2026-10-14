import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVHostEntry, DVHostRoutingConfig;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html><head><!-- dartvel:seo -->
<title>Default Shell Title</title>
<!-- /dartvel:seo -->
</head><body><div class="app"></div></body></html>
''';

Directory createSite() {
  final Directory root = Directory.systemTemp.createTempSync('dv_host_ssr_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);

  const hostConfig = DVHostRoutingConfig(
    trustedProxies: {'127.0.0.1'},
    trustLoopback: true,
    entries: [
      DVHostEntry(
        pattern: 'sigmadev.digital',
        siteUrl: 'https://sigmadev.digital',
        name: 'SigmaDev Digital',
        description: 'Websites and apps',
      ),
      DVHostEntry(
        pattern: 'tools.sigmadev.digital',
        siteUrl: 'https://tools.sigmadev.digital',
        mount: '/tools',
        name: 'SigmaDev Tools',
        description: 'Free developer tools',
      ),
      DVHostEntry(
        pattern: '*.tools.sigmadev.digital',
        siteUrl: 'https://{slug}.tools.sigmadev.digital',
        mount: '/tools/{slug}',
      ),
    ],
  );

  final manifest = <String, Object?>{
    'siteUrl': 'https://sigmadev.digital',
    'site': <String, Object?>{
      'name': 'SigmaDev Digital',
      'description': 'Websites and apps',
    },
    'hosts': hostConfig.toJson(),
    'server': <String, Object?>{},
    'routes': <String, Object?>{
      '/': <String, Object?>{
        'title': 'SigmaDev Digital — Software Agency',
        'text': ['Welcome to SigmaDev'],
      },
      '/about': <String, Object?>{
        'title': 'About SigmaDev',
        'text': ['About us'],
      },
      '/tools': <String, Object?>{
        'title': 'Free Developer Tools — SigmaDev',
        'text': ['Browse all 176 tools'],
      },
      '/tools/base64-encode': <String, Object?>{
        'title': 'Base64 Encoder & Decoder — Free Online Tool',
        'text': ['Encode and decode base64 strings'],
      },
      '/tools/uuid-generator': <String, Object?>{
        'title': 'UUID Generator — Free Online Tool',
        'text': ['Generate random UUIDs'],
      },
    },
  };

  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(manifest));
  return root;
}

Future<Response> request({
  required Directory site,
  required String host,
  required String path,
  Map<String, String> headers = const {},
}) async {
  final requestHeaders = Headers({
    'host': host,
    ...headers,
  });
  return handleSsrFallback(
    Request(
      method: 'GET',
      url: Uri.parse('http://$host$path'),
      headers: requestHeaders,
      bodyStream: const Stream<List<int>>.empty(),
    ),
    site.path,
  );
}

Future<String> readBody(Response response) async {
  final chunks = await response.body!.stream.toList();
  return utf8.decode(<int>[for (final chunk in chunks) ...chunk]);
}

void main() {
  late Directory site;

  setUp(() {
    site = createSite();
  });

  group('main domain (sigmadev.digital)', () {
    test('serves homepage with correct canonical and title', () async {
      final res = await request(site: site, host: 'sigmadev.digital', path: '/');
      expect(res.status, 200);
      final html = await readBody(res);
      expect(html, contains('<title>SigmaDev Digital — Software Agency</title>'));
      expect(html, contains('<link rel="canonical" href="https://sigmadev.digital">'));
      expect(html, contains('Welcome to SigmaDev'));
    });

    test('serves about page with correct canonical', () async {
      final res = await request(site: site, host: 'sigmadev.digital', path: '/about');
      expect(res.status, 200);
      final html = await readBody(res);
      expect(html, contains('<title>About SigmaDev</title>'));
      expect(html, contains('<link rel="canonical" href="https://sigmadev.digital/about">'));
    });

    test('301 redirects legacy /tools to tools.sigmadev.digital/', () async {
      final res1 = await request(site: site, host: 'sigmadev.digital', path: '/tools');
      expect(res1.status, 301);
      expect(res1.headers.get('location'), 'https://tools.sigmadev.digital/');

      final res2 = await request(site: site, host: 'sigmadev.digital', path: '/tools/');
      expect(res2.status, 301);
      expect(res2.headers.get('location'), 'https://tools.sigmadev.digital/');

      final res3 = await request(site: site, host: 'sigmadev.digital', path: '/tools?query=test');
      expect(res3.status, 301);
      expect(res3.headers.get('location'), 'https://tools.sigmadev.digital/?query=test');
    });

    test('301 redirects legacy /tools/<slug> to <slug>.tools.sigmadev.digital/ for registered tool', () async {
      final res = await request(
        site: site,
        host: 'sigmadev.digital',
        path: '/tools/base64-encode?input=hello',
      );
      expect(res.status, 301);
      expect(
        res.headers.get('location'),
        'https://base64-encode.tools.sigmadev.digital/?input=hello',
      );
    });

    test('does not redirect unregistered tool path, returns 404', () async {
      final res = await request(site: site, host: 'sigmadev.digital', path: '/tools/unknown-tool');
      expect(res.status, 404);
    });
  });

  group('tools index subdomain (tools.sigmadev.digital)', () {
    test('serves tools index page at path / with own canonical and SEO', () async {
      final res = await request(site: site, host: 'tools.sigmadev.digital', path: '/');
      expect(res.status, 200);
      final html = await readBody(res);
      expect(html, contains('<title>Free Developer Tools — SigmaDev</title>'));
      expect(html, contains('<link rel="canonical" href="https://tools.sigmadev.digital">'));
      expect(html, contains('Browse all 176 tools'));
    });
  });

  group('per-tool subdomain (*.tools.sigmadev.digital)', () {
    test('serves tool detail page at path / with own canonical and SEO', () async {
      final res = await request(
        site: site,
        host: 'base64-encode.tools.sigmadev.digital',
        path: '/',
      );
      expect(res.status, 200);
      final html = await readBody(res);
      expect(html, contains('<title>Base64 Encoder &amp; Decoder — Free Online Tool</title>'));
      expect(html, contains('<link rel="canonical" href="https://base64-encode.tools.sigmadev.digital">'));
      expect(html, contains('Encode and decode base64 strings'));
    });

    test('returns 404 for unknown tool slug without echoing host into title', () async {
      final res = await request(
        site: site,
        host: 'unknown-tool.tools.sigmadev.digital',
        path: '/',
      );
      expect(res.status, 404);
      final html = await readBody(res);
      expect(html, isNot(contains('unknown-tool')));
    });

    test('rejects multi-label wildcard subdomains with 404', () async {
      final res = await request(
        site: site,
        host: 'sub.base64-encode.tools.sigmadev.digital',
        path: '/',
      );
      expect(res.status, 404);
    });

    test('serves tool detail page with JSON-LD WebApplication and BreadcrumbList', () async {
      final res = await request(
        site: site,
        host: 'base64-encode.tools.sigmadev.digital',
        path: '/',
      );
      expect(res.status, 200);
      final html = await readBody(res);
      expect(html, contains('application/ld+json'));
      expect(html, contains('"@type":"WebApplication"'));
      expect(html, contains('"@type":"BreadcrumbList"'));
      expect(html, contains('https://base64-encode.tools.sigmadev.digital'));
    });

    test('serves host-specific robots.txt on tool subdomain', () async {
      final res = await request(
        site: site,
        host: 'base64-encode.tools.sigmadev.digital',
        path: '/robots.txt',
      );
      expect(res.status, 200);
      final body = await readBody(res);
      expect(body, contains('User-agent: *'));
      expect(body, contains('Sitemap: https://base64-encode.tools.sigmadev.digital/sitemap.xml'));
    });

    test('serves host-specific sitemap.xml on tool subdomain', () async {
      final res = await request(
        site: site,
        host: 'base64-encode.tools.sigmadev.digital',
        path: '/sitemap.xml',
      );
      expect(res.status, 200);
      final xml = await readBody(res);
      expect(xml, contains('<loc>https://base64-encode.tools.sigmadev.digital/</loc>'));
      expect(xml, isNot(contains('sigmadev.digital/about')));
    });
  });

  group('security & proxy trust', () {
    test('ignores untrusted X-Forwarded-Host from untrusted connection', () async {
      // remoteAddress is not trusted
      final res = await request(
        site: site,
        host: 'sigmadev.digital',
        path: '/',
        headers: {
          'x-forwarded-host': 'tools.sigmadev.digital',
        },
      );
      expect(res.status, 200);
      final html = await readBody(res);
      // Still serves sigmadev.digital, not tools.sigmadev.digital!
      expect(html, contains('<title>SigmaDev Digital — Software Agency</title>'));
    });

    test('rejects invalid host header syntax with 400', () async {
      final res = await request(site: site, host: 'invalid..host/name', path: '/');
      expect(res.status, 400);
    });
  });
}
