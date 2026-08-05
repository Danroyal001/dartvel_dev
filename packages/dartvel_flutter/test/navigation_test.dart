// DV.Navigation is what NEW_SPEC.md tells application code to use, including
// from callbacks such as `onPressed` where no BuildContext is in scope. These
// tests drive a real GoRouter so the surface is exercised the way an
// application reaches it, not through a stand-in.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVRouteTarget _home = DVRouteTarget('/');
const DVRouteTarget _users = DVRouteTarget('/users');

GoRouter _buildRouter() {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const Text('home'),
      ),
      GoRoute(
        path: '/users',
        builder: (BuildContext context, GoRouterState state) =>
            const Text('users'),
      ),
    ],
  );
  DVNavigation.attach(router);
  return router;
}

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('to() returns a callback that navigates', (WidgetTester tester) async {
    final router = _buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('home'), findsOneWidget);

    // Exactly the spec's usage: a VoidCallback handed to a handler.
    final VoidCallback navigate = DV.Navigation.to(_users);
    navigate();
    await tester.pumpAndSettle();

    expect(find.text('users'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/users');
  });

  testWidgets('push and back move along the stack', (WidgetTester tester) async {
    final router = _buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(DV.Navigation.canGoBack, isFalse);

    // `push` completes with the popped result, which this test does not need.
    unawaited(DV.Navigation.push<void>(_users));
    await tester.pumpAndSettle();
    expect(find.text('users'), findsOneWidget);
    expect(DV.Navigation.canGoBack, isTrue);

    DV.Navigation.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('back on the first page is a no-op rather than an error',
      (WidgetTester tester) async {
    final router = _buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    DV.Navigation.navigate(_home);
    await tester.pumpAndSettle();
    DV.Navigation.back<void>();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  test('navigating with no router attached names the fix', () {
    expect(DV.Navigation.isAttached, isFalse);
    expect(
      () => DV.Navigation.navigate(_users),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('createDartvelRouter'),
        ),
      ),
    );
  });
}
