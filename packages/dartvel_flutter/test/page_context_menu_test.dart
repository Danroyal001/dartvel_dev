// A right-click on a page's text shows Flutter's menu, with a way to the
// browser's own.
//
// On the web the selection area left the menu to the browser, and the
// browser had nothing to offer: the text is drawn by Flutter, not laid out
// as DOM text, so a right-click showed neither menu. A page now shows
// Flutter's -- Copy, Select all -- and a "Browser menu" item that hands the
// next right-click to the browser, which is also what Shift+right-click does.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => DVBrowserMenu.debugIsWeb = true);
  tearDown(DVBrowserMenu.debugReset);

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final TestGesture mouse = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();
  }

  Future<void> dragAcross(WidgetTester tester, Finder target) async {
    final Rect box = tester.getRect(target);
    final TestGesture mouse = await tester.startGesture(
      box.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(box.centerRight - const Offset(1, 0));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
  }

  testWidgets('selected text has Copy and a Browser menu item',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(),
        child: Center(child: Text('Seasonal menu')),
      ),
    ));

    await dragAcross(tester, find.text('Seasonal menu'));
    await rightClick(tester, find.text('Seasonal menu'));

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Browser menu'), findsOneWidget);
  });

  testWidgets('with nothing selected there is still Select all and Browser menu',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(),
        child: Center(child: Text('Seasonal menu')),
      ),
    ));

    await rightClick(tester, find.text('Seasonal menu'));

    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Browser menu'), findsOneWidget);
  });

  testWidgets('Browser menu hands the next right-click to the browser',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(),
        child: Center(child: Text('Seasonal menu')),
      ),
    ));
    await rightClick(tester, find.text('Seasonal menu'));

    await tester.tap(find.text('Browser menu'));
    await tester.pumpAndSettle();

    expect(DVBrowserMenu.nextClickIsNative, isTrue);
    expect(find.text('Browser menu'), findsNothing);
  });
}
