// A web app served by its own server shows the pages Studio published there.
//
// Studio on a web-server binary publishes into the server's database, and the
// app's page store read DV.Database in the browser, where nothing had been
// published: the page was stored and the site never showed it. The store can
// read its documents from somewhere else -- the server -- and reading again
// takes a reverted page back to the compiled one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final DVPageDocument document = DVPageDocument(route: route, title: text);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

void main() {
  late List<DVPageDocument> published;

  setUp(() {
    published = <DVPageDocument>[];
    DVPageStore.resetCache();
    DVPageStore.source = () async => published;
  });

  tearDown(() {
    DVPageStore.source = null;
    DVPageStore.resetCache();
  });

  Widget host(String route) => MaterialApp(
        home: DVStudioPageRoute(route, fallback: const Text('compiled page')),
      );

  testWidgets('a page published on the server takes over its route',
      (WidgetTester tester) async {
    published.add(documentFor('/menu', 'Published menu'));

    await tester.pumpWidget(host('/menu'));
    await tester.pumpAndSettle();

    expect(find.text('Published menu'), findsOneWidget);
    expect(find.text('compiled page'), findsNothing);
  });

  testWidgets('a route with no compiled page is served from the server too',
      (WidgetTester tester) async {
    published.add(documentFor('/specials', 'Today only'));

    await tester.pumpWidget(
        const MaterialApp(home: DVStudioPageRoute('/specials')));
    await tester.pumpAndSettle();

    expect(find.text('Today only'), findsOneWidget);
  });

  testWidgets('reading again after a revert brings the compiled page back',
      (WidgetTester tester) async {
    published.add(documentFor('/menu', 'Published menu'));
    await tester.pumpWidget(host('/menu'));
    await tester.pumpAndSettle();
    expect(find.text('Published menu'), findsOneWidget);

    published.clear();
    await DVPageStore.reload();
    await tester.pumpAndSettle();

    expect(find.text('compiled page'), findsOneWidget);
    expect(find.text('Published menu'), findsNothing);
  });
}
