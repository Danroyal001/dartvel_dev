// dartvel.hosts on the client.
//
// foo.apps.example.com/ is the /apps/foo page. The server renders it so; the
// client has to agree after hydration and after every reload, or the reader
// sees the right page for a frame and then the home page. Links to a page of
// another host have to leave for that host, and links on a mounted host have
// to show the address the reader can share.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/link_interception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

DVHosts hosts() {
  final ({DVHosts hosts, List<String> problems}) parsed = DVHosts.parse(
    <String, Object?>{
      'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
      'docs.example.com': <String, Object?>{
        'mount': '/docs',
        'siteUrl': 'https://docs.example.com',
      },
      '*.apps.example.com': <String, Object?>{
        'mount': '/apps/{label}',
        'siteUrl': 'https://{label}.apps.example.com',
      },
    },
  );
  expect(parsed.problems, isEmpty);
  return parsed.hosts;
}

List<RouteBase> routes(Widget Function(String path) page) => <RouteBase>[
  for (final String path in const <String>[
    '/',
    '/pricing',
    '/docs',
    '/docs/x',
    '/apps/foo',
    '/apps/foo/settings',
  ])
    GoRoute(
      path: path,
      builder: (BuildContext context, GoRouterState state) => page(path),
    ),
];

Widget label(String path) => Scaffold(body: Text('page $path'));

