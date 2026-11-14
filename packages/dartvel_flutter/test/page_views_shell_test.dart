// The page shell reports each page it shows to DVPageViews, so a module that
// measures page views hears about the landing page and every route change
// without any page calling anything.
import 'package:dartvel_core/dartvel.dart' show DVPageView, DVPageViews;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter router() => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        for (final (String path, String title) in const <(String, String)>[
          ('/', 'Home'),
          ('/pricing', 'Pricing'),
          ('/contact', 'Contact'),
        ])
          GoRoute(
            path: path,
            builder: (BuildContext context, GoRouterState state) => DVPageShell(
              spec: DVPageScaffoldSpec(title: title),
              child: Text('page $title'),
            ),
          ),
      ],
    );

void main() {
  late List<DVPageView> seen;

  setUp(() {
    DVPageViews.resetForTesting();
    seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
  });

  tearDown(DVPageViews.resetForTesting);

  testWidgets('the first page shown is a view', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    expect(seen.map((DVPageView v) => v.location.path), <String>['/']);
    expect(seen.single.title, 'Home');
  });

  testWidgets('each route change is a view, with its query',
      (WidgetTester tester) async {
    final GoRouter app = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: app));
    await tester.pumpAndSettle();
    app.go('/pricing?plan=pro');
    await tester.pumpAndSettle();
    app.go('/contact');
    await tester.pumpAndSettle();
    expect(
      seen.map((DVPageView v) => '${v.location}'),
      <String>['/', '/pricing?plan=pro', '/contact'],
    );
    expect(seen.last.title, 'Contact');
  });

  testWidgets('rebuilding a page is not another view',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    expect(seen, hasLength(1));
  });

  testWidgets('a page pushed over another is a view, and so is going back',
      (WidgetTester tester) async {
    final GoRouter app = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: app));
    await tester.pumpAndSettle();
    app.push('/pricing');
    await tester.pumpAndSettle();
    app.pop();
    await tester.pumpAndSettle();
    expect(
      seen.map((DVPageView v) => v.location.path),
      <String>['/', '/pricing', '/'],
    );
  });

  testWidgets('a page drawn on Studio\'s canvas is not a view',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPagePreviewScope(
        child: DVPageShell(
          spec: DVPageScaffoldSpec(title: 'Preview'),
          child: Text('preview'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(seen, isEmpty);
  });
}
