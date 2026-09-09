// routes.allow as the router actually sees it.
//
// The unit test in dartvel_core holds the decision: which paths are refused
// and where they go. What a real router adds is that the decision is being
// asked in the shape a redirect is asked in, and that the page the reader
// ends up on is the one the policy named -- a redirect can return a correct
// location and still leave the wrong widget on screen.
//
// The refusal for the home route is checked here as well. go_router happens
// to tolerate a redirect that points at the location it was given, so this
// does not catch the loop by itself; the core test does. What it does hold to
// is that the attract route renders, which is the one screen a kiosk always
// has to be able to show.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy _policy({
  List<String> allow = const <String>['/welcome', '/order/**'],
  String home = '/welcome',
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'home': home,
        'routes': <String, Object?>{'allow': allow},
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

Widget _page(String label) => Scaffold(body: Center(child: Text(label)));

GoRouter _router() => GoRouter(
      initialLocation: '/welcome',
      // What the generated router emits: the kiosk answers before anything
      // else routes, and returns null when no kiosk is holding.
      redirect: (BuildContext _, GoRouterState state) =>
          dvKioskRouteRedirect(state.uri.path),
      routes: <RouteBase>[
        GoRoute(
            path: '/welcome',
            builder: (_, __) => _page('Welcome')),
        GoRoute(
            path: '/order/:id',
            builder: (_, __) => _page('Order')),
        GoRoute(path: '/admin', builder: (_, __) => _page('Admin')),
      ],
    );

void main() {
  tearDown(dvResetKioskContainment);

  testWidgets('a route outside the list never renders', (tester) async {
    dvApplyKioskContainment(_policy());
    final GoRouter router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/admin');
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('an allowed route renders as it always did', (tester) async {
    dvApplyKioskContainment(_policy());
    final GoRouter router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/order/12');
    await tester.pumpAndSettle();

    expect(find.text('Order'), findsOneWidget);
  });

  testWidgets('a home route left off the list still shows', (tester) async {
    dvApplyKioskContainment(_policy(allow: const <String>['/order/**']));
    final GoRouter router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no kiosk running the router is untouched', (tester) async {
    final GoRouter router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/admin');
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
  });
}
