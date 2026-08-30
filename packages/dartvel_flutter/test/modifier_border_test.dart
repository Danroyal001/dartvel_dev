// DVModifier.border.
//
// Without it there is no way to draw a rule under a header or a hairline round
// a card with DVBox, so every one of those reaches for a raw Container and a
// BoxDecoration -- which is how a codebase ends up half Dartvel and half
// Flutter, and why this gap is worth closing rather than working around.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BoxDecoration decorationOf(WidgetTester tester) {
  final Container container = tester.widget<Container>(
    find.byType(Container).first,
  );
  return container.decoration! as BoxDecoration;
}

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('a border reaches the decoration', (WidgetTester tester) async {
    await pump(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier().border(
          const Border(bottom: BorderSide(color: Color(0xFF112233))),
        ),
      ),
    );

    final BoxDecoration decoration = decorationOf(tester);
    expect(decoration.border, isNotNull);
    expect(
      (decoration.border! as Border).bottom.color,
      const Color(0xFF112233),
    );
  });

  testWidgets('no border leaves the decoration without one',
      (WidgetTester tester) async {
    // A default border would put a hairline round every DVBox in an
    // application, which is the kind of change nobody asks for and everybody
    // notices.
    await pump(
      tester,
      DVBox(const DVText('x'), const DVModifier().padding(4)),
    );

    expect(decorationOf(tester).border, isNull);
  });

  testWidgets('a border composes with the rest of the chain',
      (WidgetTester tester) async {
    // The modifier is a chain, and a link that quietly drops what came before
    // it is worse than one that does nothing.
    await pump(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier()
            .backgroundColor(const Color(0xFF010203))
            .rounded(12)
            .border(const Border.fromBorderSide(
              BorderSide(color: Color(0xFF445566), width: 2),
            ))
            .padding(8),
      ),
    );

    final BoxDecoration decoration = decorationOf(tester);
    expect(decoration.color, const Color(0xFF010203));
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect((decoration.border! as Border).top.width, 2);
  });

  testWidgets('a later border replaces an earlier one',
      (WidgetTester tester) async {
    await pump(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier()
            .border(const Border(top: BorderSide(color: Color(0xFF000001))))
            .border(const Border(top: BorderSide(color: Color(0xFF000002)))),
      ),
    );

    expect(
      (decorationOf(tester).border! as Border).top.color,
      const Color(0xFF000002),
    );
  });

  testWidgets('a border round text is a DVBox, not a property of DVText',
      (WidgetTester tester) async {
    // DVText carries text properties and DVBox carries box properties. I
    // assumed the modifier chain meant every property worked everywhere and
    // wrote this the other way round first; giving DVText its own decoration
    // would be a second way to do what DVBox already does, and two ways is how
    // a design stops being one.
    await pump(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier().border(
          const Border.fromBorderSide(BorderSide(color: Color(0xFF778899))),
        ),
      ),
    );

    expect(decorationOf(tester).border, isNotNull);
  });
}
