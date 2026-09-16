// Config routes: routes declared in code, mounted beside the generated ones.
//
// Driven through a real GoRouter and DV.Navigation, the way the generated
// createDartvelRouter() assembles them: the generated routes first, the
// config routes after, and dvOrderGoRoutes over the lot. A file route is
// stood in for by a plain GoRoute, which is what the generator emits.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool signedIn = false;

GoRoute fileRoute(String path, String text) => GoRoute(
  path: path,
  builder: (BuildContext context, GoRouterState state) =>
      Text('$text ${state.pathParameters.values.join()}'.trim()),
);

List<DVRouteNode> configRoutes() => <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (BuildContext context, DVRouteState state) =>
        Text('settings ${context.dvQuery['tab'] ?? ''}'.trim()),
  ),
  DVRoute(
    path: '/orders',
    builder: (BuildContext context, DVRouteState state) => const Text('orders'),
    routes: <DVRouteNode>[
      DVRoute(
        path: ':id',
        builder: (BuildContext context, DVRouteState state) =>
            Text('order ${state.params['id']} ${state.pattern}'),
      ),
    ],
  ),
  DVRoute(
    path: '/users/new',
    builder: (BuildContext context, DVRouteState state) =>
        const Text('new user'),
  ),
  DVShellRoute(
    redirect: (BuildContext context, DVRouteState state) =>
        signedIn ? null : const DVRouteTarget('/'),
    builder: (BuildContext context, DVRouteState state, Widget child) => Column(
      children: <Widget>[
        const Text('admin frame'),
        Expanded(child: child),
      ],
    ),
    routes: <DVRouteNode>[
      DVRoute(
        path: '/admin/reports',
        builder: (BuildContext context, DVRouteState state) =>
            const Text('reports'),
      ),
    ],
  ),
  DVStatefulShellRoute(
    builder:
        (BuildContext context, DVRouteState state, DVShellNavigation shell) =>
            Column(
              children: <Widget>[
                Text('tab ${shell.currentIndex}'),
                Expanded(child: shell),
              ],
            ),
    branches: <DVShellBranch>[
      DVShellBranch(
        routes: <DVRouteNode>[
          DVRoute(
            path: '/feed',
            builder: (BuildContext context, DVRouteState state) =>
                const Text('feed'),
          ),
        ],
      ),
      DVShellBranch(
        routes: <DVRouteNode>[
          DVRoute(
            path: '/inbox',
            builder: (BuildContext context, DVRouteState state) =>
                const Text('inbox'),
          ),
        ],
      ),
    ],
  ),
  DVGoRoutes(<RouteBase>[
    GoRoute(
      path: '/legacy',
      builder: (BuildContext context, GoRouterState state) =>
          const Text('legacy'),
    ),
  ]),
];

GoRouter buildRouter({String initial = '/'}) {
  final GoRouter router = GoRouter(
    initialLocation: initial,
    routes: dvOrderGoRoutes(<RouteBase>[
      fileRoute('/', 'home'),
      // Listed before the config route it would hide, as file-name order
      // lists `[id].dart` before `new.dart`.
      fileRoute('/users/:id', 'user'),
      ...dvConfigRoutes(configRoutes(), transition: PageTransitionSpec.none),
    ]),
  );
  DVNavigation.attach(router);
  return router;
}

