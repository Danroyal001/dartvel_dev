// The prefetch links, in a real document.
//
// route_prefetch_test.dart covers what is fetched and the link calling it on
// every platform. This is the half only a browser has: that a <link> really
// lands in <head>, once per address, and that an image the browser could not
// fetch is not handed on to Flutter to fail a second time.
//
// Run with: flutter test --platform chrome test/route_prefetch_browser_test.dart
@TestOn('browser')
library;

import 'package:dartvel_flutter/src/routing/route_prefetch_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

int linksTo(String href, {String? as}) => web.document
    .querySelectorAll('link[rel="prefetch"][href="$href"]'
        '${as == null ? '' : '[as="$as"]'}')
    .length;

void main() {
  setUp(() {
    dvResetPrefetchDocument();
    final web.NodeList old = web.document.querySelectorAll('link[rel="prefetch"]');
    for (int i = 0; i < old.length; i++) {
      final web.Node? node = old.item(i);
      node?.parentNode?.removeChild(node);
    }
  });

  test('the route\'s document is prefetched', () async {
    dvPrefetchManifestLoader = () async => null;

    await dvPrefetchDocument('/docs');

    expect(linksTo('docs'), 1);
  });

  test('once, however many links point at it', () async {
    dvPrefetchManifestLoader = () async => null;

    await dvPrefetchDocument('/docs');
    await dvPrefetchDocument('/docs');
    await dvPrefetchDocument('/docs?tab=2');

    expect(linksTo('docs'), 1);
  });

  test('the manifest is read once for every link on the page', () async {
    var reads = 0;
    dvPrefetchManifestLoader = () async {
      reads++;
      return null;
    };

    await dvPrefetchDocument('/docs');
    await dvPrefetchDocument('/cloud');

    expect(reads, 1);
  });

  test('each image the build recorded is prefetched as an image', () async {
    dvPrefetchManifestLoader = () async => '{"routes": {"/docs": {'
        '"images": [{"url": "dv-prefetch-missing.png", "as": "fetch"}]}}}';

    final List<String> fetched = await dvPrefetchDocument('/docs');

    expect(linksTo('dv-prefetch-missing.png', as: 'image'), 1);
    // Nothing is served at that address. Handing it to Flutter anyway would
    // be a second request for something already known to fail.
    expect(fetched, isEmpty);
  });

  test('a site without a manifest still prefetches its documents', () async {
    dvPrefetchManifestLoader = () async => 'not json';

    expect(await dvPrefetchDocument('/'), isEmpty);
    expect(linksTo('./'), 1);
  });
}
