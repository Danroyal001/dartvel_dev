// The docs sidebar is grouped, and on a phone the groups fold.
//
// The docs grow from two dozen pages toward one per built spec section. A
// flat list of a hundred links is a wall on a 390px screen, so the menu shows
// the groups, opens the one the reader is in, and opens another on a tap.
import 'package:dartvel_site/components/docs.dart';
import 'package:dartvel_site/components/docs_page_info.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:dartvel_site/pages/docs/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<GoRouter> pumpDocs(WidgetTester tester, String path, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = GoRouter(
    initialLocation: path,
    routes: <RouteBase>[
      for (final DocsPageInfo page in kDocsPages)
        GoRoute(
          path: page.path,
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Layout(
              child: DocsLayout(child: Text('page ${state.uri.path}')),
            ),
          ),
        ),
    ],
  );
  DVNavigation.attach(router);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return router;
}

Finder navText(String text) =>
    find.descendant(of: find.byType(DocsNav), matching: find.text(text));

void main() {
  tearDown(DVNavigation.detach);

  test('every page is in a named group, and groups keep that order', () {
    for (final DocsPageInfo page in kDocsPages) {
      expect(kDocsGroupOrder, contains(page.group), reason: page.title);
    }
    final List<String> order = <String>[
      for (final String g in kDocsGroupOrder)
        if (docsGroups.contains(g)) g,
    ];
    expect(docsGroups, order);
  });

  testWidgets('on a wide screen every group is open', (WidgetTester tester) async {
    await pumpDocs(tester, '/docs', const Size(1440, 900));
    for (final DocsPageInfo page in kDocsPages) {
      expect(navText(page.title), findsOneWidget, reason: page.title);
    }
  });

  testWidgets('on a phone the menu opens the group the reader is in',
      (WidgetTester tester) async {
    await pumpDocs(tester, '/docs/cache', const Size(390, 844));
    await tester.tap(find.text('Docs menu'));
    await tester.pumpAndSettle();

    for (final String group in docsGroups) {
      expect(navText(group.toUpperCase()), findsOneWidget, reason: group);
    }
    final String here = docsPageAt('/docs/cache')!.group;
    for (final DocsPageInfo page in kDocsPages) {
      expect(navText(page.title),
          page.group == here ? findsOneWidget : findsNothing,
          reason: page.title);
    }
  });

  testWidgets('on a phone a group heading opens that group and its link works',
      (WidgetTester tester) async {
    final GoRouter router =
        await pumpDocs(tester, '/docs', const Size(390, 844));
    await tester.tap(find.text('Docs menu'));
    await tester.pumpAndSettle();

    final DocsPageInfo target =
        kDocsPages.lastWhere((DocsPageInfo p) => p.group != kDocsPages.first.group);
    expect(navText(target.title), findsNothing);
    await tester.ensureVisible(navText(target.group.toUpperCase()));
    await tester.tap(navText(target.group.toUpperCase()));
    await tester.pumpAndSettle();
    expect(navText(target.title), findsOneWidget);

    await tester.ensureVisible(navText(target.title));
    await tester.tap(navText(target.title));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, target.path);
  });

  testWidgets('a group heading says whether it is open', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpDocs(tester, '/docs', const Size(390, 844));
    await tester.tap(find.text('Docs menu'));
    await tester.pumpAndSettle();

    final String open = kDocsPages.first.group.toUpperCase();
    final String closed = docsGroups[1].toUpperCase();
    expect(
      tester.getSemantics(navText(open)),
      matchesSemantics(
        label: open,
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(navText(closed)),
      matchesSemantics(
        label: closed,
        isButton: true,
        hasExpandedState: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('nothing in the phone menu is wider than the phone',
      (WidgetTester tester) async {
    await pumpDocs(tester, '/docs', const Size(390, 844));
    await tester.tap(find.text('Docs menu'));
    await tester.pumpAndSettle();
    for (final String group in docsGroups) {
      final Finder heading = navText(group.toUpperCase());
      final DocsPageInfo first =
          kDocsPages.firstWhere((DocsPageInfo p) => p.group == group);
      if (navText(first.title).evaluate().isEmpty) {
        await tester.ensureVisible(heading);
        await tester.tap(heading);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: group);
      for (final DocsPageInfo page in kDocsPages) {
        if (page.group != group) continue;
        final Rect box = tester.getRect(navText(page.title));
        expect(box.left, greaterThanOrEqualTo(0), reason: page.title);
        expect(box.right, lessThanOrEqualTo(390), reason: page.title);
      }
    }
  });
}