Future<DVRouter> pumpRouter(
  WidgetTester tester, {
  String initialLocation = '/',
  Widget Function(String path) page = label,
}) async {
  final DVRouter router = DVRouter(
    initialLocation: initialLocation,
    routes: routes(page),
  );
  addTearDown(router.dispose);
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// The address the router would put in the browser's address bar.
String addressBar(DVRouter router) => router.routeInformationParser
    .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
    .uri
    .toString();

void main() {
  tearDown(dvResetHosts);

  test('the table a generated router declares is a const DVHosts', () {
    // The shape the CLI writes into router.g.dart.
    const DVHosts dartvelHosts = DVHosts(<DVHostEntry>[
      DVHostEntry(
        pattern: 'example.com',
        siteUrl: 'https://example.com',
        mount: '/',
      ),
      DVHostEntry(
        pattern: '*.apps.example.com',
        siteUrl: 'https://{label}.apps.example.com',
        mount: '/apps/{label}',
      ),
    ]);
    dvUseHosts(dartvelHosts, host: 'foo.apps.example.com');
    expect(dvLocationFromPlatform('/'), '/apps/foo');
  });

  group('the location each host shows', () {
    test('a mounted host maps a location outside its mount into it', () {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      expect(dvLocationFromPlatform('/'), '/apps/foo');
      expect(
        dvLocationFromPlatform('/settings?tab=1'),
        '/apps/foo/settings?tab=1',
      );
      // Already internal: an in-app navigation, left alone.
      expect(
        dvLocationFromPlatform('/apps/foo/settings'),
        '/apps/foo/settings',
      );
      expect(
        dvLocationToPlatform('/apps/foo/settings?tab=1'),
        '/settings?tab=1',
      );
      expect(dvLocationToPlatform('/apps/foo'), '/');
    });

    test('the primary host and no hosts change nothing', () {
      dvUseHosts(hosts(), host: 'example.com');
      expect(dvLocationFromPlatform('/docs/x'), '/docs/x');
      expect(dvLocationToPlatform('/docs/x'), '/docs/x');
      dvResetHosts();
      expect(dvLocationFromPlatform('/x'), '/x');
      expect(dvLocationToPlatform('/x'), '/x');
    });

    test('an unknown host is the primary', () {
      dvUseHosts(hosts(), host: 'localhost');
      expect(dvCurrentHost!.entry.pattern, 'example.com');
      expect(dvLocationFromPlatform('/'), '/');
    });
  });

  group('public locations', () {
    test('same host: the path without the mount', () {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      expect(dvPublicLocation('/apps/foo/settings'), '/settings');
      expect(dvPublicLocation('/apps/foo'), '/');
      expect(
        dvPublicLocation('/apps/foo/settings?tab=1#a'),
        '/settings?tab=1#a',
      );
    });

    test('another host: an absolute URL there', () {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      expect(dvPublicLocation('/pricing'), 'https://example.com/pricing');
      expect(dvPublicLocation('/docs/x?q=1'), 'https://docs.example.com/x?q=1');
      dvUseHosts(hosts(), host: 'example.com');
      expect(dvPublicLocation('/docs/x'), 'https://docs.example.com/x');
      expect(dvPublicLocation('/pricing'), '/pricing');
    });

    test('another host of the application is not leaving the site', () {
      const DVLinkActivation toDocs = DVLinkActivation(
        href: 'https://docs.example.com/x',
        currentUrl: 'https://example.com/',
      );
      // Without hosts it is another site, opened beside.
      expect(dvLinkLeavesTheSite(toDocs), isTrue);
      dvUseHosts(hosts(), host: 'example.com');
      // With them, a page of this application: followed in this tab.
      expect(dvLinkLeavesTheSite(toDocs), isFalse);
      expect(
        dvRoutedLinkPath(toDocs),
        isNull,
        reason: 'another origin is never routed here',
      );
      expect(
        dvLinkLeavesTheSite(
          const DVLinkActivation(
            href: 'https://pub.dev/',
            currentUrl: 'https://example.com/',
          ),
        ),
        isTrue,
      );
    });

    test('no hosts: the location itself', () {
      expect(dvPublicLocation('/docs/x'), '/docs/x');
    });

    test('the canonical URL for the page the reader is on', () {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      expect(
        dvHostCanonicalUrl('/settings'),
        'https://foo.apps.example.com/settings',
      );
      expect(dvHostCanonicalUrl('/'), 'https://foo.apps.example.com');
      dvResetHosts();
      expect(dvHostCanonicalUrl('/settings'), isNull);
    });
  });

  group('DVRouter', () {
    testWidgets('a wildcard host\'s / resolves its mount on first load', (
      WidgetTester tester,
    ) async {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      final DVRouter router = await pumpRouter(tester);
      expect(find.text('page /apps/foo'), findsOneWidget);
      expect(router.state.uri.path, '/apps/foo');
      expect(addressBar(router), '/');
    });

    testWidgets('a reload onto a deeper path resolves under the mount', (
      WidgetTester tester,
    ) async {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      final DVRouter router = await pumpRouter(tester);
      // What the platform reports on a reload or a typed address.
      unawaited(
        router.routeInformationProvider.didPushRouteInformation(
          RouteInformation(uri: Uri.parse('/settings')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('page /apps/foo/settings'), findsOneWidget);
      expect(addressBar(router), '/settings');
    });

    testWidgets('in-app navigation under the mount shows the host path', (
      WidgetTester tester,
    ) async {
      dvUseHosts(hosts(), host: 'docs.example.com');
      final DVRouter router = await pumpRouter(tester);
      expect(find.text('page /docs'), findsOneWidget);
      router.go('/docs/x');
      await tester.pumpAndSettle();
      expect(find.text('page /docs/x'), findsOneWidget);
      expect(addressBar(router), '/x');
    });

    testWidgets('the primary host is untouched', (WidgetTester tester) async {
      dvUseHosts(hosts(), host: 'example.com');
      final DVRouter router = await pumpRouter(tester);
      expect(find.text('page /'), findsOneWidget);
      router.go('/docs/x');
      await tester.pumpAndSettle();
      expect(addressBar(router), '/docs/x');
    });

    testWidgets('without hosts the parser is go_router\'s own', (
      WidgetTester tester,
    ) async {
      final DVRouter router = await pumpRouter(tester);
      expect(
        router.routeInformationParser.runtimeType,
        GoRouteInformationParser,
      );
      expect(find.text('page /'), findsOneWidget);
    });
  });

  group('DVNavLink across hosts', () {
    final List<(String, bool)> opened = <(String, bool)>[];
    setUp(() {
      opened.clear();
      DVLinkOpener.install((String path, {bool newTab = false}) {
        opened.add((path, newTab));
      });
    });
    tearDown(DVLinkOpener.reset);

    Widget linkTo(String to) => Scaffold(
      body: DVNavLink(
        to: DVRouteTarget(to),
        preload: DVLinkPreload.none,
        preview: DVLinkPreview.none,
        child: const Text('the link'),
      ),
    );

    Uri? linkUrl(WidgetTester tester) {
      final SemanticsNode node = tester.getSemantics(find.text('the link'));
      SemanticsNode? n = node;
      while (n != null && !n.getSemanticsData().flagsCollection.isLink) {
        n = n.parent;
      }
      return n?.getSemanticsData().linkUrl;
    }

    testWidgets('a link to another host carries its URL and leaves for it', (
      WidgetTester tester,
    ) async {
      dvUseHosts(hosts(), host: 'example.com');
      final SemanticsHandle semantics = tester.ensureSemantics();
      final DVRouter router = await pumpRouter(
        tester,
        page: (String path) => path == '/' ? linkTo('/docs/x') : label(path),
      );
      expect(linkUrl(tester), Uri.parse('https://docs.example.com/x'));
      await tester.tap(find.text('the link'));
      await tester.pumpAndSettle();
      expect(opened, <(String, bool)>[('https://docs.example.com/x', false)]);
      expect(router.state.uri.path, '/', reason: 'not an in-app route change');
      semantics.dispose();
    });

    testWidgets('a link on the same host shows the path without the mount', (
      WidgetTester tester,
    ) async {
      dvUseHosts(hosts(), host: 'foo.apps.example.com');
      final SemanticsHandle semantics = tester.ensureSemantics();
      final DVRouter router = await pumpRouter(
        tester,
        page: (String path) =>
            path == '/apps/foo' ? linkTo('/apps/foo/settings') : label(path),
      );
      expect(linkUrl(tester), Uri.parse('/settings'));
      await tester.tap(find.text('the link'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('page /apps/foo/settings'), findsOneWidget);
      expect(addressBar(router), '/settings');
      semantics.dispose();
    });

    testWidgets('without hosts a link is what it was', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpRouter(
        tester,
        page: (String path) => path == '/' ? linkTo('/docs/x') : label(path),
      );
      expect(linkUrl(tester), Uri.parse('/docs/x'));
      await tester.tap(find.text('the link'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('page /docs/x'), findsOneWidget);
      semantics.dispose();
    });
  });
}
