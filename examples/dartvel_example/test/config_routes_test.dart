// Config routes and file routes through the example's real generated router.
//
// lib/routes.dart declares /settings, /team with a nested /team/:member, and
// a guarded shell over /admin/reports; lib/pages has /about and the rest.
// One router for all of it, reached through DV.Navigation and DVRoutes, the
// way the application reaches it.
//
// One test, one router: instantiating this generated router repeatedly in
// one isolate is unreliable (see studio_publish_test.dart).
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed frames: the example's home page animates continuously, so
/// pumpAndSettle would never return, and a page transition has to finish
/// before the page it left is gone.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('config routes, file routes, nesting and a guard in one router',
      (WidgetTester tester) async {
    DV.Auth.configure(DVLocalAuthProvider());
    final GoRouter router = createDartvelRouter();
    addTearDown(router.dispose);
    // Started on a config route, as a deep link or a reload would.
    router.go('/settings?tab=billing');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    // A config route, with the query its builder reads.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('A config route. Tab: billing'), findsOneWidget);

    // A file route, by its typed target.
    DV.Navigation.navigate(DVRoutes.about);
    await settle(tester);
    expect(DV.Navigation.currentPath, '/about');
    expect(find.text('Settings'), findsNothing);

    // A nested config route: pushed over its parent, so back returns to it.
    DV.Navigation.navigate(DVRoutes.teamMember(member: 'ada'));
    await settle(tester);
    expect(find.text('Profile of ada'), findsOneWidget);
    expect(DV.Navigation.canGoBack, isTrue);
    DV.Navigation.back<void>();
    await settle(tester);
    expect(DV.Navigation.currentPath, '/team');
    expect(find.text('Member grace'), findsOneWidget);

    // A guarded config route: nobody is signed in, so the shell's redirect
    // sends the visitor to the About page instead.
    DV.Navigation.navigate(DVRoutes.adminReports);
    // The guard is async and takes a moment, as a session check would.
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
    expect(find.text('Reports'), findsNothing);
    expect(DV.Navigation.currentPath, '/about');
  });

  test('config routes are in the route manifest the web build reads', () {
    final Set<String> paths =
        dartvelRouteManifest.map((DVRouteInfo r) => r.path).toSet();
    expect(paths, containsAll(<String>['/settings', '/team', '/team/:member']));
    expect(paths, contains('/about'));
    expect(dartvelGuardedRoutes, contains('/admin/reports'));
    expect(dartvelGuardedRoutes, isNot(contains('/settings')));
  });
}
