// A table that is loading is the shape of what is coming.
//
// Error, Empty, and Loading States: skeletons are derived from the model's
// field layout, because a generated table knows its columns before it has
// rows. Before this a table with no rows yet had one thing to show, its empty
// label -- so every table announced "No rows" while its rows were on their
// way, which is the silent kind of wrong: plausible, and false.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Person {
  const Person(this.name, this.age);
  final String name;
  final int age;
}

final List<DVTableColumn<Person>> _columns = <DVTableColumn<Person>>[
  DVTableColumn<Person>(label: 'Name', value: (Person p) => p.name),
  DVTableColumn<Person>(
    label: 'Age',
    value: (Person p) => '${p.age}',
    compare: (Person a, Person b) => a.age.compareTo(b.age),
  ),
];

Future<void> _show(WidgetTester tester, Widget table) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: table)));
  await tester.pump();
}

void main() {
  tearDown(DV.I18n.reset);

  testWidgets('the header is there before the rows are',
      (WidgetTester tester) async {
    await _show(tester, DVTable<Person>.loading(columns: _columns));

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
  });

  testWidgets('a loading table does not say it is empty',
      (WidgetTester tester) async {
    await _show(tester, DVTable<Person>.loading(columns: _columns));

    expect(find.text('No rows'), findsNothing);
    expect(find.bySemanticsLabel('No rows'), findsNothing);
  });

  testWidgets('one placeholder per column, per placeholder row',
      (WidgetTester tester) async {
    await _show(
      tester,
      DVTable<Person>.loading(columns: _columns, placeholderRows: 4),
    );

    expect(find.byType(DVTableSkeletonCell), findsNWidgets(4 * 2));
  });

  testWidgets('a screen reader is told it is loading, once',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _show(tester, DVTable<Person>.loading(columns: _columns));

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the loading words are a framework string',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.tableLoading: 'Chargement',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);

    await _show(tester, DVTable<Person>.loading(columns: _columns));

    expect(find.bySemanticsLabel('Chargement'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('arrow keys have nothing to land on', (WidgetTester tester) async {
    await _show(tester, DVTable<Person>.loading(columns: _columns));
    final DVTableState<Person> state =
        tester.state<DVTableState<Person>>(find.byType(DVTable<Person>));

    await tester.tap(find.byType(DVTableSkeletonCell).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(state.focusedRow, isNull,
        reason: 'a placeholder is not a row anybody can read');
  });

  testWidgets('the rows arriving replace the placeholders',
      (WidgetTester tester) async {
    await _show(tester, DVTable<Person>.loading(columns: _columns));
    await _show(
      tester,
      DVTable<Person>(const <Person>[Person('Ada', 36)], columns: _columns),
    );

    expect(find.byType(DVTableSkeletonCell), findsNothing);
    expect(find.text('Ada'), findsOneWidget);
  });
}
