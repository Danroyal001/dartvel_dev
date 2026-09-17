// The docs hold together: every page is reachable from every other, each
// renders all of its sections at desktop and phone width, and two live copies
// of a page (which a link preview makes) both keep their sections.
import 'package:dartvel_site/components/docs.dart';
import 'package:dartvel_site/components/docs_page_info.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:dartvel_site/pages/docs/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each docs page's generated widget and deferred loader, by path.
final Map<String, (Widget Function(), Future<void> Function())> docsWidgets =
    <String, (Widget Function(), Future<void> Function())>{
  '/docs': (() => const DocsPageGeneratedPage(), DocsPageGeneratedPage.loadLibrary),
  '/docs/ui': (() => const DocsUiPageGeneratedPage(), DocsUiPageGeneratedPage.loadLibrary),
  '/docs/routing': (() => const DocsRoutingPageGeneratedPage(), DocsRoutingPageGeneratedPage.loadLibrary),
  '/docs/state': (() => const DocsStatePageGeneratedPage(), DocsStatePageGeneratedPage.loadLibrary),
  '/docs/accessibility': (() => const DocsAccessibilityPageGeneratedPage(), DocsAccessibilityPageGeneratedPage.loadLibrary),
  '/docs/localization': (() => const DocsLocalizationPageGeneratedPage(), DocsLocalizationPageGeneratedPage.loadLibrary),
  '/docs/models': (() => const DocsModelsPageGeneratedPage(), DocsModelsPageGeneratedPage.loadLibrary),
  '/docs/database': (() => const DocsDatabasePageGeneratedPage(), DocsDatabasePageGeneratedPage.loadLibrary),
  '/docs/forms': (() => const DocsFormsPageGeneratedPage(), DocsFormsPageGeneratedPage.loadLibrary),
  '/docs/search': (() => const DocsSearchPageGeneratedPage(), DocsSearchPageGeneratedPage.loadLibrary),
  '/docs/sync': (() => const DocsSyncPageGeneratedPage(), DocsSyncPageGeneratedPage.loadLibrary),
  '/docs/import-export': (() => const DocsImportExportPageGeneratedPage(), DocsImportExportPageGeneratedPage.loadLibrary),
  '/docs/change-capture': (() => const DocsChangeCapturePageGeneratedPage(), DocsChangeCapturePageGeneratedPage.loadLibrary),
  '/docs/backend-functions': (() => const DocsBackendFunctionsPageGeneratedPage(), DocsBackendFunctionsPageGeneratedPage.loadLibrary),
  '/docs/auth': (() => const DocsAuthPageGeneratedPage(), DocsAuthPageGeneratedPage.loadLibrary),
  '/docs/authorization': (() => const DocsAuthorizationPageGeneratedPage(), DocsAuthorizationPageGeneratedPage.loadLibrary),
  '/docs/queues': (() => const DocsQueuesPageGeneratedPage(), DocsQueuesPageGeneratedPage.loadLibrary),
  '/docs/workers': (() => const DocsWorkersPageGeneratedPage(), DocsWorkersPageGeneratedPage.loadLibrary),
  '/docs/cache': (() => const DocsCachePageGeneratedPage(), DocsCachePageGeneratedPage.loadLibrary),
  '/docs/notifications': (() => const DocsNotificationsPageGeneratedPage(), DocsNotificationsPageGeneratedPage.loadLibrary),
  '/docs/storage': (() => const DocsStoragePageGeneratedPage(), DocsStoragePageGeneratedPage.loadLibrary),
  '/docs/media': (() => const DocsMediaPageGeneratedPage(), DocsMediaPageGeneratedPage.loadLibrary),
  '/docs/http': (() => const DocsHttpPageGeneratedPage(), DocsHttpPageGeneratedPage.loadLibrary),
  '/docs/ai': (() => const DocsAiPageGeneratedPage(), DocsAiPageGeneratedPage.loadLibrary),
  '/docs/webhooks': (() => const DocsWebhooksPageGeneratedPage(), DocsWebhooksPageGeneratedPage.loadLibrary),
  '/docs/graphql': (() => const DocsGraphqlPageGeneratedPage(), DocsGraphqlPageGeneratedPage.loadLibrary),
  '/docs/platform-api': (() => const DocsPlatformApiPageGeneratedPage(), DocsPlatformApiPageGeneratedPage.loadLibrary),
  '/docs/edge-security': (() => const DocsEdgeSecurityPageGeneratedPage(), DocsEdgeSecurityPageGeneratedPage.loadLibrary),
  '/docs/tenancy': (() => const DocsTenancyPageGeneratedPage(), DocsTenancyPageGeneratedPage.loadLibrary),
  '/docs/organizations': (() => const DocsOrganizationsPageGeneratedPage(), DocsOrganizationsPageGeneratedPage.loadLibrary),
  '/docs/privacy': (() => const DocsPrivacyPageGeneratedPage(), DocsPrivacyPageGeneratedPage.loadLibrary),
  '/docs/building': (() => const DocsBuildingPageGeneratedPage(), DocsBuildingPageGeneratedPage.loadLibrary),
  '/docs/web-hosting': (() => const DocsWebHostingPageGeneratedPage(), DocsWebHostingPageGeneratedPage.loadLibrary),
  '/docs/deploying': (() => const DocsDeployingPageGeneratedPage(), DocsDeployingPageGeneratedPage.loadLibrary),
  '/docs/testing': (() => const DocsTestingPageGeneratedPage(), DocsTestingPageGeneratedPage.loadLibrary),
  '/docs/cli': (() => const DocsCliPageGeneratedPage(), DocsCliPageGeneratedPage.loadLibrary),
};

