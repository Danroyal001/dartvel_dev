// The docs open with the whole platform on one list: every built section,
// how built it is, and a link to where it is written up.
//
// The list is drawn from the same mapping test/spec_coverage_test.dart checks,
// so a section cannot be listed with a status or a page the site does not have.
import 'package:dartvel_site/components/docs.dart';
import 'package:dartvel_site/components/spec_coverage.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<GoRouter> pumpIndex(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = GoRouter(
    initialLocation: '/docs',
    routes: <RouteBase>[
      GoRoute(
        path: '/docs',
        builder: (BuildContext context, GoRouterState state) => const Scaffold(
            body: SingleChildScrollView(child: DocsPlatformIndex())),
      ),
      for (final String path in <String>{
        for (final SpecCoverage c in kSpecCoverage)
          if (c.target.path != '/docs') c.target.path,
      })
        GoRoute(
          path: path,
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: Text('page $path')),
        ),
    ],
  );
  DVNavigation.attach(router);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Finder inIndex(Finder matching) =>
    find.descendant(of: find.byType(DocsPlatformIndex), matching: matching);

Finder rowOf(String section) =>
    inIndex(find.byKey(ValueKey<String>('spec:$section')));

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('every built section is listed once with its status',
      (WidgetTester tester) async {
    await pumpIndex(tester, const Size(1440, 900));
    for (final MapEntry<String, String> e in kDocsSpecStatus.entries) {
      final Finder row = rowOf(e.key);
      expect(row, findsOneWidget, reason: e.key);
      expect(find.descendant(of: row, matching: find.text(e.key)),
          findsOneWidget,
          reason: e.key);
      expect(
        find.descendant(
          of: row,
          matching:
              find.text(e.value == 'Shipped' ? 'Shipped' : 'Partly built'),
        ),
        findsOneWidget,
        reason: e.key,
      );
    }
    expect(
      inIndex(find.byWidgetPredicate((Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('spec:'))),
      findsNWidgets(kDocsSpecStatus.length),
    );
  });

  testWidgets('a covered section links to its page and a gap does not',
      (WidgetTester tester) async {
    await pumpIndex(tester, const Size(1440, 900));
    for (final SpecCoverage c in kSpecCoverage) {
      expect(find.descendant(of: rowOf(c.section), matching: find.byType(DVNavLink)),
          findsOneWidget,
          reason: c.section);
    }
    for (final String gap in kSpecKnownGaps.keys) {
      expect(find.descendant(of: rowOf(gap), matching: find.byType(DVNavLink)),
          findsNothing,
          reason: gap);
    }
  });

  testWidgets('a link lands on the section that covers it',
      (WidgetTester tester) async {
    final GoRouter router = await pumpIndex(tester, const Size(390, 844));
    final SpecCoverage cache =
        kSpecCoverage.firstWhere((SpecCoverage c) => c.section == 'Cache');
    final Finder link = inIndex(find.text('Cache'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    final Uri at = router.routerDelegate.currentConfiguration.uri;
    expect(at.path, cache.target.path);
    expect(at.fragment, cache.anchor);
  });

  testWidgets('the list fits a phone', (WidgetTester tester) async {
    await pumpIndex(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    for (final String section in kDocsSpecStatus.keys) {
      final Rect box = tester.getRect(inIndex(find.text(section)));
      expect(box.right, lessThanOrEqualTo(390), reason: section);
    }
  });

  group('fragments', () {
    setUpAll(DocsModelsPageGeneratedPage.loadLibrary);
    setUp(dvResetDeferredPages);

    Future<double> topOf(
        WidgetTester tester, String location, String heading) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final GoRouter router = GoRouter(
        initialLocation: location,
        routes: <RouteBase>[
          GoRoute(
            path: '/docs/models',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: DocsModelsPageGeneratedPage()),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      // The heading is also an entry in the page's contents box, above the
      // sections, so the section title is the last one.
      return tester.getTopLeft(find.text(heading).last).dy;
    }

    // A link from the index carries the section's anchor, and the docs page
    // opens on that section.
    testWidgets('a docs page opens at the section its link names',
        (WidgetTester tester) async {
      final SpecCoverage sensitive = kSpecCoverage.firstWhere(
          (SpecCoverage c) => c.section == 'Sensitive Model Fields');
      expect(await topOf(tester, '/docs/models', sensitive.heading),
          greaterThan(900));
      expect(await topOf(tester, sensitive.href, sensitive.heading),
          inInclusiveRange(0, 900));
    });
  });
}
