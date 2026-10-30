// Empty is not one state.
//
// Error, Empty, and Loading States distinguishes three, because the answers
// differ: nothing yet wants the action that creates the first one, nothing
// matching wants the filter cleared, and nothing visible to you is a policy
// that filtered everything out. They were one state -- "No rows" -- so a
// reader whose search matched nothing was told the table was empty, and a
// reader who could see nothing was sent to support with the wrong question.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<DVTableColumn<String>> _columns = <DVTableColumn<String>>[
  DVTableColumn<String>(label: 'Name', value: (String s) => s),
];

Future<void> _show(WidgetTester tester, DVEmpty empty) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DVTable<String>(const <String>[], columns: _columns, empty: empty),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(DV.I18n.reset);

  testWidgets('nothing yet shows the action that creates the first one',
      (WidgetTester tester) async {
    await _show(
      tester,
      DVEmpty.nothingYet(
        action: TextButton(onPressed: () {}, child: const Text('New order')),
      ),
    );

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('New order'), findsOneWidget);
  });

  testWidgets('nothing matching offers to clear the filter, not to create',
      (WidgetTester tester) async {
    int cleared = 0;
    await _show(tester, DVEmpty.nothingMatching(onClear: () => cleared += 1));

    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);

    await tester.tap(find.text('Clear filters'));
    expect(cleared, 1);
  });

  testWidgets('nothing visible says so, rather than "no records"',
      (WidgetTester tester) async {
    await _show(tester, const DVEmpty.nothingVisible());

    expect(find.text('Nothing here is visible to you'), findsOneWidget);
    expect(find.text('No rows'), findsNothing);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('each is announced once', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _show(tester, DVEmpty.nothingMatching(onClear: () {}));

    expect(find.bySemanticsLabel('No results'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the words are framework strings a catalogue replaces',
      (WidgetTester tester) async {
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.nothingMatching: 'Aucun résultat',
        DVFrameworkStrings.clearFilters: 'Effacer les filtres',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);

    await _show(tester, DVEmpty.nothingMatching(onClear: () {}));

    expect(find.text('Aucun résultat'), findsOneWidget);
    expect(find.text('Effacer les filtres'), findsOneWidget);
  });

  testWidgets('a label of the application\'s own replaces the default',
      (WidgetTester tester) async {
    await _show(tester, const DVEmpty.nothingYet(label: 'No orders yet'));

    expect(find.text('No orders yet'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('with no empty state named, the table still says No rows',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVTable<String>(const <String>[], columns: _columns)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No rows'), findsOneWidget);
  });
}