/// The site's chrome around every docs page, the way the generated router
/// wraps it: the site layout outside, the docs layout inside.
GoRouter docsRouter(String initial) => GoRouter(
      initialLocation: initial,
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('home')),
        ),
        for (final MapEntry<String, (Widget Function(), Future<void> Function())> e
            in docsWidgets.entries)
          GoRoute(
            path: e.key,
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Layout(child: DocsLayout(child: e.value.$1())),
            ),
          ),
      ],
    );

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<GoRouter> pumpDocs(WidgetTester tester, String path, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = docsRouter(path);
  // DVNavLink navigates through DV.Navigation, which drives this router.
  DVNavigation.attach(router);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await settle(tester);
  return router;
}

void main() {
  setUpAll(() async {
    for (final (Widget Function(), Future<void> Function()) page
        in docsWidgets.values) {
      await page.$2();
    }
  });
  setUp(dvResetDeferredPages);
  tearDown(DVNavigation.detach);

  test('every docs route is in the navigation, and every entry is a route', () {
    final Set<String> routed = <String>{
      for (final DVRouteInfo route in dartvelRouteManifest)
        if (route.path == '/docs' || route.path.startsWith('/docs/')) route.path,
    };
    expect(<String>{for (final DocsPageInfo p in kDocsPages) p.path}, routed);
    expect(docsWidgets.keys.toSet(), routed);
  });

  test('each group sits together in the sidebar', () {
    final List<String> order = <String>[
      for (final DocsPageInfo p in kDocsPages) p.group,
    ];
    for (final String group in docsGroups) {
      final int first = order.indexOf(group);
      final int last = order.lastIndexOf(group);
      expect(order.sublist(first, last + 1).every((String g) => g == group),
          isTrue, reason: '$group is split');
    }
  });

  for (final (String name, Size size) in <(String, Size)>[
    ('desktop', const Size(1440, 900)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final String path in docsWidgets.keys) {
      testWidgets('$path renders every section on a $name', (WidgetTester tester) async {
        await pumpDocs(tester, path, size);
        expect(tester.takeException(), isNull);
        final List<DocsSection> sections = tester
            .widgetList<DocsSection>(find.byType(DocsSection, skipOffstage: false))
            .toList();
        expect(sections, isNotEmpty);
        for (final DocsSection section in sections) {
          expect(find.text(section.title, skipOffstage: false), findsWidgets,
              reason: section.id);
        }
        expect(find.byType(DocsOnThisPage, skipOffstage: false), findsOneWidget);
        expect(find.byType(DocsPager, skipOffstage: false), findsOneWidget);
      });
    }
  }

  testWidgets('two live copies of every page both keep their sections',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (Widget Function() build, _) in docsWidgets.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: <Widget>[
            Expanded(child: build()),
            Expanded(child: build()),
          ]),
        ),
      ));
      await settle(tester);
      expect(tester.takeException(), isNull);
      final int sections =
          find.byType(DocsSection, skipOffstage: false).evaluate().length;
      expect(sections, greaterThan(0));
      expect(sections.isEven, isTrue);
      expect(find.byType(DocsOnThisPage, skipOffstage: false), findsNWidgets(2));
    }
  });

  testWidgets('the sidebar reaches every page', (WidgetTester tester) async {
    final GoRouter router = await pumpDocs(tester, '/docs', const Size(1440, 900));
    for (final DocsPageInfo page in kDocsPages.reversed) {
      final Finder link = find.descendant(
        of: find.byType(DocsNav),
        matching: find.text(page.title),
      );
      await tester.ensureVisible(link);
      await tester.tap(link);
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, page.path);
    }
  });

  testWidgets('next and previous walk the pages in order', (WidgetTester tester) async {
    final GoRouter router = await pumpDocs(tester, '/docs', const Size(1440, 900));
    for (int i = 1; i < kDocsPages.length; i++) {
      final Finder next = find.descendant(
        of: find.byType(DocsPager),
        matching: find.text(kDocsPages[i].title),
      );
      await tester.ensureVisible(next);
      await settle(tester);
      await tester.tap(next);
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          kDocsPages[i].path);
    }
    expect(find.descendant(of: find.byType(DocsPager), matching: find.text('NEXT')),
        findsNothing, reason: 'the last page has no next');
  });

  testWidgets('on a phone the menu opens and reaches a page', (WidgetTester tester) async {
    final GoRouter router = await pumpDocs(tester, '/docs', const Size(390, 844));
    expect(find.byType(DocsNav), findsNothing);
    await tester.tap(find.text('Docs menu'));
    await settle(tester);
    expect(find.byType(DocsNav), findsOneWidget);
    final Finder link = find.descendant(
        of: find.byType(DocsNav), matching: find.text('Queues and jobs'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/docs/queues');
    expect(find.byType(DocsNav), findsNothing, reason: 'the menu closes');
  });

  testWidgets('a contents entry scrolls to its section', (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    late BuildContext inner;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocsAnchors(
          ids: const <String>['a', 'b', 'c'],
          builder: (BuildContext context, Map<String, GlobalKey> keys) {
            inner = context;
            return SingleChildScrollView(
              controller: controller,
              child: Column(children: <Widget>[
                for (final String id in <String>['a', 'b', 'c'])
                  SizedBox(key: keys[id], height: 1200, child: Text(id)),
              ]),
            );
          },
        ),
      ),
    ));
    expect(controller.offset, 0);
    dvDocsGoTo(inner, 'c');
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(1200));
    expect(() => dvDocsGoTo(inner, 'missing'), returnsNormally);
  });
}
