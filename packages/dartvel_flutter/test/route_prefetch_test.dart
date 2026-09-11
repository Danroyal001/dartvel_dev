// A link that preloads fetches the page's HTML and images as well as its
// Dart.
//
// `loadLibrary()` fetches the page's code and nothing else. The prerendered
// page a route is served as -- what a new tab, a reload or a shared link
// opens -- and the images the page shows were left to be fetched when the
// visitor got there. On the web a link now asks the browser for both, with a
// <link rel="prefetch"> each, and hands every image to Flutter's image cache
// once the browser has it, so the page paints them on its first frame.
//
// The DOM half is exercised in route_prefetch_browser_test.dart. This is the
// part that holds on every platform: which document and which images, the
// mapping from a URL back to the image provider the page itself will ask for,
// and the link calling all of it.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String manifest = '''
{"routes": {
  "/docs": {
    "scripts": ["main.dart.js_2.part.js"],
    "images": [
      {"url": "assets/assets/hero.png", "as": "fetch"},
      {"url": "https://cdn.example.com/a.jpg", "as": "image"}
    ]
  },
  "/": {"scripts": [], "images": []}
}}
''';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: subject),
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('docs page')),
        ),
      ],
    );

Future<void> pump(WidgetTester tester, Widget subject) async {
  final router = routerWith(subject);
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
  await tester.pump();
}

Widget link({Future<void> Function()? onPreload}) => DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.immediate,
      onPreload: onPreload ?? () async {},
      child: const DVText('Docs'),
    );

void main() {
  setUp(DVRoutePrefetch.reset);
  tearDown(DVRoutePrefetch.reset);

  group('the document a route is served as', () {
    test('is its path, relative to the base the site is served from', () {
      expect(dvPrefetchHref('/docs'), 'docs');
      expect(dvPrefetchHref('/docs/intro'), 'docs/intro');
    });

    test('the root is the base itself', () {
      expect(dvPrefetchHref('/'), './');
    });

    test('without the query or fragment, which pick data, not a document', () {
      expect(dvPrefetchHref('/docs?tab=2#install'), 'docs');
    });
  });

  group('the images the build listed for a route', () {
    test('are read from the manifest', () {
      expect(dvPrefetchImages(manifest, '/docs'), <String>[
        'assets/assets/hero.png',
        'https://cdn.example.com/a.jpg',
      ]);
    });

    test('a query or a trailing slash is the same route', () {
      expect(dvPrefetchImages(manifest, '/docs?tab=2'), hasLength(2));
      expect(dvPrefetchImages(manifest, '/docs/'), hasLength(2));
    });

    test('a route the build knows nothing about has none', () {
      expect(dvPrefetchImages(manifest, '/pricing'), isEmpty);
      expect(dvPrefetchImages(manifest, '/'), isEmpty);
    });

    test('a missing or broken manifest prefetches nothing and throws nothing',
        () {
      // An optimisation that throws is worse than none: this runs on the way
      // to a tap.
      for (final String? broken in <String?>[
        null,
        '',
        'not json',
        '[]',
        '{"routes": []}',
        '{"routes": {"/docs": {"images": "x"}}}',
        '{"routes": {"/docs": {"images": [1, {"url": 2}]}}}',
      ]) {
        expect(dvPrefetchImages(broken, '/docs'), isEmpty, reason: '$broken');
      }
    });
  });

  group('an image address back to what the page will ask for', () {
    // The cache is keyed by provider, not by URL. Precaching the right bytes
    // under the wrong key decodes them for nothing and the page fetches again.
    test('an asset is the AssetImage the page names', () {
      expect(DVRoutePrefetch.providerFor('assets/assets/hero.png'),
          const AssetImage('assets/hero.png'));
    });

    test('a resolution variant is the same asset', () {
      // The capture runs at one device pixel ratio. AssetImage picks the
      // variant for this screen itself, from the name the page used.
      expect(DVRoutePrefetch.providerFor('assets/assets/2.0x/hero.png'),
          const AssetImage('assets/hero.png'));
      expect(DVRoutePrefetch.providerFor('assets/assets/icons/3.0x/star.png'),
          const AssetImage('assets/icons/star.png'));
    });

    test('a package\'s asset keeps its package path', () {
      expect(DVRoutePrefetch.providerFor('assets/packages/icons/star.png'),
          const AssetImage('packages/icons/star.png'));
    });

    test('anything else is a network image at that address', () {
      expect(DVRoutePrefetch.providerFor('https://cdn.example.com/a.jpg'),
          const NetworkImage('https://cdn.example.com/a.jpg'));
    });
  });

  test('off the web there is no document to fetch', () async {
    expect(await DVRoutePrefetch.fetch('/docs'), isEmpty);
  });

  group('a link that preloads', () {
    testWidgets('fetches the page\'s document as well as its code',
        (WidgetTester tester) async {
      final List<String> asked = <String>[];
      DVRoutePrefetch.fetch = (String path) async {
        asked.add(path);
        return const <String>[];
      };
      var loads = 0;

      await pump(tester, link(onPreload: () async => loads++));

      expect(asked, <String>['/docs']);
      expect(loads, 1, reason: 'in addition to loadLibrary, not instead of it');
    });

    testWidgets('once, however many times it is triggered',
        (WidgetTester tester) async {
      var asked = 0;
      DVRoutePrefetch.fetch = (String path) async {
        asked++;
        return const <String>[];
      };

      await pump(tester, link());
      await tester.pump(const Duration(seconds: 1));

      expect(asked, 1);
    });

    testWidgets('hands each image to Flutter\'s cache',
        (WidgetTester tester) async {
      final List<String> precached = <String>[];
      DVRoutePrefetch.fetch = (String path) async => const <String>[
            'assets/assets/hero.png',
            'https://cdn.example.com/a.jpg',
          ];
      DVRoutePrefetch.precache = (BuildContext context, String url) async {
        precached.add(url);
      };

      await pump(tester, link());

      expect(precached, <String>[
        'assets/assets/hero.png',
        'https://cdn.example.com/a.jpg',
      ]);
    });

    testWidgets('but not once the link is gone', (WidgetTester tester) async {
      final Completer<List<String>> document = Completer<List<String>>();
      final List<String> precached = <String>[];
      DVRoutePrefetch.fetch = (String path) => document.future;
      DVRoutePrefetch.precache = (BuildContext context, String url) async {
        precached.add(url);
      };

      await pump(tester, link());
      await tester.pumpWidget(const SizedBox());
      document.complete(const <String>['assets/assets/hero.png']);
      await tester.pump();

      // The link's context is gone. Using it would throw, and the page the
      // images were for is no longer one the visitor is about to open.
      expect(precached, isEmpty);
    });

    testWidgets('a document that cannot be fetched does not stop the preload',
        (WidgetTester tester) async {
      DVRoutePrefetch.fetch = (String path) async => throw StateError('offline');
      var loads = 0;

      await pump(tester, link(onPreload: () async => loads++));

      expect(loads, 1);
      expect(tester.takeException(), isA<StateError>(),
          reason: 'reported, not swallowed: a prefetch that silently never '
              'works is a performance bug nobody can see');
    });

    testWidgets('a link that does not preload fetches nothing',
        (WidgetTester tester) async {
      var asked = 0;
      DVRoutePrefetch.fetch = (String path) async {
        asked++;
        return const <String>[];
      };

      await pump(
        tester,
        const DVNavLink(
          to: DVRouteTarget('/docs'),
          preload: DVLinkPreload.none,
          child: DVText('Docs'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(asked, 0);
    });
  });
}
