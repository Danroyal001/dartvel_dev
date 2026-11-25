// What the reader selects on a page is told to the document too (Tori and
// Learnacer, Dartvel 3.47.7: after the app took over, a script asking
// window.getSelection() got nothing, after a drag, a double-click or a
// triple-click, while Flutter's own copy worked).
//
// Flutter draws the text and keeps the selection to itself. The page shell
// hands every change of it to DVSelectionMirror, which on the web puts the
// selected text in the document and selects it there
// (selection_mirror_browser_test.dart proves that half).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/accessibility/selection_mirror.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String sentence = 'Records are deleted after seven years.';

Widget page({bool selectable = true}) => MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(selectable: selectable),
        child: const Center(child: Text(sentence)),
      ),
    );

Future<void> dragAcross(WidgetTester tester, Finder text) async {
  final Rect line = tester.getRect(text);
  final TestGesture gesture =
      await tester.startGesture(line.centerLeft + const Offset(1, 0), kind: PointerDeviceKind.mouse);
  await tester.pump();
  for (int step = 1; step <= 20; step++) {
    await gesture.moveTo(line.centerLeft + Offset((line.width - 2) * step / 20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  final List<String?> written = <String?>[];
  setUp(() {
    written.clear();
    DVSelectionMirror.write = written.add;
  });
  tearDown(DVSelectionMirror.reset);

  testWidgets('a drag across text hands the selected text to the document', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await dragAcross(tester, find.text(sentence));
    expect(written.last, sentence);
  });

  testWidgets('clearing the selection clears it in the document', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await dragAcross(tester, find.text(sentence));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // Flutter reports a cleared selection as empty text; both mean nothing
    // is selected, and the mirror clears the document for either.
    expect(written.last, anyOf(isNull, isEmpty));
  });

  testWidgets('leaving the page clears what it had selected', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await dragAcross(tester, find.text(sentence));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(written.last, isNull);
  });

  testWidgets('a page that is not selectable tells the document nothing', (WidgetTester tester) async {
    await tester.pumpWidget(page(selectable: false));
    await dragAcross(tester, find.text(sentence));
    expect(written.where((String? text) => text != null), isEmpty);
  });
}
