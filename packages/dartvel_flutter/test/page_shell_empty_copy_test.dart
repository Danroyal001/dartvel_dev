// Ctrl+C with nothing selected leaves the clipboard alone.
//
// Checked on dartvel.dev in Chrome (16 Nov 2026): after a click left an empty
// selection, Ctrl+C wrote an empty string over whatever the reader had
// copied. A copy with nothing to copy does nothing, as it does in every
// browser and editor; with text selected it copies that text, as before.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget page() => const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Terms'),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Text('The terms for dartvel.dev and Dartvel.'),
              Text('Last updated 1 October 2026.'),
            ],
          ),
        ),
      ),
    );

Future<void> copy(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  late List<String?> written;
  setUp(() {
    written = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        written.add((call.arguments as Map<Object?, Object?>)['text'] as String?);
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': written.isEmpty ? 'kept' : written.last};
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  testWidgets('a click, then Ctrl+C, writes nothing to the clipboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final TestGesture mouse = await tester.startGesture(
        tester.getCenter(find.text('Last updated 1 October 2026.')),
        kind: PointerDeviceKind.mouse);
    await mouse.up();
    await tester.pumpAndSettle();
    await copy(tester);
    expect(written, isEmpty, reason: 'an empty copy overwrote the clipboard');
  });

  testWidgets('with text selected, Ctrl+C copies it', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final Offset start = tester.getTopLeft(find.text('The terms for dartvel.dev and Dartvel.'));
    final TestGesture mouse = await tester.startGesture(start + const Offset(1, 5),
        kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getBottomRight(find.text('The terms for dartvel.dev and Dartvel.')) - const Offset(1, 2));
    await mouse.up();
    await tester.pumpAndSettle();
    await copy(tester);
    expect(written, isNotEmpty);
    expect(written.last, contains('The terms for dartvel.dev'));
  });
}
