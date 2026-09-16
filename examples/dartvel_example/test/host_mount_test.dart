// The example's generated routes inside a host application's own GoRouter.
//
// dartvelRoutes(at: '/app') is what an application that already has a
// router mounts: pages, config routes and tabs, under a prefix. The host
// keeps its routes, and DV.Navigation lands Dartvel's targets under /app.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() {
    DVNavigation.detach();
    dvResetMount();
  });

  testWidgets('mounted at /app beside the host\'s own routes', (
    WidgetTester tester,
  ) async {
    final GoRouter host = GoRouter(
      initialLocation: '/profile',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('host profile')),
        ),
        ...dartvelRoutes(at: '/app'),
      ],
    );
    addTearDown(host.dispose);
    DVNavigation.attach(host);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: host)),
    );
    await settle(tester);
    expect(find.text('host profile'), findsOneWidget);

    // A config route, by its typed target, under the prefix.
    DV.Navigation.navigate(DVRoutes.settings);
    await settle(tester);
    expect(find.text('A config route. Tab: general'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/settings');

    // A nested config route.
    DV.Navigation.navigate(DVRoutes.teamMember(member: 'linus'));
    await settle(tester);
    expect(find.text('Profile of linus'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/team/linus');

    // A file route inside the tabs.
    DV.Navigation.navigate(DVRoutes.libraryBook(book: 'dune'));
    await settle(tester);
    expect(find.text('Reading dune'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/library/dune');

    // The host's route, through the same DV.Navigation.
    DV.Navigation.navigate(const DVRouteTarget('/profile'));
    await settle(tester);
    expect(find.text('host profile'), findsOneWidget);
  });
}
