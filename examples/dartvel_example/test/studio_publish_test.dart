// Studio's publish loop end to end, through the app's real generated router:
// a page saved to the store is served at its route with no rebuild, while a
// compiled route still wins over a stored one of the same name.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The example's home page animates continuously, so pumpAndSettle never
/// returns on it. Fixed frames are enough here: the store read is a local
/// database query, not an animation.
/// Long enough for a page transition to finish: during one, both the
/// outgoing and incoming pages are in the tree, so a findsNothing assertion
/// would see the page it just left.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

DVPageDocument marketingPage(String route, String headline) {
  final document = DVPageDocument(route: route, title: headline);
  DVPageDocumentEditor(document).insert(
    DVPageNode.text(headline),
    parent: document.root.id,
  );
  return document;
}

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
  });

  tearDown(() {
    database.close();
    DVNavigation.detach();
  });

  testWidgets('a saved page is served at its route without a rebuild',
      (WidgetTester tester) async {
    await const DVPageStore().save(marketingPage('/promo', 'Spring Sale'));

    final router = createDartvelRouter();
    addTearDown(router.dispose);
    // /promo exists in no generated route table — it is data, saved a moment
    // ago, and the running app serves it. Navigating before the first pump
    // keeps the example's bootstrap-dependent home page out of this test.
    router.go('/promo');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    expect(find.text('Spring Sale'), findsOneWidget);
  });

  testWidgets('editing and re-saving changes what the route serves',
      (WidgetTester tester) async {
    const store = DVPageStore();
    await store.save(marketingPage('/promo', 'Spring Sale'));

    final router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/promo');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);
    expect(find.text('Spring Sale'), findsOneWidget);

    // The builder edits and saves again; saving is publishing.
    await store.save(marketingPage('/promo', 'Summer Sale'));
    // Leave and return, so the route rebuilds and re-reads the store.
    router.go('/nothing-here');
    await settle(tester);
    router.go('/promo');
    await settle(tester);

    expect(find.text('Summer Sale'), findsOneWidget);
    expect(find.text('Spring Sale'), findsNothing);
  });

  testWidgets('a compiled route still wins over a stored page',
      (WidgetTester tester) async {
    // /about is a real compiled page in this app. A stored document must not
    // shadow it — the store is consulted only after matching fails.
    await const DVPageStore().save(marketingPage('/about', 'Hijacked'));

    final router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/about');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    expect(find.text('Hijacked'), findsNothing);
  });

  testWidgets('an unknown route renders 404 rather than a blank screen',
      (WidgetTester tester) async {
    final router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/nothing-here');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    expect(find.text('404'), findsOneWidget);
    expect(find.textContaining('/nothing-here'), findsOneWidget);
  });

  testWidgets('a save while the page is on screen updates it live',
      (WidgetTester tester) async {
    // The spec's claim is that changes take effect immediately on running
    // apps. The re-save test above navigates away and back, which would
    // reload anyway; this one never leaves the page.
    const store = DVPageStore();
    await store.save(marketingPage('/promo', 'Before'));

    final router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/promo');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);
    expect(find.text('Before'), findsOneWidget);

    await store.save(marketingPage('/promo', 'After'));
    await settle(tester);

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('a save to another route leaves this page alone',
      (WidgetTester tester) async {
    const store = DVPageStore();
    await store.save(marketingPage('/promo', 'Mine'));

    final router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/promo');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    await store.save(marketingPage('/other', 'Theirs'));
    await settle(tester);

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Theirs'), findsNothing);
  });
}
