// The keys a person types with reach the text field, on every page.
//
// Every page carries keyboard scrolling and a remote's D-pad above its
// content. Both answered Space, Enter, the arrows, Home, End and the page
// keys as handled even while a text field had focus, so in a browser Space
// scrolled the page instead of typing, the caret would not move, and Enter
// never submitted a form -- Studio's sign-in included.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(TextEditingController, ScrollController)> pumpFormPage(WidgetTester tester) async {
  final TextEditingController field = TextEditingController(text: 'abcd');
  final ScrollController scroll = ScrollController();
  addTearDown(field.dispose);
  addTearDown(scroll.dispose);
  await tester.pumpWidget(MaterialApp(
    home: DVPageShell(
      spec: const DVPageScaffoldSpec(),
      child: ListView(
        controller: scroll,
        children: <Widget>[
          TextField(key: const ValueKey<String>('field'), controller: field),
          const SizedBox(height: 4000),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (field, scroll);
}

void main() {
  for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.home,
  ]) {
    testWidgets('${key.keyLabel} typed into a field is left to the field', (WidgetTester tester) async {
      final (TextEditingController _, ScrollController scroll) = await pumpFormPage(tester);
      await tester.tap(find.byKey(const ValueKey<String>('field')));
      await tester.pumpAndSettle();
      final bool handledByPage = await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      // Handled means the browser is told the page used the key, and the
      // field never sees it. Home, End and Page Down are the field's own caret
      // moves, which the field itself handles; what matters is that the page
      // did not take them, so it did not scroll.
      if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
        expect(handledByPage, isFalse);
      }
      expect(scroll.offset, 0);
    });
  }

  testWidgets('the arrows move the caret in a field', (WidgetTester tester) async {
    final (TextEditingController field, ScrollController _) = await pumpFormPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('field')));
    await tester.pumpAndSettle();
    field.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(field.selection.baseOffset, 3);
  });

  testWidgets('with no field focused, Space still scrolls the page', (WidgetTester tester) async {
    final (TextEditingController _, ScrollController scroll) = await pumpFormPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
  });
}
