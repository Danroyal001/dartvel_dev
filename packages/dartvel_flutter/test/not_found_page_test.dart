// What a path no route serves renders, with nothing configured.
//
// dartvel.notFoundRedirect is an override, not the way to handle an unknown
// URL: a project that sets nothing still gets a page in its own theme, and a
// visitor who lands on one gets a way back rather than a dead end.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, String path) async {
  final GoRouter router = GoRouter(
    initialLocation: path,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext c, GoRouterState s) =>
            const Scaffold(body: Text('home page')),
      ),
    ],
    errorBuilder: (BuildContext c, GoRouterState s) =>
        DVStudioPageRoute(s.uri.path),
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4BF4)),
    ),
    routerConfig: router,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(DVPageStore.resetCache);
  tearDown(DVPageStore.resetCache);

  testWidgets('an unknown path renders a 404 page that names it',
      (WidgetTester tester) async {
    await pumpAt(tester, '/nope');

    expect(find.text('404'), findsOneWidget);
    expect(find.textContaining('/nope'), findsOneWidget);
  });

  testWidgets('it offers the way home, and going there works',
      (WidgetTester tester) async {
    await pumpAt(tester, '/nope');

    expect(find.text('Go to the home page'), findsOneWidget);
    await tester.tap(find.text('Go to the home page'));
    await tester.pumpAndSettle();

    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('it is drawn in the application\'s theme',
      (WidgetTester tester) async {
    await pumpAt(tester, '/nope');

    // A router's error page has no Scaffold above it, so bare text there
    // takes Flutter's red-on-yellow fallback style.
    expect(
        find.ancestor(
            of: find.text('404'), matching: find.byType(Material)),
        findsWidgets);
    final TextStyle style = tester.widget<Text>(find.text('404')).style!;
    expect(style.color, isNot(const Color(0xFFFF0000)));
  });
}
