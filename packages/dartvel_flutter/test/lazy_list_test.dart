// A scrollable DVBox list builds only what is on screen (owner, 12 Nov 2026:
// sigmadev.digital took long to load and then crashed on a phone; Dartvel
// should use less than plain Flutter, and every list is lazy without the
// application writing ListView.builder).
//
// The build's page capture is the exception: it reads the whole page from the
// semantics tree for the HTML crawlers and no-JS readers get, so while it runs
// every list is built whole.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:dartvel_flutter/src/lists/lazy_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counted extends StatelessWidget {
  const _Counted(this.index, this.builds);
  final int index;
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(index);
    return SizedBox(height: 40, child: Text('Row $index of the list'));
  }
}

Widget screen(Widget child) => MaterialApp(
      home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'List'), child: child),
    );

void main() {
  tearDown(() => DVLazyLists.buildWhole = false);

  testWidgets('a long scrollable list builds only the rows on screen', (WidgetTester tester) async {
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      for (int i = 0; i < 500; i++) _Counted(i, builds),
    ])));
    expect(builds.length, lessThan(60), reason: '600 px of 40 px rows, plus a little cache');
    expect(find.text('Row 0 of the list'), findsOneWidget);
    expect(find.text('Row 499 of the list', skipOffstage: false), findsNothing);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Row 0 of the list', skipOffstage: false), findsNothing,
        reason: 'rows scrolled far away are let go');
    expect(builds.toSet().length, lessThan(250));
  });

  testWidgets('a list made scrollable with .scrollable() is lazy too', (WidgetTester tester) async {
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.list(<Widget>[
      for (int i = 0; i < 500; i++) _Counted(i, builds),
    ]).scrollable()));
    expect(builds.length, lessThan(60));
  });

  testWidgets('while the build captures the page, every row is built', (WidgetTester tester) async {
    DVLazyLists.buildWhole = true;
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      for (int i = 0; i < 500; i++) _Counted(i, builds),
    ])));
    expect(builds.toSet().length, 500);
  });

  testWidgets('spacing and alignment are kept', (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      for (int i = 0; i < 20; i++) SizedBox(height: 40, width: 100, child: Text('Item $i')),
    ], spacing: 10)));
    final Rect first = tester.getRect(find.text('Item 0'));
    final Rect second = tester.getRect(find.text('Item 1'));
    expect(second.top - first.top, 50, reason: '40 px row and 10 px gap');
  });

  testWidgets('a long list inside the scrolling page builds its rows as they come near', (WidgetTester tester) async {
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      DVBox.list(<Widget>[for (int i = 0; i < 300; i++) _Counted(i, builds)]),
    ])));
    expect(builds.toSet().length, lessThan(80), reason: 'a page holding 300 rows builds about a screen of them');
    await tester.dragUntilVisible(find.text('Row 200 of the list'), find.byType(Scrollable).first, const Offset(0, -500));
    expect(find.text('Row 200 of the list'), findsOneWidget, reason: 'rows come in as the reader scrolls');
  });

  testWidgets('a row it has built is not painted again while the page scrolls', (WidgetTester tester) async {
    // tools.sigmadev.digital (owner, 13 Nov 2026: severe frame drops when
    // scrolling fast). Every row built so far sat in one column the scroll
    // view repainted on each frame, every card and its shadow included. A
    // Flutter ListView gives each row its own layer; so does this.
    final Map<int, int> paints = <int, int>{};
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      DVBox.list(<Widget>[
        for (int i = 0; i < 300; i++)
          SizedBox(height: 40, child: CustomPaint(painter: _CountingPainter(i, paints), child: Text('Row $i of the list'))),
      ]),
    ])));
    await tester.dragUntilVisible(find.text('Row 200 of the list'), find.byType(Scrollable).first, const Offset(0, -500));
    // One drag first: starting a drag repaints once (not per frame), and what
    // this guards against is a repaint on every frame of a scroll.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -8));
    await tester.pumpAndSettle();
    final int before = paints[200] ?? 0;
    expect(before, greaterThan(0));
    for (int step = 0; step < 5; step++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -8));
      await tester.pump();
    }
    expect(paints[200], before, reason: 'scrolling moves the row, it does not redraw it');
  });

  testWidgets('a long grid inside the scrolling page builds its rows as they come near', (WidgetTester tester) async {
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      DVBox.grid(<Widget>[for (int i = 0; i < 300; i++) _Counted(i, builds)], columns: 3),
    ])));
    expect(builds.toSet().length, lessThan(120));
  });

  testWidgets('while the build captures, a nested list is built whole too', (WidgetTester tester) async {
    DVLazyLists.buildWhole = true;
    final List<int> builds = <int>[];
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      DVBox.list(<Widget>[for (int i = 0; i < 300; i++) _Counted(i, builds)]),
    ])));
    expect(builds.toSet().length, 300);
  });

  testWidgets('Ctrl+F reaches a row of a nested list not built yet', (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      DVBox.list(<Widget>[for (int i = 0; i < 300; i++) SizedBox(height: 40, child: Text('Row $i of the list'))]),
    ])));
    final Future<bool> revealed = DVFindInPage.reveal('Row 250 of the list');
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    final Rect rect = tester.getRect(find.text('Row 250 of the list'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });

  testWidgets("Ctrl+F reaches a row the list has not built", (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.scrollableList(<Widget>[
      for (int i = 0; i < 500; i++) SizedBox(height: 40, child: Text('Row $i of the list')),
    ])));
    expect(find.text('Row 420 of the list', skipOffstage: false), findsNothing, reason: 'not built yet');

    final Future<bool> revealed = DVFindInPage.reveal('Row 420 of the list');
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    final Rect rect = tester.getRect(find.text('Row 420 of the list'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.index, this.paints);
  final int index;
  final Map<int, int> paints;

  @override
  void paint(Canvas canvas, Size size) => paints[index] = (paints[index] ?? 0) + 1;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}
