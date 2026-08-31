// A grid that is three columns wide on a phone is not a grid, it is an
// overflow.
//
// DVBox.grid took a fixed `columns` and used it at every width, so the only
// way to be responsive was for the application to measure the screen itself
// and pass a different number -- which is the boilerplate the primitives exist
// to remove, and which nobody does until a phone screenshot shames them into
// it.
//
// `columns` now means "at most this many, on a large screen", and the count
// steps down on narrower ones. A developer who needs the old behaviour asks
// for it with `responsive: false`.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> render(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

int gridColumns(WidgetTester tester) {
  final GridView grid = tester.widget<GridView>(find.byType(GridView));
  return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
      .crossAxisCount;
}

List<Widget> cards(int n) =>
    <Widget>[for (int i = 0; i < n; i++) DVText('card $i')];

void main() {
  group('a static grid', () {
    testWidgets('uses the asked-for columns on a desktop',
        (WidgetTester tester) async {
      await render(tester, const Size(1440, 900),
          DVBox.grid(cards(9), columns: 3));
      expect(gridColumns(tester), 3);
    });

    testWidgets('steps down to two on a tablet', (WidgetTester tester) async {
      await render(tester, const Size(900, 1200),
          DVBox.grid(cards(9), columns: 3));
      expect(gridColumns(tester), 2);
    });

    testWidgets('is a single column on a phone', (WidgetTester tester) async {
      await render(
          tester, const Size(390, 844), DVBox.grid(cards(9), columns: 3));
      expect(gridColumns(tester), 1);
    });

    testWidgets('never asks for more columns than it was given',
        (WidgetTester tester) async {
      // A two-column grid on a wide display stays two columns. `columns` is a
      // ceiling, not a target -- widening it on the developer's behalf would
      // change a deliberate layout.
      await render(tester, const Size(1920, 1080),
          DVBox.grid(cards(9), columns: 2));
      expect(gridColumns(tester), 2);
    });

    testWidgets('a fixed grid is left alone', (WidgetTester tester) async {
      await render(tester, const Size(390, 844),
          DVBox.grid(cards(9), columns: 3, responsive: false));
      expect(gridColumns(tester), 3);
    });

    testWidgets('it reflows when the window resizes',
        (WidgetTester tester) async {
      // The reason this belongs in the primitive rather than at the call
      // site: a value read once at construction cannot do this.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DVBox.grid(cards(9), columns: 3)),
      ));
      expect(gridColumns(tester), 3);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(gridColumns(tester), 1);
    });
  });

  group('a builder grid', () {
    testWidgets('follows the same ladder', (WidgetTester tester) async {
      await render(
        tester,
        const Size(390, 844),
        DVBox.builder<int>(
          const <int>[1, 2, 3, 4],
          (int n) => DVText('$n'),
        ).grid(columns: 3),
      );
      expect(gridColumns(tester), 1);
    });
  });

  group('masonry', () {
    testWidgets('collapses to one column on a phone',
        (WidgetTester tester) async {
      // Masonry builds a Row of Expanded columns, so three of them on a
      // 390pt screen leaves 130pt each: text wraps to one word per line.
      await render(
          tester, const Size(390, 844), DVBox.masonry(cards(6), columns: 3));

      final Finder row = find.descendant(
        of: find.byType(DVBox),
        matching: find.byType(Row),
      );
      expect(tester.widgetList<Expanded>(
              find.descendant(of: row.first, matching: find.byType(Expanded)))
          .length, 1);
    });
  });

  testWidgets('a grid with fewer children than columns does not pad out',
      (WidgetTester tester) async {
    // Two cards in a three-column grid should not leave a third of the row
    // empty on a wide screen just because the ceiling allows it.
    await render(
        tester, const Size(1440, 900), DVBox.grid(cards(2), columns: 3));
    expect(gridColumns(tester), 2);
  });
}
