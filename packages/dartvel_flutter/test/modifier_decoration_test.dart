// Underlined and struck-through text, which the chain could not say.
//
// DVModifier carries every other TextStyle property a design uses -- size,
// weight, family, colour, letter spacing, line height, line limit, overflow
// -- and had no way to underline a word. A link in an imported design came
// through as ordinary text, and a struck-through old price came through as
// the price.
//
// One method taking Flutter's own type rather than underline() and
// strikethrough(), matching overflow(TextOverflow) beside it: a design that
// uses both at once is a real design, and two flags cannot express it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle? styleOf(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first).style;

Future<void> pump(WidgetTester tester, DVModifier modifier) =>
    tester.pumpWidget(
      MaterialApp(home: const DVText('Sale').modifier(modifier)),
    );

void main() {
  testWidgets('an underline reaches the text', (WidgetTester tester) async {
    await pump(tester, const DVModifier().decoration(TextDecoration.underline));

    expect(styleOf(tester)?.decoration, TextDecoration.underline);
  });

  testWidgets('so does a strike-through', (WidgetTester tester) async {
    await pump(
      tester,
      const DVModifier().decoration(TextDecoration.lineThrough),
    );

    expect(styleOf(tester)?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('text nobody decorated carries none',
      (WidgetTester tester) async {
    // Not TextDecoration.none: a style that names it overrides an underline
    // an enclosing theme asked for, which is a decision this modifier was
    // never given.
    await pump(tester, const DVModifier().fontSize(18));

    expect(styleOf(tester)?.decoration, isNull);
  });

  testWidgets('merging keeps a decoration the other side set',
      (WidgetTester tester) async {
    await pump(
      tester,
      const DVModifier()
          .fontSize(18)
          .merge(const DVModifier().decoration(TextDecoration.underline)),
    );

    expect(styleOf(tester)?.decoration, TextDecoration.underline);
    expect(styleOf(tester)?.fontSize, 18);
  });
}
