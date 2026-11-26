// The rendered-page cache filled after the server starts, so the first real
// visitor of a static page gets a kept page rather than waiting for a render.
// Sequential, nothing user-specific, off with DARTVEL_OFF=cache-warm.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:test/test.dart';

final Uri _origin = Uri.parse('http://127.0.0.1:8740');

Directory _site({Map<String, Object?> extraRoutes = const <String, Object?>{}}) {
  final Directory root = Directory.systemTemp.createTempSync('dv-cache-warm-');
  File('${root.path}/index.html').writeAsStringSync(
      '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>App</title></head><body></body></html>');
  File('${root.path}/dartvel_routes.json').writeAsStringSync(jsonEncode(<String, Object?>{
    'siteUrl': 'https://example.com',
    'routes': <String, Object?>{
      '/': <String, Object?>{'title': 'Home', 'text': <String>['Welcome']},
      '/pricing': <String, Object?>{'title': 'Pricing', 'text': <String>['Plans']},
      '/jobs/:id': <String, Object?>{'title': 'Job'},
      '/private': <String, Object?>{'guarded': true},
      '/clock': <String, Object?>{'title': 'Clock', 'cache': false},
      '/elsewhere': <String, Object?>{'location': 'https://other.example/'},
      ...extraRoutes,
    },
  }));
  return root;
}

/// A visitor's request as the server builds it: its URL on the bound
/// address, and the headers a proxy and a browser send.
Request _visitor(String path, {Map<String, String> extra = const <String, String>{}}) => Request(
      method: 'GET',
      url: _origin.replace(path: path),
      headers: Headers(<String, String>{
        'host': 'example.com',
        'user-agent': 'Mozilla/5.0 (Test)',
        'accept': 'text/html',
        'accept-encoding': 'gzip, br',
        'x-forwarded-for': '203.0.113.9',
        ...extra,
      }),
      bodyStream: const Stream<List<int>>.empty(),
    );

void main() {
  late Directory root;
  setUp(() {
    dvPurgeRenderedPages();
    root = _site();
  });
  tearDown(() {
    DVOffSwitches.current = DVOffSwitches.none;
    root.deleteSync(recursive: true);
  });

  test('warms each static, cacheable route once; the first visitor is served from it', () async {
    final DVCacheWarmResult warmed = await dvWarmRenderedPages(root.path, origin: _origin, delay: Duration.zero);
    expect(warmed.paths, <String>['/', '/pricing']);
    expect(warmed.pages, 2);
    final int renders = dvSsrRenderCount;
    final Response page = await handleSsrFallback(_visitor('/pricing'), root.path);
    expect(page.status, 200);
    expect(utf8.decode(await page.body!.bytes()), contains('Pricing'));
    expect(dvSsrRenderCount, renders, reason: 'served from the warmed cache, not rendered again');
    await handleSsrFallback(_visitor('/clock'), root.path);
    expect(dvSsrRenderCount, renders + 1, reason: 'a route that opted out is still rendered per request');
  });

  test('with a default locale, also warmed for a visitor asking for it', () async {
    root.deleteSync(recursive: true);
    root = _site(extraRoutes: <String, Object?>{
      '/about': <String, Object?>{
        'title': 'About',
        'page': <String, Object?>{
          'route': '/about',
          'title': 'About',
          'alternates': <String, String>{'en': 'https://example.com/about', 'fr': 'https://example.com/fr/about'},
          'defaultAlternate': 'https://example.com/about',
        },
      },
    });
    final DVCacheWarmResult warmed = await dvWarmRenderedPages(root.path, origin: _origin, delay: Duration.zero);
    expect(warmed.pages, 6, reason: 'three routes, without Accept-Language and with en');
    final int renders = dvSsrRenderCount;
    await handleSsrFallback(_visitor('/about', extra: const <String, String>{'accept-language': 'en'}), root.path);
    await handleSsrFallback(_visitor('/about'), root.path);
    expect(dvSsrRenderCount, renders);
  });

  test('stops when the server does', () async {
    int asked = 0;
    final DVCacheWarmResult warmed = await dvWarmRenderedPages(root.path,
        origin: _origin, delay: Duration.zero, stopped: () => asked++ > 0);
    expect(warmed.pages, 1);
  });

  test('cache-warm switched off: nothing is rendered', () async {
    DVOffSwitches.current = DVOffSwitches.parse('cache-warm');
    final int renders = dvSsrRenderCount;
    final DVCacheWarmResult warmed = await dvWarmRenderedPages(root.path, origin: _origin, delay: Duration.zero);
    expect(warmed.pages, 0);
    expect(warmed.switchedOff, isTrue);
    expect(dvSsrRenderCount, renders);
  });

  test('a site with no manifest warms nothing', () async {
    File('${root.path}/dartvel_routes.json').deleteSync();
    expect((await dvWarmRenderedPages(root.path, origin: _origin, delay: Duration.zero)).pages, 0);
  });

  test('the log line', () {
    expect(const DVCacheWarmResult(pages: 3, paths: <String>['/', '/a', '/b'], elapsed: Duration(milliseconds: 42)).describe(),
        'dartvel: cache warm: 3 pages in 42 ms');
  });
}
