import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary apps expose no Telegram platform', () {
    expect(DV.Platform.telegram, isNull);
  });
  test('Telegram colors override app roles without discarding typography', () {
    final base = ThemeData(brightness: .dark, fontFamily: 'Manrope');
    final theme = dvTelegramTheme(
      base,
      const DVTelegramTheme(
        dark: true,
        params: {
          'bg_color': '#102030',
          'text_color': '#fafafa',
          'button_color': '#abc123',
          'button_text_color': '#112233',
        },
      ),
    );
    expect(theme.scaffoldBackgroundColor, const Color(0xff102030));
    expect(theme.colorScheme.primary, const Color(0xffabc123));
    expect(theme.colorScheme.onPrimary, const Color(0xff112233));
    expect(
      theme.textTheme.bodyMedium?.fontFamily,
      base.textTheme.bodyMedium?.fontFamily,
    );
    expect(
      dvTelegramTheme(
        base,
        const DVTelegramTheme(dark: false, params: {'bg_color': 'invalid'}),
      ).scaffoldBackgroundColor,
      base.scaffoldBackgroundColor,
    );
  });
}
