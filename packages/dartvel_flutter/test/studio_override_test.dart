// Override precedence, tested directly on the widget the generated router
// wraps every compiled page in.
//
// The rule the builder depends on: a stored document OVERRIDES the compiled
// @DVPage. A compiled page is the entrypoint an app ships with, not a fixture
// — if it always won, a shipped page could never be edited, only added to.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: text);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

Widget host(String route) => MaterialApp(
      home: DVStudioPageRoute(
        route,
        fallback: const Text('compiled page'),
      ),
    );

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  testWidgets('the compiled page serves when nothing overrides it',
      (WidgetTester tester) async {
    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();

    expect(find.text('compiled page'), findsOneWidget);
  });

  testWidgets('a stored document overrides the compiled page',
      (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/about', 'edited in studio'));

    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();

    expect(find.text('edited in studio'), findsOneWidget);
    expect(find.text('compiled page'), findsNothing);
  });

  testWidgets('editing a compiled route takes effect on a running app',
      (WidgetTester tester) async {
    // The OTA/editor case: the app is showing the page it shipped with when
    // an edit to that same route is published.
    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();
    expect(find.text('compiled page'), findsOneWidget);

    await const DVPageStore().save(documentFor('/about', 'overridden live'));
    await tester.pumpAndSettle();

    expect(find.text('overridden live'), findsOneWidget);
    expect(find.text('compiled page'), findsNothing);
  });

  testWidgets('deleting the document restores the compiled page',
      (WidgetTester tester) async {
    const store = DVPageStore();
    await store.save(documentFor('/about', 'temporary edit'));
    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();
    expect(find.text('temporary edit'), findsOneWidget);

    // Reverting an edit must bring back what the app shipped with.
    await store.delete('/about');
    await tester.pumpAndSettle();

    expect(find.text('compiled page'), findsOneWidget);
    expect(find.text('temporary edit'), findsNothing);
  });

  testWidgets('a save to another route leaves this page alone',
      (WidgetTester tester) async {
    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();

    await const DVPageStore().save(documentFor('/other', 'not this one'));
    await tester.pumpAndSettle();

    expect(find.text('compiled page'), findsOneWidget);
    expect(find.text('not this one'), findsNothing);
  });

  testWidgets('a route with no compiled page and no document renders 404',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DVStudioPageRoute('/nothing-here')),
    );
    await tester.pumpAndSettle();

    // A blank screen is indistinguishable from a crash.
    expect(find.text('404'), findsOneWidget);
    expect(find.textContaining('/nothing-here'), findsOneWidget);
  });

  testWidgets('a document saved before priming still wins on first paint',
      (WidgetTester tester) async {
    // Cold start: prime() reads the store, and a save that landed first must
    // not be clobbered by that read.
    await const DVPageStore().save(documentFor('/about', 'from cache'));
    DVPageStore.resetCache();
    await const DVPageStore().save(documentFor('/about', 'saved first'));

    await tester.pumpWidget(host('/about'));
    await tester.pumpAndSettle();

    expect(find.text('saved first'), findsOneWidget);
  });
}
