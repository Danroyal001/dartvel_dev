// Dartvel's routes inside an application that already has a GoRouter.
//
// The adoption path with no lock-in: the host keeps its router, its routes
// and its navigation, and mounts Dartvel's as a sub-tree -- at its own root
// or under a prefix. DV.Navigation then goes through the host's router,
// placing Dartvel's targets under the prefix and leaving the host's alone.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool signedIn = false;

GoRoute page(String path, String text) => GoRoute(
  path: path,
  builder: (BuildContext context, GoRouterState state) =>
      Text('$text ${state.pathParameters.values.join()}'.trim()),
);

/// What the generated router would hand over: pages, a page behind a guard
/// that returns a Dartvel path, and config routes with nesting and tabs.
List<RouteBase> dartvelRoutes() => dvOrderGoRoutes(<RouteBase>[
  page('/', 'dartvel home'),
  page('/about', 'about'),
  page('/users/:id', 'user'),
  GoRoute(
    path: '/account',
    redirect: (BuildContext context, GoRouterState state) =>
        signedIn ? null : '/about',
    builder: (BuildContext context, GoRouterState state) =>
        const Text('account'),
  ),
  ...dvConfigRoutes(<DVRouteNode>[
    DVRoute(
      path: '/settings',
      redirect: (BuildContext context, DVRouteState state) =>
          signedIn ? null : const DVRouteTarget('/about'),
      builder: (BuildContext context, DVRouteState state) =>
          Text('settings ${state.pattern}'),
      routes: <DVRouteNode>[
        DVRoute(
          path: ':tab',
          builder: (BuildContext context, DVRouteState state) =>
              Text('settings tab ${state.params['tab']}'),
        ),
      ],
    ),
    DVStatefulShellRoute(
      builder:
          (BuildContext context, DVRouteState state, DVShellNavigation shell) =>
              shell,
      branches: <DVShellBranch>[
        DVShellBranch(
          initialLocation: const DVRouteTarget('/feed'),
          routes: <DVRouteNode>[
            DVRoute(
              path: '/feed',
              builder: (BuildContext context, DVRouteState state) =>
                  const Text('feed'),
            ),
          ],
        ),
      ],
    ),
  ], transition: PageTransitionSpec.none),
]);

Future<GoRouter> pumpHost(WidgetTester tester, {required String at}) async {
  final GoRouter host = GoRouter(
    routes: <RouteBase>[
      if (at != '/') page('/', 'host home'),
      page('/profile', 'host profile'),
      ...dvMountRoutes(dartvelRoutes(), at: at),
    ],
  );
  addTearDown(host.dispose);
  DVNavigation.attach(host);
  await tester.pumpWidget(MaterialApp.router(routerConfig: host));
  await tester.pumpAndSettle();
  return host;
}

Future<void> go(WidgetTester tester, String path) async {
  DV.Navigation.navigate(DVRouteTarget(path));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => signedIn = false);
  tearDown(() {
    DVNavigation.detach();
    dvResetMount();
  });

  testWidgets('mounted under a prefix, DV.Navigation lands under it', (
    WidgetTester tester,
  ) async {
    final GoRouter host = await pumpHost(tester, at: '/app');
    expect(find.text('host home'), findsOneWidget);

    await go(tester, '/about');
    expect(find.text('about'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/about');

    await go(tester, '/');
    expect(find.text('dartvel home'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app');

    await go(tester, '/users/5');
    expect(find.text('user 5'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/users/5');

    // The host's own route is the host's: not prefixed.
    await go(tester, '/profile');
    expect(find.text('host profile'), findsOneWidget);

    // And the host's router still navigates the way it always did.
    host.go('/app/about');
    await tester.pumpAndSettle();
    expect(find.text('about'), findsOneWidget);
  });

  testWidgets('a Dartvel redirect stays inside the mount', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester, at: '/app');

    await go(tester, '/account');
    expect(DV.Navigation.currentPath, '/app/about');

    await go(tester, '/settings/billing');
    expect(DV.Navigation.currentPath, '/app/about');

    signedIn = true;
    await go(tester, '/settings/billing');
    expect(find.text('settings tab billing'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/settings/billing');
  });

  testWidgets('tabs and their initial location move under the prefix', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester, at: '/app');
    await go(tester, '/feed');
    expect(find.text('feed'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/feed');
  });

  testWidgets('mounted at the root, both route sets sit side by side', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester, at: '/');
    expect(find.text('dartvel home'), findsOneWidget);

    await go(tester, '/profile');
    expect(find.text('host profile'), findsOneWidget);
    await go(tester, '/about');
    expect(DV.Navigation.currentPath, '/about');
  });

  test('locationOf prefixes only what Dartvel serves', () {
    dvMountRoutes(dartvelRoutes(), at: '/app');
    expect(
      DVNavigation.locationOf(const DVRouteTarget('/about?x=1')),
      '/app/about?x=1',
    );
    expect(DVNavigation.locationOf(const DVRouteTarget('/')), '/app');
    expect(
      DVNavigation.locationOf(const DVRouteTarget('/profile')),
      '/profile',
    );
  });

  test('a prefix that is not a path is refused', () {
    expect(
      () => dvMountRoutes(dartvelRoutes(), at: 'app'),
      throwsArgumentError,
    );
    expect(
      () => dvMountRoutes(dartvelRoutes(), at: '/app/'),
      throwsArgumentError,
    );
  });
}
