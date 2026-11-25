import 'package:dartvel_core/dartvel.dart' show DVColorPair, DVColorRole, DVThemeConfig;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `dartvel.theme` reaches everything the framework draws: Material's roles,
/// Dartvel's own focus ring, the selection, the page, and `DV.Theme` at run
/// time. Nothing declared is dartvel.dev's theme, unchanged.
void main() {
  const Color brick = Color(0xFFB83A12);
  const DVThemeConfig chop = DVThemeConfig(
    seed: '#B83A12',
    colors: <DVColorRole, DVColorPair>{
      DVColorRole.background: DVColorPair(light: '#FAF7F2', dark: '#141210'),
      DVColorRole.accent: DVColorPair(light: '#B83A12', dark: '#FF8A5C'),
      DVColorRole.text: DVColorPair(light: '#1C1917', dark: '#F3EEE8'),
      DVColorRole.focus: DVColorPair(light: '#1C1917', dark: '#F3EEE8'),
      DVColorRole.selection: DVColorPair(light: '#B83A1240', dark: '#FF8A5C55'),
    },
  );

  tearDown(() => const DVTheme().configure(DVThemeConfig.dartvel));

  test('nothing declared is Dartvel\'s own theme, exactly as before', () {
    for (final Brightness brightness in Brightness.values) {
      final ThemeData theme = dartvelDefaultTheme(brightness);
      final ColorScheme expected = ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF), brightness: brightness);
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.surface, expected.surface);
      expect(theme.scaffoldBackgroundColor,
          brightness == .dark ? const Color(0xFF0A0D13) : const Color(0xFFFFFFFF));
      expect(theme.textSelectionTheme.selectionColor, isNull);
      expect(theme.extension<DVThemeColors>()!.focus, const Color(0xFF1D4ED8));
    }
  });

  test('a seed is the light accent exactly, and a readable tone of it in dark', () {
    const DVThemeConfig seedOnly = DVThemeConfig(seed: '#B83A12');
    final ThemeData light = dvThemeData(.light, seedOnly);
    final ThemeData dark = dvThemeData(.dark, seedOnly);
    expect(light.colorScheme.primary, brick);
    expect(light.colorScheme.onPrimary, const Color(0xFFFFFFFF));
    expect(dark.colorScheme.primary, isNot(brick));
    expect(dark.colorScheme.primary.computeLuminance(), greaterThan(brick.computeLuminance()));
    // Nothing of Dartvel's blue is left in the derived roles.
    final ColorScheme blue = ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF));
    expect(light.colorScheme.secondary, isNot(blue.secondary));
    expect(light.extension<DVThemeColors>()!.focus, brick);
    expect(light.extension<DVThemeColors>()!.link, brick);
  });

  test('named roles are used as written, per mode', () {
    for (final Brightness brightness in Brightness.values) {
      final bool dark = brightness == .dark;
      final ThemeData theme = dvThemeData(brightness, chop);
      final DVThemeColors colours = theme.extension<DVThemeColors>()!;
      expect(theme.scaffoldBackgroundColor, dark ? const Color(0xFF141210) : const Color(0xFFFAF7F2));
      expect(theme.colorScheme.primary, dark ? const Color(0xFFFF8A5C) : brick);
      expect(theme.textTheme.bodyMedium!.color, dark ? const Color(0xFFF3EEE8) : const Color(0xFF1C1917));
      expect(theme.textSelectionTheme.selectionColor, dark ? const Color(0x55FF8A5C) : const Color(0x40B83A12));
      expect(theme.textSelectionTheme.cursorColor, theme.colorScheme.primary);
      expect(colours.focus, dark ? const Color(0xFFF3EEE8) : const Color(0xFF1C1917));
      expect(theme.focusColor.a, closeTo(0.16, 0.01));
      // The font and the always-visible scrollbars are kept.
      expect(theme.textTheme.bodyMedium!.fontFamily, contains('Manrope'));
      expect(theme.scrollbarTheme.thumbVisibility?.resolve(<WidgetState>{}), isTrue);
    }
  });

  testWidgets('DV.Theme.configure and setMode redraw the application in place', (WidgetTester tester) async {
    await tester.pumpWidget(DVAppTheme(
      builder: (BuildContext context, ThemeData light, ThemeData dark, ThemeMode mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: Builder(
          builder: (BuildContext context) =>
              Text('${DV.Theme.colors(context).accent.toARGB32()}', textDirection: .ltr),
        ),
      ),
    ));
    final int blue = dartvelDefaultTheme(.light).colorScheme.primary.toARGB32();
    expect(find.text('$blue'), findsOneWidget);

    DV.Theme.configure(chop);
    await tester.pumpAndSettle();
    expect(find.text('${brick.toARGB32()}'), findsOneWidget);

    DV.Theme.setMode(.dark);
    await tester.pumpAndSettle();
    expect(find.text('${const Color(0xFFFF8A5C).toARGB32()}'), findsOneWidget);
  });

  testWidgets('the focus ring on a tappable box is the theme\'s focus colour, not a fixed blue',
      (WidgetTester tester) async {
    Future<Color?> ringWith(DVThemeConfig config) async {
      await tester.pumpWidget(MaterialApp(
        theme: dvThemeData(.light, config),
        home: Scaffold(
          body: DVBox(DVText('Save').modifier(DVModifier().onTap(() {}))),
        ),
      ));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final Object? decoration =
          tester.widget<Container>(find.byKey(const ValueKey<String>('dv-control:Save'))).foregroundDecoration;
      return decoration is BoxDecoration ? (decoration.border as Border?)?.top.color : null;
    }

    expect(await ringWith(chop), const Color(0xFF1C1917));
    expect(await ringWith(DVThemeConfig.dartvel), const Color(0xFF1D4ED8));
  });
}
