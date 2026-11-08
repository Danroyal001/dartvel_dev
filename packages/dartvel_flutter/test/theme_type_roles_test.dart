import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle drawnStyle(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan).style!;

void main() {
  tearDown(() => DV.Theme.useTokens(DVThemeTokens.dartvel));

  test('type roles are modifiers carrying the role\'s size, weight and line height', () {
    expect(DVText.body.fontSizeValue, 17);
    expect(DVText.body.lineHeightValue, 1.6);
    expect(DVText.heading1.fontSizeValue, 30);
    expect(DVText.heading1.fontWeightValue, FontWeight.w700);
    expect(DVText.caption.fontSizeValue, 14);
    expect(<double?>[
      DVText.display.fontSizeValue,
      DVText.heading2.fontSizeValue,
      DVText.heading3.fontSizeValue,
      DVText.small.fontSizeValue,
      DVText.label.fontSizeValue,
    ], <double>[50, 24, 20, 15, 12]);
  });

  testWidgets('a role draws in the theme\'s face and chains like any modifier', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: dartvelDefaultTheme(.dark),
      themeMode: .dark,
      home: Scaffold(body: DVText('caption', DVText.caption.color(DVColor.muted))),
    ));
    final TextStyle style = drawnStyle(tester, 'caption');
    expect(style.fontSize, 14);
    expect(style.fontFamily, 'packages/dartvel_flutter/Manrope');
    expect(style.color!.toARGB32(), 0xFF9AA7BD);
  });

  test('a role follows the token set', () {
    DV.Theme.useTokens(DVThemeTokens.dartvel.override(
      text: const <String, DVTextRole>{'body': DVTextRole(size: 16, family: 'Inter')},
    ));
    expect(DVText.body.fontSizeValue, 16);
    expect(DVText.body.fontFamilyValue, 'Inter');
  });
}
