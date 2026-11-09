// A text field that a mouse click could not focus.
//
// Found on Tori: on the desktop web, the first click into a multi-line field
// right after clicking a button ("Paste text") left the field unfocused, and
// typing went nowhere. The second click worked.
//
// The click starts by taking focus off the button. For that moment nothing
// holds focus, and the page's keyboard scrolling took focus back straight
// away -- in the middle of the click. On the web that moved the browser's own
// focus to the page's node, away from the text field the reader was clicking,
// so the field never started editing. The page has to wait until the click is
// over, and take focus back only if the click left it nowhere.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool pageHoldsFocus() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'DVKeyboardScroll';

void main() {
  late FocusNode button;
  late FocusNode field;

  setUp(() {
    button = FocusNode(debugLabel: 'button');
    field = FocusNode(debugLabel: 'field');
  });
  tearDown(() {
    button.dispose();
    field.dispose();
  });

  Widget page() => MaterialApp(
        home: DVPageShell(
          spec: const DVPageScaffoldSpec(title: 'Add a book'),
          child: Column(children: <Widget>[
            TextButton(focusNode: button, onPressed: () {}, child: const Text('Paste text')),
            TextField(focusNode: field, minLines: 8, maxLines: 16),
            const SizedBox(key: Key('blank'), height: 200, width: 200),
          ]),
        ),
      );

  testWidgets('a click from a button into a text field is not interrupted '
      'by the page taking focus', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    button.requestFocus();
    await tester.pumpAndSettle();
    expect(button.hasPrimaryFocus, isTrue);

    final TestGesture click = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
      kind: PointerDeviceKind.mouse,
    );
    // What the browser does as the button is clicked away from: it loses focus.
    button.unfocus();
    await tester.pump();
    expect(pageHoldsFocus(), isFalse,
        reason: 'taking focus mid-click moves the browser focus off the field '
            'being clicked, so the field never starts editing');

    await click.up();
    await tester.pumpAndSettle();
    expect(field.hasPrimaryFocus, isTrue);
    expect(pageHoldsFocus(), isFalse);
  });

  testWidgets('a click that lands on nothing still gives the page its keys back',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    button.requestFocus();
    await tester.pumpAndSettle();

    final TestGesture click = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('blank'))),
      kind: PointerDeviceKind.mouse,
    );
    button.unfocus();
    await tester.pump();
    await click.up();
    await tester.pumpAndSettle();

    expect(pageHoldsFocus(), isTrue,
        reason: 'with nothing focused after the click, the arrows must scroll '
            'the page again');
  });
}
