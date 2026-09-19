// A right-click on a page's text shows Flutter's menu, with a way to the
// browser's own.
//
// On the web the selection area left the menu to the browser, and the
// browser had nothing to offer: the text is drawn by Flutter, not laid out
// as DOM text, so a right-click showed neither menu. A page now shows
// Flutter's -- Copy, Select all -- and More, which hands the next
// right-click to the browser, which is also what Shift+right-click does.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> clipboard;

  setUp(() {
    DVBrowserMenu.debugIsWeb = true;
    clipboard = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    DVBrowserMenu.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget page() => const MaterialApp(
        home: DVPageShell(
          spec: DVPageScaffoldSpec(),
          child: Center(child: Text('Seasonal menu')),
        ),
      );

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

  testWidgets('selected text has Copy, Select all and More',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());

    await dragAcross(tester, find.text('Seasonal menu'));
    await rightClick(tester, find.text('Seasonal menu'));

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Browser menu'), findsNothing);
  });

  testWidgets('with nothing selected there is still Select all and More',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());

    await rightClick(tester, find.text('Seasonal menu'));

    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  // On the web a click on a menu item focused that button's semantics node,
  // the selection area lost focus, and losing focus cleared the selection --
  // all before the button's tap fired. Copy then copied nothing. It copies
  // what was selected when the menu opened.
  /// What a click on a menu item does on the web before its tap arrives:
  /// Dartvel turns semantics on, the browser focuses the button's semantics
  /// node, and the engine sends that node a focus action.
  Future<void> webFocus(WidgetTester tester, String label) async {
    final SemanticsNode node = tester.getSemantics(find.text(label));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.focus);
    await tester.pump();
  }

  testWidgets('Copy copies the selection a web click would have cleared',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    // Selection is only cleared on losing focus while the app is running.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(page());
    await dragAcross(tester, find.text('Seasonal menu'));
    await rightClick(tester, find.text('Seasonal menu'));

    await webFocus(tester, 'Copy');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboard, isNotEmpty);
    expect(clipboard.last, contains('Seasonal menu'));
    semantics.dispose();
  });

  testWidgets('the menu does not take focus from the selection',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(page());
    await dragAcross(tester, find.text('Seasonal menu'));
    await rightClick(tester, find.text('Seasonal menu'));
    final FocusNode? before = FocusManager.instance.primaryFocus;

    await webFocus(tester, 'Select all');

    expect(FocusManager.instance.primaryFocus, same(before));
    expect(find.text('Copy'), findsOneWidget,
        reason: 'the selection, and the menu over it, are still there');
    semantics.dispose();
  });

  testWidgets('More hands the next right-click to the browser, and says so',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await rightClick(tester, find.text('Seasonal menu'));

    await tester.tap(find.text('More'));
    await tester.pump();

    expect(DVBrowserMenu.nextClickIsNative, isTrue);
    expect(find.text('More'), findsNothing);
    expect(find.text("Right-click again for your browser's menu"),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("Right-click again for your browser's menu"),
        findsNothing);
  });
}
