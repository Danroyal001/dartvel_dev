// The example's generated routes inside a host application's own GoRouter.
//
// dartvelRoutes(at: '/app') is what an application that already has a
// router mounts: pages, config routes and tabs, under a prefix. The host
// keeps its routes, and DV.Navigation lands Dartvel's targets under /app.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
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
    configureDartvelExample();
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
    expect(find.text('Showing general settings'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/settings');

    // A nested config route.
    DV.Navigation.navigate(DVRoutes.teamMember(member: 'lucia'));
    await settle(tester);
    expect(find.text('Packing and customer care'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/team/lucia');

    // A file route inside the tabs.
    DV.Navigation.navigate(DVRoutes.coffee(slug: 'nyeri'));
    await settle(tester);
    expect(find.byKey(const Key('add-to-bag')), findsOneWidget);
    expect(DV.Navigation.currentPath, '/app/coffee/nyeri');

    // The host's route, through the same DV.Navigation.
    DV.Navigation.navigate(const DVRouteTarget('/profile'));
    await settle(tester);
    expect(find.text('host profile'), findsOneWidget);
  });
}
