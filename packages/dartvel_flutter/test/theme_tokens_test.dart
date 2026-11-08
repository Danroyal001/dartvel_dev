import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DV.Theme.useTokens(DVThemeTokens.dartvel));

  group('the default vocabulary is dartvel.dev\'s', () {
    test('colour tokens carry a value per mode', () {
      expect(DVColor.surface.resolve(.light), const Color(0xFFFFFFFF));
      expect(DVColor.surface.resolve(.dark), const Color(0xFF0A0D13));
      expect(DVColor.onSurface.resolve(.light), const Color(0xFF0B1020));
      expect(DVColor.onSurface.resolve(.dark), const Color(0xFFF2F5FA));
      expect(DVColor.accent.resolve(.light), const Color(0xFF2F6BFF));
      expect(DVColor.accent.resolve(.dark), const Color(0xFF7BA2FF));
      expect(DVColor.raised.resolve(.dark), const Color(0xFF11161F));
      expect(DVColor.muted.resolve(.light), const Color(0xFF5A6478));
      expect(DVColor.outline.resolve(.dark), const Color(0xFF222A38));
      expect(DVColor.danger.resolve(.light), const Color(0xFFBA1A1A));
      expect(DVColor.danger.resolve(.dark), const Color(0xFFFFB4AB));
    });

    test('an unresolved token is its light value, so a raw Flutter widget is never transparent', () {
      final Color asColor = DVColor.surface;
      expect(asColor.toARGB32(), 0xFFFFFFFF);
    });

    test('space, radius, motion and elevation have their scales', () {
      expect(<double>[DVSpace.xs, DVSpace.sm, DVSpace.md, DVSpace.lg, DVSpace.xl], <double>[4, 8, 16, 24, 32]);
      expect(<double>[DVRadius.sm, DVRadius.md, DVRadius.lg, DVRadius.full], <double>[6, 10, 12, 999]);
      expect(DVMotion.standard, const Duration(milliseconds: 180));
      expect(DVMotion.standard.curve, Curves.easeOut);
      expect(DVMotion.quick, const Duration(milliseconds: 140));
      expect(DVMotion.slow, const Duration(milliseconds: 420));
      expect(DVElevation.flat, isEmpty);
      final BoxShadow raised = DVElevation.raised.single;
      expect(raised.blurRadius, 22);
      expect(raised.offset, const Offset(0, 8));
      final DVColorToken shade = raised.color as DVColorToken;
      expect(shade.resolve(.light).a, closeTo(0.09, 0.005));
      expect(shade.resolve(.dark).a, closeTo(0.40, 0.005));
    });
  });

  group('high contrast', () {
    test('a token that declares it resolves to it in either brightness', () {
      final DVColorToken surface = DVColorToken(
        'surface',
        light: const Color(0xFFFFFFFF),
        dark: const Color(0xFF101114),
        highContrast: const Color(0xFF000000),
      );
      expect(surface.resolve(.light, highContrast: true), const Color(0xFF000000));
      expect(surface.resolve(.dark, highContrast: true), const Color(0xFF000000));
      expect(surface.resolve(.dark), const Color(0xFF101114));
    });

    test('a token that does not falls back to its brightness value', () {
      expect(DVColor.accent.resolve(.dark, highContrast: true), const Color(0xFF7BA2FF));
    });
  });

  test('a token made translucent keeps a value per mode', () {
    final DVColorToken faded = DVColor.accent.withValues(alpha: 0.5);
    expect(faded.resolve(.dark), const Color(0xFF7BA2FF).withValues(alpha: 0.5));
    expect(faded.resolve(.light), const Color(0xFF2F6BFF).withValues(alpha: 0.5));
  });

  test('two tokens equal in light and different in dark are different colours', () {
    final DVColorToken one = DVColorToken('a', light: const Color(0xFFFFFFFF), dark: const Color(0xFF000000));
    final DVColorToken two = DVColorToken('a', light: const Color(0xFFFFFFFF), dark: const Color(0xFF111111));
    expect(one == two, isFalse);
  });

  test('DV.Theme.useTokens replaces only the tokens it names', () {
    DV.Theme.useTokens(DVThemeTokens.dartvel.override(
      color: <String, DVColorToken>{
        'accent': DVColorToken('accent', light: const Color(0xFF00AA55), dark: const Color(0xFF33CC77)),
      },
      space: <String, double>{'md': 20},
    ));
    expect(DVColor.accent.resolve(.dark), const Color(0xFF33CC77));
    expect(DVSpace.md, 20);
    expect(DVSpace.sm, 8);
    expect(DVColor.surface.resolve(.dark), const Color(0xFF0A0D13));
    expect(DV.Theme.tokens.space['md'], 20);
  });

  test('a token name the vocabulary does not have is refused, naming it', () {
    expect(
      () => DVThemeTokens.dartvel.override(space: <String, double>{'huge': 80}),
      throwsA(isA<ArgumentError>().having((ArgumentError error) => '${error.message}', 'message', contains('huge'))),
    );
  });
}
