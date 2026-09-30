// A page made in Studio is a page of the site.
//
// A page Studio serves at an address no compiled page claims was built by
// go_router's error builder. There it had no Material above it, so on
// dartvel.dev it came out in Flutter's debug text style -- red, underlined
// in yellow, in Roboto -- with no header; and no router state, so the site's
// layouts, whose header reads GoRouterState to light the current link,
// could not be put around it without throwing. It is now served by a route
// of its own, last, so it has both: the site's layouts and shell, and the
// state they read. An address with nothing at it is still not found, and
// dartvel.notFoundRedirect still sends it away.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A site layout that lights its links from the router, as dartvel.dev's
/// header does.
class _Layout extends StatelessWidget {
  const _Layout({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text('header at ${GoRouterState.of(context).uri.path}'),
          Expanded(child: child),
        ],
      );
}

Widget _frame(Widget document) => DVPageShell(
      spec: const DVPageScaffoldSpec(),
      child: _Layout(child: document),
    );

GoRouter _router(String location, {String notFoundRedirect = ''}) => GoRouter(
      initialLocation: location,
      redirect: (BuildContext context, GoRouterState state) =>
          dvNotFoundRedirect(state, notFoundRedirect),
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/menu', builder: (_, _) => const Text('the menu')),
        GoRoute(path: '/gone', builder: (_, _) => const Text('went away')),
        dvStudioPagesRoute(frame: _frame),
      ],
    );

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    await const DVPageStore().save(DVPageDocument(
      route: '/pricing/plans',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        DVPageNode(type: 'text', properties: <String, Object?>{'text': 'Plans'}),
      ]),
    ));
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  testWidgets('is drawn in the site\'s layouts, which read the router',
      (WidgetTester tester) async {
    final GoRouter router = _router('/pricing/plans');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Plans'), findsOneWidget);
    expect(find.text('header at /pricing/plans'), findsOneWidget);
    // Under the application's theme, not the debug text style.
    final TextStyle style = DefaultTextStyle.of(tester.element(find.text('Plans'))).style;
    expect(style.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('compiled pages still win, wherever they are listed',
      (WidgetTester tester) async {
    final GoRouter router = _router('/menu');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('the menu'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('an address with nothing at it is not found, unframed',
      (WidgetTester tester) async {
    final GoRouter router = _router('/nothing/here');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(DVNotFoundPage), findsOneWidget);
    expect(find.textContaining('header at'), findsNothing);
  });

  testWidgets('dartvel.notFoundRedirect sends away an address with nothing at '
      'it, and leaves a Studio page alone', (WidgetTester tester) async {
    final GoRouter router = _router('/nothing/here', notFoundRedirect: '/gone');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('went away'), findsOneWidget);

    router.go('/pricing/plans');
    await tester.pumpAndSettle();
    expect(find.text('Plans'), findsOneWidget);
  });
}
