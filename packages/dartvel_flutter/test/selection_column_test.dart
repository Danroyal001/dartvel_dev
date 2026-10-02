// Text beside a column of separate selectables can be drag-selected.
//
// A selection area asks its selectables, in reading order, where a drag
// begins, and stops at the first that says the pointer is above it. Flutter
// orders a tall scrolling content column after the short sidebar texts to its
// left, so a drag across a line of content reached a lower sidebar item first
// and stopped: nothing was selected and Ctrl+C copied an empty string.
// Studio's rail and list panes beside its scrolling workspace are exactly that
// layout.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String contentLine = 'A line of content beside the sidebar';

Widget sidebarLayout({required bool grouped}) {
  final Widget sidebar = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (int item = 0; item < 8; item++)
        Padding(padding: const EdgeInsets.only(bottom: 40), child: Text('Sidebar item $item')),
    ],
  );
  return MaterialApp(
    home: Material(
      child: SelectionArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 240, child: grouped ? DVSelectionColumn(child: sidebar) : sidebar),
            // A scrolling workspace: one tall selectable, as Studio's is.
            const Expanded(
              child: SizedBox(
                height: 600,
                child: SingleChildScrollView(
                  child: Padding(padding: EdgeInsets.only(top: 50), child: Text(contentLine)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Drags across [target] with a mouse, presses Ctrl+C, and answers what reached
/// the clipboard.
Future<String?> dragAcrossAndCopy(WidgetTester tester, Finder target) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
    if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
    return null;
  });
  final Rect line = tester.getRect(target);
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
  return copied;
}

void main() {
  testWidgets('without grouping, a drag beside a sidebar selects nothing', (WidgetTester tester) async {
    await tester.pumpWidget(sidebarLayout(grouped: false));
    expect(await dragAcrossAndCopy(tester, find.text(contentLine)), isNot(contentLine));
  });

  testWidgets('a DVSelectionColumn sidebar lets the content beside it be selected', (WidgetTester tester) async {
    await tester.pumpWidget(sidebarLayout(grouped: true));
    expect(await dragAcrossAndCopy(tester, find.text(contentLine)), contentLine);
  });

  testWidgets('a drag from the sidebar into the content selects both, in order', (WidgetTester tester) async {
    await tester.pumpWidget(sidebarLayout(grouped: true));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    final Offset from = tester.getRect(find.text('Sidebar item 0')).centerLeft + const Offset(1, 0);
    final Offset to = tester.getRect(find.text(contentLine)).centerRight - const Offset(1, 0);
    final TestGesture gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (int step = 1; step <= 20; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied, startsWith('Sidebar item 0'));
    expect(copied, contains('Sidebar item 7'));
    expect(copied, endsWith(contentLine));
  });

  testWidgets('text inside a DVSelectionColumn is still selectable', (WidgetTester tester) async {
    await tester.pumpWidget(sidebarLayout(grouped: true));
    expect(await dragAcrossAndCopy(tester, find.text('Sidebar item 3')), 'Sidebar item 3');
  });

  testWidgets('with no selection area above, it draws its child and nothing else', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DVSelectionColumn(child: Text('alone'))));
    expect(find.text('alone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
