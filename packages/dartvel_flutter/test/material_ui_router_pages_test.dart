// The pages go_router builds itself keep their Material page under a
// material_ui app.
//
// go_router 14 decides what page to give a route with a plain `builder` by
// looking for package:flutter/material.dart's MaterialApp above it. Dartvel's
// app is material_ui's MaterialApp now -- a different class, because
// material_ui is a copy of the library rather than a re-export -- so
// go_router stops recognising it and falls back to its WidgetsApp path: a
// NoTransitionPage for every builder route and a bare error screen. Nothing
// fails; shells and error pages just lose the Material page they had. The
// routes Dartvel builds with a `builder` say what page they want instead of
// leaving it to that check.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

List<Page<Object?>> rootPages(WidgetTester tester) =>
    tester.widget<Navigator>(find.byType(Navigator).first).pages;

void main() {
  tearDown(DVNavigation.detach);

  Future<void> pump(WidgetTester tester, GoRouter router) async {
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('a shell route is a Material page', (WidgetTester tester) async {
    await pump(
      tester,
      DVRouter(
        initialLocation: '/admin',
        routes: dvConfigRoutes(<DVRouteNode>[
          DVShellRoute(
            builder: (BuildContext context, DVRouteState state, Widget child) =>
                Column(children: <Widget>[const Text('frame'), Expanded(child: child)]),
            routes: <DVRouteNode>[
              DVRoute(
                path: '/admin',
                builder: (BuildContext context, DVRouteState state) =>
                    const Text('admin'),
              ),
            ],
          ),
        ], transition: PageTransitionSpec.none),
      ),
    );
    expect(find.text('frame'), findsOneWidget);
    expect(rootPages(tester).single, isA<MaterialPage<void>>());
  });

  testWidgets('a tabbed shell route is a Material page', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      DVRouter(
        initialLocation: '/feed',
        routes: dvConfigRoutes(<DVRouteNode>[
          DVStatefulShellRoute(
            builder: (BuildContext context, DVRouteState state,
                    DVShellNavigation shell) =>
                Column(children: <Widget>[const Text('tabs'), Expanded(child: shell)]),
            branches: <DVShellBranch>[
              DVShellBranch(routes: <DVRouteNode>[
                DVRoute(
                  path: '/feed',
                  builder: (BuildContext context, DVRouteState state) =>
                      const Text('feed'),
                ),
              ]),
            ],
          ),
        ], transition: PageTransitionSpec.none),
      ),
    );
    expect(find.text('tabs'), findsOneWidget);
    expect(rootPages(tester).single, isA<MaterialPage<void>>());
  });

  testWidgets('the error builder\'s page is a Material page', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      DVRouter(
        initialLocation: '/nowhere',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                const NoTransitionPage<void>(child: Text('home')),
          ),
        ],
        errorBuilder: (BuildContext context, GoRouterState state) =>
            const Text('not found'),
      ),
    );
    expect(find.text('not found'), findsOneWidget);
    expect(rootPages(tester).single, isA<MaterialPage<void>>());
  });

  testWidgets('an error page asked for by page builder is left as it is', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      DVRouter(
        initialLocation: '/nowhere',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                const NoTransitionPage<void>(child: Text('home')),
          ),
        ],
        errorPageBuilder: (BuildContext context, GoRouterState state) =>
            const NoTransitionPage<void>(child: Text('custom')),
      ),
    );
    expect(find.text('custom'), findsOneWidget);
    expect(rootPages(tester).single, isA<NoTransitionPage<void>>());
  });
}
