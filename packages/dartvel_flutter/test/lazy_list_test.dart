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
