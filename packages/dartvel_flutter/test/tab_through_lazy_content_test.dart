// Tab reaches every control on a page, including the ones a lazy list has
// not built yet (Tori and Learnacer, Dartvel 3.47.7: Tab never reached the
// footer links on a long page).
//
// Every scrollable DVBox list is lazy, and so is a long DVBox list in a page
// that scrolls (DVNearScreen). A row that is not built has no focus node, so
// Flutter's traversal could not go to it: a layout that is one scrollable list
// of header, page and footer left the footer out of the Tab order, and Tab
// from the last control built went back to the top of the page. Rows of a long
// catalogue past the second screen were skipped the same way, Tab jumping from
// the last built row to the footer. The page shell now scrolls the content
// that is not built yet into being before it lets the focus leave it, in both
// directions.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/lists/lazy_lists.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget screen(Widget child) => MaterialApp(
      home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Long page'), child: child),
    );

Widget button(String label) => TextButton(onPressed: () {}, child: Text(label));

/// The words of the control that has the focus, or null.
String? focusedLabel() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) return null;
  String? found;
  void visit(Element element) {
    if (found != null) return;
    final Widget widget = element.widget;
    if (widget is Text) {
      found = widget.data;
      return;
    }
    element.visitChildElements(visit);
  }

  visit(context);
  return found;
}

Future<String?> tab(WidgetTester tester, {bool back = false}) async {
  if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
  return focusedLabel();
}

/// Presses Tab until [label] has the focus, and returns every label on the
/// way; fails after [limit] presses.
Future<List<String?>> tabUntil(WidgetTester tester, String label, {bool back = false, int limit = 200}) async {
  final List<String?> seen = <String?>[];
  for (int press = 0; press < limit; press++) {
    final String? now = await tab(tester, back: back);
    seen.add(now);
    if (now == label) return seen;
  }
  fail('Tab never reached "$label" in $limit presses; went through ${seen.toSet()}');
}

/// The layout shape Learnacer uses: header, page and footer as one
/// scrollable DVBox list, which is a lazy ListView.
Widget layoutPage({int paragraphs = 80}) => DVBox.list(<Widget>[
      DVBox.row(<Widget>[button('Home'), button('Catalogue')]),
      DVBox.list(<Widget>[
        for (int i = 0; i < paragraphs; i++)
          Text('Paragraph $i of the long page, about records and how long they are kept.'),
        button('Last body link'),
      ], spacing: 12),
      DVBox.list(<Widget>[
        const Text('Made by somebody'),
        DVBox.row(<Widget>[button('Privacy'), button('Terms of use')]),
      ]),
    ], spacing: 0).scrollable();

/// A long collection in a page that scrolls: rows past the first screens are
/// DVNearScreen placeholders, with the footer built after them.
Widget cataloguePage() => DVBox.list(<Widget>[
      DVBox.list(<Widget>[
        for (int i = 0; i < 60; i++)
          DVBox.list(<Widget>[Text('Tool number $i'), button('Open tool $i')], spacing: 4),
      ], spacing: 12),
      button('Footer link'),
    ], spacing: 12);

