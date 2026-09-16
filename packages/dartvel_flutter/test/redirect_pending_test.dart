// An async guard never leaves the screen empty while it decides.
//
// go_router builds `SizedBox.shrink()` while the first location's redirects
// are still resolving (go_router #133746): a deep link or a reload onto a
// guarded route is a black screen for as long as the guard takes -- a session
// check over the network, say. DVRouter paints DVRoutePending there instead.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('a deep link behind an async guard shows the pending view', (
    WidgetTester tester,
  ) async {
    final Completer<String?> decision = Completer<String?>();
    final DVRouter router = DVRouter(
      initialLocation: '/private',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('home'),
        ),
        GoRoute(
          path: '/private',
          redirect: (BuildContext context, GoRouterState state) =>
              decision.future,
          builder: (BuildContext context, GoRouterState state) =>
              const Text('private'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.byType(DVRoutePending), findsOneWidget);
    expect(find.text('private'), findsNothing);

    decision.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('private'), findsOneWidget);
    expect(find.byType(DVRoutePending), findsNothing);
  });

  testWidgets('the pending view is painted, not an empty box', (
    WidgetTester tester,
  ) async {
    final Completer<String?> decision = Completer<String?>();
    final DVRouter router = DVRouter(
      initialLocation: '/private',
      routes: <RouteBase>[
        GoRoute(
          path: '/private',
          redirect: (BuildContext context, GoRouterState state) =>
              decision.future,
          builder: (BuildContext context, GoRouterState state) =>
              const Text('private'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFAFAFA)),
      ),
    );
    await tester.pump();

    final ColoredBox background = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(DVRoutePending),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(background.color, const Color(0xFFFAFAFA));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    decision.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('a redirect decided later still lands where it says', (
    WidgetTester tester,
  ) async {
    final Completer<String?> decision = Completer<String?>();
    final DVRouter router = DVRouter(
      initialLocation: '/private',
      routes: <RouteBase>[
        GoRoute(
          path: '/login',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('login'),
        ),
        GoRoute(
          path: '/private',
          redirect: (BuildContext context, GoRouterState state) =>
              decision.future,
          builder: (BuildContext context, GoRouterState state) =>
              const Text('private'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    decision.complete('/login');
    await tester.pumpAndSettle();

    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('a DVRouter is a GoRouter: go, pop and DV.Navigation work', (
    WidgetTester tester,
  ) async {
    final DVRouter router = DVRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('home'),
        ),
        GoRoute(
          path: '/next',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('next'),
        ),
      ],
    );
    addTearDown(router.dispose);
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    DV.Navigation.navigate(const DVRouteTarget('/next'));
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
    expect(router.state.uri.path, '/next');
  });
}
