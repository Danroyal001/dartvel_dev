// The header links and hero buttons, tapped.
//
// They shipped dead. `onTap: () => DV.Navigation.to(target)` builds the
// callback that would navigate, discards it, and returns it from the lambda —
// which satisfies VoidCallback, because Dart lets any return type stand where
// void is expected. It compiles, it runs, the cursor changes, nothing happens.
//
// Screenshotting each route by URL did not catch this: the routes were fine,
// the links were not. Only tapping does.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_site/components/site.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A router with the site's real routes, where "/" renders the widget under
/// test and everything else renders a marker. The widget has to be inside the
/// routed app, or the router drives nothing and reports no current path.
GoRouter siteRouter(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          // Wrapped exactly as a real page is: DVPageShell puts every page
          // inside a SelectionArea. Testing the header bare is what let dead
          // links pass a suite that taps them.
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: SelectionArea(child: subject)),
        ),
        for (final String path in const <String>['/docs', '/features', '/cloud'])
          GoRoute(
            path: path,
            builder: (BuildContext context, GoRouterState state) =>
                Scaffold(body: Text('at $path')),
          ),
      ],
    );

void main() {
  tearDown(DVNavigation.detach);

  Future<void> pumpWith(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = siteRouter(child);
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  // One link per test, rather than a loop. Tapping navigates away from the
  // page that holds the header, and returning to it mid-loop was its own
  // source of failure rather than a test of anything.
  for (final (String label, String path) in const <(String, String)>[
    ('Docs', '/docs'),
    ('Features', '/features'),
    ('Cloud', '/cloud'),
  ]) {
    testWidgets('the $label link navigates when tapped',
        (WidgetTester tester) async {
      await pumpWith(tester, const SiteHeader());

      expect(find.text(label), findsOneWidget, reason: '$label is missing');

      await tester.tap(find.text(label));
      await tester.pump();

      expect(DV.Navigation.currentPath, path,
          reason: 'tapping $label did not navigate');
    });
  }

  testWidgets('a filled button navigates', (WidgetTester tester) async {
    await pumpWith(tester, const PrimaryLink('Get started', '/docs'));

    await tester.tap(find.text('Get started'));
    await tester.pump();

    expect(DV.Navigation.currentPath, '/docs');
  });

  testWidgets('an outlined button navigates', (WidgetTester tester) async {
    await pumpWith(tester, const GhostLink('Cloud', '/cloud'));

    await tester.tap(find.text('Cloud'));
    await tester.pump();

    expect(DV.Navigation.currentPath, '/cloud');
  });

  testWidgets('the padding around a link is clickable, not just the glyphs',
      (WidgetTester tester) async {
    // The header links were bare text: the gaps between letters and the space
    // around them did nothing, so a click that looked on-target missed.
    await pumpWith(tester, const SiteHeader());

    final rect = tester.getRect(find.text('Docs'));
    // Two pixels outside the text box, still inside the link's padding.
    await tester.tapAt(Offset(rect.left - 2, rect.center.dy));
    await tester.pump();

    expect(DV.Navigation.currentPath, '/docs');
  });
}