void main() {
  tearDown(() => DVLazyLists.buildWhole = false);

  testWidgets('the footer of a layout that is one lazy list is not built at first', (WidgetTester tester) async {
    await tester.pumpWidget(screen(layoutPage()));
    // The premise of the bug: without this the tests below prove nothing.
    expect(find.text('Privacy', skipOffstage: false), findsNothing);
  });

  testWidgets('Tab goes on from the last control built to the footer links', (WidgetTester tester) async {
    await tester.pumpWidget(screen(layoutPage()));
    final List<String?> seen = await tabUntil(tester, 'Privacy');
    expect(seen.where((String? label) => label == 'Home').length, 1,
        reason: 'reached without going round to the top again: $seen');
    expect(seen, containsAllInOrder(<String>['Home', 'Catalogue', 'Last body link', 'Privacy']));
    expect(await tab(tester), 'Terms of use');
    expect(tester.getRect(find.text('Terms of use')).bottom, lessThanOrEqualTo(600),
        reason: 'the focused link is scrolled into view');
  });

  testWidgets('Shift+Tab from the footer goes back up through what was let go', (WidgetTester tester) async {
    await tester.pumpWidget(screen(layoutPage(paragraphs: 200)));
    await tabUntil(tester, 'Terms of use');
    // The header is far above by now, and the lazy list has let it go.
    expect(find.text('Home', skipOffstage: false), findsNothing);
    final List<String?> seen = await tabUntil(tester, 'Home', back: true);
    expect(seen, containsAllInOrder(<String>['Privacy', 'Last body link', 'Catalogue', 'Home']));
    expect(seen.where((String? label) => label == 'Terms of use'), isEmpty,
        reason: 'reached without going round to the bottom again: $seen');
  });

  testWidgets('Tab visits every row of a long collection before the footer after it', (WidgetTester tester) async {
    await tester.pumpWidget(screen(cataloguePage()));
    // The premise: the last rows are placeholders and the footer is built.
    expect(find.text('Open tool 59', skipOffstage: false), findsNothing);
    expect(find.text('Footer link', skipOffstage: false), findsOneWidget);
    final List<String?> seen = await tabUntil(tester, 'Footer link');
    expect(seen, <String>[for (int i = 0; i < 60; i++) 'Open tool $i', 'Footer link']);
  });

  testWidgets('Shift+Tab visits every row of a long collection on the way back', (WidgetTester tester) async {
    await tester.pumpWidget(screen(cataloguePage()));
    await tabUntil(tester, 'Footer link');
    final List<String?> seen = await tabUntil(tester, 'Open tool 0', back: true);
    expect(seen, <String>[for (int i = 59; i >= 0; i--) 'Open tool $i']);
  });

  testWidgets('Tab from a control past a long stretch with nothing to focus reaches the next one', (WidgetTester tester) async {
    // The list keeps the focused row alive after it scrolls out of view, at
    // its old place: Flutter's traversal from there went round to the top.
    await tester.pumpWidget(screen(Column(children: <Widget>[
      button('Fixed'),
      Expanded(
        child: DVBox.list(<Widget>[
          button('Only link'),
          for (int i = 0; i < 300; i++) Text('Plain row $i'),
          button('End link'),
        ]).scrollable(),
      ),
    ])));
    await tabUntil(tester, 'Only link');
    expect(await tab(tester), 'End link');
    expect(await tab(tester, back: true), 'Only link');
  });

  testWidgets('a reader who moves the focus while a walk scrolls keeps it there', (WidgetTester tester) async {
    await tester.pumpWidget(screen(Column(children: <Widget>[
      button('Fixed'),
      Expanded(
        child: DVBox.list(<Widget>[
          button('Only link'),
          for (int i = 0; i < 300; i++) Text('Plain row $i'),
          button('End link'),
        ]).scrollable(),
      ),
    ])));
    await tabUntil(tester, 'Only link');
    // Tab starts a walk: nothing focusable is built below, so the list
    // scrolls a screen a frame towards End link.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    // Before it gets there, the reader puts the focus on another control.
    Focus.of(tester.element(find.text('Fixed'))).requestFocus();
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'Fixed', reason: 'the walk does not take the focus back');
  });

  testWidgets('a page whose list is all built tabs as before', (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.list(<Widget>[button('One'), button('Two'), button('Three')])));
    expect(await tab(tester), 'One');
    expect(await tab(tester), 'Two');
    expect(await tab(tester), 'Three');
    expect(await tab(tester, back: true), 'Two');
  });

  testWidgets('a lazy list whose rest holds no controls lets Tab go on as before', (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.list(<Widget>[
      button('Only link'),
      for (int i = 0; i < 200; i++) Text('Plain row $i'),
    ]).scrollable()));
    expect(await tab(tester), 'Only link');
    // Nothing focusable is left below: the focus goes round, as Flutter's own
    // traversal does on this platform, after the list has been looked through.
    expect(await tab(tester), 'Only link');
  });
}
