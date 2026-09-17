// dartvel.notFoundRedirect sends a path no route serves to a page of the
// application's choosing.
//
// The generated router used to test `state.error != null` inside the
// top-level redirect. go_router never sets `error` on the state it hands that
// redirect (buildTopLevelGoRouterState leaves it out), so the setting was
// read, generated, and never once applied: an unknown path rendered the 404
// fallback whatever the pubspec said.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerTo(String location, {String to = '/'}) => DVRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, __) => const Text('home')),
        GoRoute(path: '/about', builder: (_, __) => const Text('about')),
      ],
      redirect: (BuildContext context, GoRouterState state) =>
          dvNotFoundRedirect(state, to),
      errorBuilder: (BuildContext context, GoRouterState state) =>
          DVStudioPageRoute(state.uri.path),
    );

void main() {
  setUp(DVPageStore.resetCache);
  tearDown(DVPageStore.resetCache);

  testWidgets('a path no route serves goes to the configured page',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: routerTo('/__studio')));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('404'), findsNothing);
  });

  testWidgets('a declared route is left where it is',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: routerTo('/about')));
    await tester.pumpAndSettle();

    expect(find.text('about'), findsOneWidget);
  });

  testWidgets('a target that is itself unserved renders 404 instead of looping',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: routerTo('/missing', to: '/also-missing'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('404'), findsOneWidget);
  });

  testWidgets('a Studio page stored for the path is not redirected away',
      (WidgetTester tester) async {
    final database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    addTearDown(database.close);
    final document = DVPageDocument(route: '/promo', title: 'Promo');
    DVPageDocumentEditor(document)
        .insert(DVPageNode.text('studio promo'), parent: document.root.id);
    await const DVPageStore().save(document);

    await tester.pumpWidget(MaterialApp.router(routerConfig: routerTo('/promo')));
    await tester.pumpAndSettle();

    expect(find.text('studio promo'), findsOneWidget);
  });
}