Future<GoRouter> pumpRouter(WidgetTester tester, {String initial = '/'}) async {
  final GoRouter router = buildRouter(initial: initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<void> go(WidgetTester tester, String path) async {
  DV.Navigation.navigate(DVRouteTarget(path));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    signedIn = false;
    DVRoutePreviews.clear();
  });
  tearDown(DVNavigation.detach);

  testWidgets('a config route and a file route share one router', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    expect(find.text('home'), findsOneWidget);

    await go(tester, '/settings?tab=billing');
    expect(find.text('settings billing'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/settings?tab=billing');

    await go(tester, '/users/7');
    expect(find.text('user 7'), findsOneWidget);
  });

  testWidgets('a static config route is not hidden by a file parameter route', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    await go(tester, '/users/new');
    expect(find.text('new user'), findsOneWidget);
  });

  testWidgets('a nested route is pushed over its parent, and back returns', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    await go(tester, '/orders/42');
    expect(find.text('order 42 /orders/:id'), findsOneWidget);
    expect(DV.Navigation.canGoBack, isTrue);

    DV.Navigation.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('orders'), findsOneWidget);
  });

  testWidgets('a guarded shell redirects, then lets a signed-in visitor in', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    await go(tester, '/admin/reports');
    expect(find.text('reports'), findsNothing);
    expect(find.text('home'), findsOneWidget);

    signedIn = true;
    await go(tester, '/admin/reports');
    expect(find.text('admin frame'), findsOneWidget);
    expect(find.text('reports'), findsOneWidget);
  });

  testWidgets('an inherited guard runs before the route\'s own redirect', (
    WidgetTester tester,
  ) async {
    final List<String> ran = <String>[];
    final GoRouter router = GoRouter(
      routes: dvOrderGoRoutes(<RouteBase>[
        fileRoute('/', 'home'),
        fileRoute('/login', 'login'),
        ...dvConfigRoutes(
          <DVRouteNode>[
            DVRoute(
              path: '/private',
              redirect: (BuildContext context, DVRouteState state) {
                ran.add('own');
                return null;
              },
              builder: (BuildContext context, DVRouteState state) =>
                  const Text('private'),
            ),
          ],
          inheritedRedirect: (BuildContext context, GoRouterState state) {
            ran.add('inherited');
            return signedIn ? null : '/login';
          },
        ),
      ]),
    );
    addTearDown(router.dispose);
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await go(tester, '/private');
    expect(find.text('login'), findsOneWidget);
    expect(ran, <String>['inherited']);

    signedIn = true;
    ran.clear();
    await go(tester, '/private');
    expect(find.text('private'), findsOneWidget);
    expect(ran, <String>['inherited', 'own']);
  });

  testWidgets('a deep link straight to a nested config route', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester, initial: '/orders/9');
    expect(find.text('order 9 /orders/:id'), findsOneWidget);
  });

  testWidgets('tabs keep their own branch and switch with goBranch', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    await go(tester, '/inbox');
    expect(find.text('tab 1'), findsOneWidget);
    expect(find.text('inbox'), findsOneWidget);

    await go(tester, '/feed');
    expect(find.text('tab 0'), findsOneWidget);
    expect(find.text('feed'), findsOneWidget);
  });

  testWidgets('an existing go_router route list is mounted as it is', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRouter(tester);
    router.go('/legacy');
    await tester.pumpAndSettle();
    expect(find.text('legacy'), findsOneWidget);
  });

  test('a preview is registered for an open route and not a guarded one', () {
    dvConfigRoutes(configRoutes());
    expect(DVRoutePreviews.forPath('/settings'), isNotNull);
    expect(DVRoutePreviews.forPath('/orders'), isNotNull);
    // Parameterised: a link names a concrete path, never the pattern.
    expect(DVRoutePreviews.forPath('/orders/:id'), isNull);
    // Behind the shell's redirect. A preview is the page built live, and
    // building it for somebody the guard would refuse shows them the page.
    expect(DVRoutePreviews.forPath('/admin/reports'), isNull);
  });

  test('preview: false keeps a route out of the preview registry', () {
    dvConfigRoutes(<DVRouteNode>[
      DVRoute(
        path: '/live',
        preview: false,
        builder: (BuildContext context, DVRouteState state) => const SizedBox(),
      ),
    ]);
    expect(DVRoutePreviews.forPath('/live'), isNull);
  });

  test('routes that cannot be ordered fail with DV-ROUTE-004', () {
    expect(
      () => dvOrderGoRoutes(<RouteBase>[
        ...dvConfigRoutes(<DVRouteNode>[
          DVShellRoute(
            builder: (BuildContext c, DVRouteState s, Widget child) => child,
            routes: <DVRouteNode>[
              DVRoute(path: '/a/:x', builder: (c, s) => const SizedBox()),
              DVRoute(path: '/b/new', builder: (c, s) => const SizedBox()),
            ],
          ),
          DVShellRoute(
            builder: (BuildContext c, DVRouteState s, Widget child) => child,
            routes: <DVRouteNode>[
              DVRoute(path: '/a/new', builder: (c, s) => const SizedBox()),
              DVRoute(path: '/b/:x', builder: (c, s) => const SizedBox()),
            ],
          ),
        ]),
      ]),
      throwsA(isA<DVRouteOrderException>()),
    );
  });
}
