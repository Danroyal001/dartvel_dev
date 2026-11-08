import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget inMode(ThemeMode mode, Widget child, {bool highContrast = false}) => MaterialApp(
      theme: ThemeData(brightness: .light),
      darkTheme: ThemeData(brightness: .dark),
      themeMode: mode,
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: Scaffold(body: child),
        ),
      ),
    );

BoxDecoration decorationOf(WidgetTester tester) =>
    tester.widget<Container>(find.descendant(of: find.byKey(const Key('box')), matching: find.byType(Container)).first).decoration! as BoxDecoration;

Color? drawnColor(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan).style?.color;

void main() {
  testWidgets('a DVBox paints a colour token in the mode it is drawn in', (WidgetTester tester) async {
    final Widget box = KeyedSubtree(key: const Key('box'), child: DVBox(const SizedBox(width: 10, height: 10), DVModifier().backgroundColor(DVColor.surface)));
    await tester.pumpWidget(inMode(.light, box));
    expect(decorationOf(tester).color!.toARGB32(), 0xFFFFFFFF);
    await tester.pumpWidget(inMode(.dark, box));
    await tester.pumpAndSettle(); // the theme animates between modes
    expect(decorationOf(tester).color!.toARGB32(), 0xFF0A0D13);
  });

  testWidgets('high contrast picks the token\'s high-contrast value', (WidgetTester tester) async {
    final DVColorToken ground = DVColorToken('surface',
        light: const Color(0xFFFFFFFF), dark: const Color(0xFF101114), highContrast: const Color(0xFF000000));
    await tester.pumpWidget(inMode(.light,
        KeyedSubtree(key: const Key('box'), child: DVBox(const SizedBox(width: 10, height: 10), DVModifier().backgroundColor(ground))),
        highContrast: true));
    expect(decorationOf(tester).color!.toARGB32(), 0xFF000000);
  });

  testWidgets('borders and elevation shadows resolve too', (WidgetTester tester) async {
    final Widget box = KeyedSubtree(key: const Key('box'), child: DVBox(
      const SizedBox(width: 10, height: 10),
      DVModifier().border(Border.all(color: DVColor.outline)).shadow(DVElevation.raised),
    ));
    await tester.pumpWidget(inMode(.dark, box));
    final BoxDecoration decoration = decorationOf(tester);
    expect((decoration.border! as Border).top.color.toARGB32(), 0xFF222A38);
    expect(decoration.boxShadow!.single.color.toARGB32(), 0x66000000);
  });

  testWidgets('DVText draws a colour token in the mode it is drawn in', (WidgetTester tester) async {
    await tester.pumpWidget(inMode(.dark, DVText('hello', DVModifier().color(DVColor.onSurface))));
    expect(drawnColor(tester, 'hello')!.toARGB32(), 0xFFF2F5FA);
  });

  test('animate takes a motion token\'s curve when none is named', () {
    expect(DVModifier().animate(DVMotion.slow).animateCurve, Curves.easeInOut);
    expect(DVModifier().animate(DVMotion.slow, curve: Curves.linear).animateCurve, Curves.linear);
    expect(DVModifier().animate(const Duration(milliseconds: 100)).animateCurve, Curves.easeOut);
  });

  test('modifiers take space and radius tokens as the numbers they are', () {
    final DVModifier modifier = DVModifier().padding(DVSpace.md).rounded(DVRadius.md);
    expect(modifier.paddingValue, const EdgeInsets.all(16));
    expect(modifier.borderRadius, BorderRadius.circular(10));
  });
}
