// What was made in Studio and committed ships in the build, and an
// application with nothing stored -- a phone with no server to ask -- still
// draws it. Anything stored for the same route wins over it.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _doc(String text) => jsonEncode(DVPageDocument(
      route: '/landing',
      root: DVPageNode(type: 'box', children: <DVPageNode>[
        DVPageNode(type: 'text', properties: <String, Object?>{'text': text}),
      ]),
    ).toJson());

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
    DVPageStore.bundled = const <String>[];
  });

  testWidgets('a bundled page is drawn where nothing is stored',
      (WidgetTester tester) async {
    DVPageStore.bundled = <String>[_doc('From the repository'), '{not json'];
    await tester.pumpWidget(const MaterialApp(home: DVStudioPageRoute('/landing')));
    await tester.pumpAndSettle();
    expect(find.text('From the repository'), findsOneWidget);
  });

  testWidgets('a stored page wins over the bundled one', (WidgetTester tester) async {
    DVPageStore.bundled = <String>[_doc('From the repository')];
    await const DVPageStore().save(
        DVPageDocument.fromJson((jsonDecode(_doc('Changed in Studio')) as Map).cast()));
    await tester.pumpWidget(const MaterialApp(home: DVStudioPageRoute('/landing')));
    await tester.pumpAndSettle();
    expect(find.text('Changed in Studio'), findsOneWidget);
  });
}
