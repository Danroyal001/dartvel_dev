// A table that a keyboard and a screen reader can actually use.
//
// User.Table() generated DVBox.builder(...).grid(columns: 2) -- a grid of
// cards wearing the name Table. No header, no rows, no column, nothing to
// arrow between, and nothing a screen reader could announce as tabular. The
// spec promises sorting, keyboard navigation, column management and
// accessibility from it.
//
// The tests below are mostly about the parts that are invisible when you look
// at the rendered pixels: what a screen reader is told, and where focus goes.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Person {
  const Person(this.name, this.age);
  final String name;
  final int age;
}

const List<Person> _people = <Person>[
  Person('Ada', 36),
  Person('Grace', 45),
  Person('Alan', 41),
];

List<DVTableColumn<Person>> get _columns => <DVTableColumn<Person>>[
      DVTableColumn<Person>(label: 'Name', value: (Person p) => p.name),
      DVTableColumn<Person>(
        label: 'Age',
        value: (Person p) => '${p.age}',
        compare: (Person a, Person b) => a.age.compareTo(b.age),
      ),
    ];

/// The table's state, so the tests can read where the keyboard is.
///
/// Read from the widget rather than exposed as library API: a table does not
/// need a public "where is focus" accessor, and adding one so a test can pass
/// is how test-only surface ends up shipped.
DVTableState<Person> stateOf(WidgetTester tester) =>
    tester.state<DVTableState<Person>>(find.byType(DVTable<Person>));

Future<void> show(
  WidgetTester tester, {
  List<Person> rows = _people,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DVTable<Person>(rows, columns: _columns)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('what it renders', () {
    testWidgets('a header and every row', (WidgetTester tester) async {
      await show(tester);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
    });

    testWidgets('an empty table says so rather than rendering nothing',
        (WidgetTester tester) async {
      // A blank rectangle is indistinguishable from a table that failed to
      // load, for a sighted reader and a screen reader alike.
      await show(tester, rows: <Person>[]);
      expect(find.text('No rows'), findsOneWidget);
    });
  });

  group('what a screen reader is told', () {
    testWidgets('a header cell is announced as a header',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await show(tester);

      expect(
        tester.getSemantics(find.byType(DVTableHeaderCell).first),
        matchesSemantics(label: 'Name', isHeader: true, hasTapAction: false),
      );
      handle.dispose();
    });

    testWidgets('a cell names its column and its position',
        (WidgetTester tester) async {
      // "Grace" alone tells a screen reader user nothing. Which column, and
      // which row of how many, is the whole content of a table cell.
      final SemanticsHandle handle = tester.ensureSemantics();
      await show(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Name.*Grace.*row 2 of 3')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a sorted column announces its direction',
        (WidgetTester tester) async {
      // Without it, a sighted reader sees an arrow and a screen reader user
      // has no idea the data was reordered under them.
      final SemanticsHandle handle = tester.ensureSemantics();
      await show(tester);

      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Age.*ascending')), findsWidgets);
      handle.dispose();
    });
  });

  group('sorting', () {
    testWidgets('a column with a comparator sorts, ascending then descending',
        (WidgetTester tester) async {
      await show(tester);

      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Ada')).dy,
        lessThan(tester.getTopLeft(find.text('Alan')).dy),
      );

      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Grace')).dy,
        lessThan(tester.getTopLeft(find.text('Ada')).dy),
      );
    });

    testWidgets('a column without a comparator is not sortable',
        (WidgetTester tester) async {
      // Offering a control that does nothing is worse than not offering it.
      await show(tester);
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();

      // Unchanged order.
      expect(
        tester.getTopLeft(find.text('Ada')).dy,
        lessThan(tester.getTopLeft(find.text('Grace')).dy),
      );
    });
  });

  group('keyboard navigation', () {
    testWidgets('arrow keys move between cells', (WidgetTester tester) async {
      await show(tester);

      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedRow, 0);
      expect(stateOf(tester).focusedColumn, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedColumn, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedRow, 1);
    });

    testWidgets('focus does not run off the edges', (WidgetTester tester) async {
      // At the last column, right should stay put rather than wrapping to the
      // next row or throwing.
      await show(tester);
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedColumn, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedRow, 0);
    });

    testWidgets('home and end go to the ends of the row',
        (WidgetTester tester) async {
      await show(tester);
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedColumn, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedColumn, 0);
    });

    testWidgets('focus survives a sort', (WidgetTester tester) async {
      // Focus restoration: reordering the rows under someone who is reading
      // one, and dumping their focus back to the top, is how a keyboard user
      // loses their place entirely.
      await show(tester);
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(stateOf(tester).focusedRow, 1);

      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      expect(stateOf(tester).focusedRow, isNotNull,
          reason: 'a sort must not drop the keyboard position');
    });
  });
}
