import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Color? scrollbar(WidgetStateProperty<Color?>? property) => property?.resolve(<WidgetState>{});

void main() {
  tearDown(() => DV.Theme.useTokens(DVThemeTokens.dartvel));

  // What the default theme resolved to before tokens fed it, written out so a
  // token default that drifts is a visible change rather than a quiet one.
  for (final Brightness brightness in Brightness.values) {
    test('the default theme is unchanged in ${brightness.name}', () {
      final bool dark = brightness == .dark;
      final ThemeData theme = dartvelDefaultTheme(brightness);
      expect(theme.colorScheme, ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF), brightness: brightness));
      expect(theme.scaffoldBackgroundColor.toARGB32(), dark ? 0xFF0A0D13 : 0xFFFFFFFF);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'packages/dartvel_flutter/Manrope');
      expect(scrollbar(theme.scrollbarTheme.thumbColor)!.toARGB32(), dark ? 0xFF39435A : 0xFFC2C9D8);
      expect(scrollbar(theme.scrollbarTheme.trackColor)!.toARGB32(), dark ? 0xFF161B25 : 0xFFF1F3F8);
      expect(scrollbar(theme.scrollbarTheme.trackBorderColor)!.toARGB32(), dark ? 0xFF222A38 : 0xFFE3E7EF);
    });
  }

  test('the default theme is built from the token set', () {
    DV.Theme.useTokens(DVThemeTokens.dartvel.override(
      color: <String, DVColorToken>{
        'surface': DVColorToken('surface', light: const Color(0xFFFAFAF7), dark: const Color(0xFF101114)),
        'accent': DVColorToken('accent', light: const Color(0xFF00875A), dark: const Color(0xFF57D9A3)),
        'danger': DVColorToken('danger', light: const Color(0xFFC9372C), dark: const Color(0xFFFF8F73)),
        'outline': DVColorToken('outline', light: const Color(0xFFDDDDDD), dark: const Color(0xFF333333)),
      },
      text: const <String, DVTextRole>{'body': DVTextRole(size: 17, lineHeight: 1.6, family: 'Inter')},
    ));
    final ThemeData dark = dartvelDefaultTheme(.dark, fontPackage: null);
    expect(dark.scaffoldBackgroundColor.toARGB32(), 0xFF101114);
    expect(dark.colorScheme.primary, ColorScheme.fromSeed(seedColor: const Color(0xFF00875A), brightness: .dark).primary);
    expect(dark.colorScheme.error.toARGB32(), 0xFFFF8F73);
    expect(scrollbar(dark.scrollbarTheme.trackBorderColor)!.toARGB32(), 0xFF333333);
    expect(dark.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(dartvelDefaultTheme(.light).scaffoldBackgroundColor.toARGB32(), 0xFFFAFAF7);
  });
}
