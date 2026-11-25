// An input draws its value in the text style its modifier gives.
//
// `DVText(value).modifier(DVModifier().color(...).fontSize(16).fontFamily(...)
// .input(...))` styled every other DVText and was ignored by the field: the
// value came out in the Material theme's body style. A launcher with a light
// drawer under a dark app theme typed white on white, and the font and size an
// app chose for its search box never showed.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the typed value takes the colour, size, weight, spacing and family of the modifier', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: DVText('wifi').modifier(DVModifier()
            .color(const Color(0xFF1F2328))
            .fontSize(16)
            .fontWeight(FontWeight.w700)
            .letterSpacing(-0.2)
            .fontFamily('JetBrainsMono')
            .input(label: 'Search apps', onChanged: (_) {})),
      ),
    ));
    final EditableText field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.style.color, const Color(0xFF1F2328), reason: 'not the dark theme\'s white');
    expect(field.style.fontSize, 16);
    expect(field.style.fontWeight, FontWeight.w700);
    expect(field.style.letterSpacing, -0.2);
    expect(field.style.fontFamily, 'JetBrainsMono');
  });

  testWidgets('a field whose modifier sets no text style keeps the theme\'s', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: DVText('').modifier(DVModifier().input(label: 'Name', onChanged: (_) {}))),
    ));
    final BuildContext context = tester.element(find.byType(TextField));
    final EditableText field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.style.color, Theme.of(context).textTheme.bodyLarge?.color);
    expect(field.style.fontSize, Theme.of(context).textTheme.bodyLarge?.fontSize);
  });
}
