// DV.Navigation.to returns a callback rather than navigating.
//
// That is deliberate -- it is built for `onPressed: DV.Navigation.to(target)`
// -- and it is a trap in every other position. Written as
// `onTap: () => DV.Navigation.to(target)` it compiles, runs, discards the
// callback it built, and navigates nowhere. The dartvel.dev header shipped
// exactly that: links that looked right and did nothing.
//
// Dart has an annotation for a return value that must not be dropped, and the
// analyzer enforces it. These assert the two calls behave as their names say,
// so the annotation is documented by behaviour rather than only by a comment.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWithPages() => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('home'),
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('docs'),
        ),
      ],
    );

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('navigate() goes there', (WidgetTester tester) async {
    final router = routerWithPages();
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('home'), findsOneWidget);

    DV.Navigation.navigate(const DVRouteTarget('/docs'));
    await tester.pumpAndSettle();

    expect(find.text('docs'), findsOneWidget);
  });

  testWidgets('to() returns a callback and does not navigate by itself',
      (WidgetTester tester) async {
    // The behaviour that made the header links dead. Calling it is not
    // navigating; the returned callback is.
    final router = routerWithPages();
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final VoidCallback go = DV.Navigation.to(const DVRouteTarget('/docs'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget,
        reason: 'building the callback must not navigate');

    go();
    await tester.pumpAndSettle();

    expect(find.text('docs'), findsOneWidget);
  });

  testWidgets('the callback works as an onTap handler',
      (WidgetTester tester) async {
    // The position it is designed for: passed, not called.
    final router = routerWithPages();
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Inside the routed app, so tapping navigates the router under test
    // rather than a second, unrouted MaterialApp.
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final VoidCallback onTap =
        DV.Navigation.to(const DVRouteTarget('/docs'));
    onTap();
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/docs');
  });
}
