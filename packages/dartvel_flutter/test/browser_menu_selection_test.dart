// When the browser's own menu is switched, the page's selection area is
// rebuilt whole, and nothing on the page loses its state.
//
// Flutter's selection area is shaped differently while the browser's menu is
// on, and reads that only when it rebuilds. Dartvel switches the menu off
// after the first page has built, so the next rebuild -- choosing another
// Studio screen in the rail -- changed the area's shape in place: a second
// selection container registered while the first still was, and a release
// build failed with "Null check operator used on a null value" when one of
// them left.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        TextButton(onPressed: () => setState(() => taps++), child: const Text('Tap')),
        Text('Tapped $taps times, a sentence to select'),
      ]);
}

void main() {
  tearDown(DVBrowserMenu.debugReset);

  testWidgets('a switch of the browser menu gives the page a new selection area and keeps its state',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(spec: DVPageScaffoldSpec(), child: Center(child: _Counter())),
    ));
    await tester.tap(find.text('Tap'));
    await tester.pumpAndSettle();
    final SelectableRegionState before = tester.state(find.byType(SelectableRegion));

    DVBrowserMenu.debugSetNativeMenuOn(false);
    await tester.pumpAndSettle();

    final SelectableRegionState after = tester.state(find.byType(SelectableRegion));
    expect(identical(before, after), isFalse, reason: 'the area is replaced, not reshaped in place');
    expect(find.text('Tapped 1 times, a sentence to select'), findsOneWidget,
        reason: 'the page beneath keeps its state');
    expect(tester.takeException(), isNull);

    // And the new area selects and copies.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    final Rect line = tester.getRect(find.text('Tapped 1 times, a sentence to select'));
    final TestGesture gesture = await tester.startGesture(line.centerLeft + const Offset(1, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (int step = 1; step <= 20; step++) {
      await gesture.moveTo(line.centerLeft + Offset((line.width - 2) * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied, 'Tapped 1 times, a sentence to select');
  });

  testWidgets('switching back and forth leaves one container registered with each area',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(spec: DVPageScaffoldSpec(), child: Center(child: _Counter())),
    ));
    for (final bool on in <bool>[false, true, false]) {
      DVBrowserMenu.debugSetNativeMenuOn(on);
      await tester.pumpAndSettle();
    }
    final Iterable<SelectionContainer> registeredWithArea = tester
        .widgetList<SelectionContainer>(find.byType(SelectionContainer))
        .where((SelectionContainer container) => container.registrar is SelectableRegionState);
    expect(registeredWithArea, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
