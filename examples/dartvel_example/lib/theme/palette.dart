// The shop's colours and type, in one place.
//
// Two palettes with the same names, so a screen asks for `palette.ink` and
// gets the right one for the theme it is drawn in. Warm paper and roast
// brown, with one accent: a shop that sells coffee should look like a bag of
// it, not like a dashboard.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

class const Palette({
  required final Brightness brightness,

  /// Behind everything.
  required final Color canvas,

  /// Cards and sheets.
  required final Color surface,

  /// Wells inside a surface: a quantity stepper, a skeleton.
  required final Color sunken,
  required final Color line,
  required final Color ink,
  required final Color inkMuted,
  required final Color inkFaint,
  required final Color accent,
  required final Color onAccent,

  /// The accent at low strength, for a selected tab or a badge.
  required final Color accentSoft,
  required final Color success,
}) {
  static const Palette light = Palette(
    brightness: Brightness.light,
    canvas: Color(0xFFF7F3EE),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFE8E0),
    line: Color(0xFFE4DBD1),
    ink: Color(0xFF221B17),
    inkMuted: Color(0xFF6A5F57),
    inkFaint: Color(0xFF8F847B),
    accent: Color(0xFF9C4A26),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFF3E1D6),
    success: Color(0xFF3F6B4F),
  );

  static const Palette dark = Palette(
    brightness: Brightness.dark,
    canvas: Color(0xFF161311),
    surface: Color(0xFF211D1A),
    sunken: Color(0xFF2B2622),
    line: Color(0xFF383230),
    ink: Color(0xFFF2ECE6),
    inkMuted: Color(0xFFB3A89F),
    inkFaint: Color(0xFF8A8078),
    accent: Color(0xFFE39A6E),
    onAccent: Color(0xFF2A1408),
    accentSoft: Color(0xFF3A2A21),
    success: Color(0xFF8FC2A0),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// The type scale. Five sizes, used the same way on every screen.
extension PaletteType on Palette {
  /// A screen's name.
  DVModifier get display => const DVModifier()
      .fontSize(30)
      .fontWeight(FontWeight.w700)
      .letterSpacing(-0.6)
      .lineHeight(1.15)
      .color(ink);

  /// A section's name.
  DVModifier get title => const DVModifier()
      .fontSize(19)
      .fontWeight(FontWeight.w600)
      .letterSpacing(-0.2)
      .color(ink);

  /// A card's name.
  DVModifier get headline =>
      const DVModifier().fontSize(16).fontWeight(FontWeight.w600).color(ink);

  DVModifier get body =>
      const DVModifier().fontSize(15).lineHeight(1.45).color(ink);

  DVModifier get muted =>
      const DVModifier().fontSize(14).lineHeight(1.4).color(inkMuted);

  /// Small capitals over a heading: an origin, a status.
  DVModifier get overline => const DVModifier()
      .fontSize(11)
      .fontWeight(FontWeight.w600)
      .letterSpacing(1.2)
      .color(inkMuted);
}

/// Material's themes, made from the palettes, so the controls Dartvel draws
/// with Material -- a form's fields, the navigation bar -- match the rest.
ThemeData shopTheme(Palette p) {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.brightness,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.inkMuted,
        outline: p.line,
        outlineVariant: p.line,
        secondaryContainer: p.accentSoft,
        onSecondaryContainer: p.ink,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    dividerColor: p.line,
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accentSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.ink : p.inkMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.accent : p.inkMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accentSoft,
      selectedIconTheme: IconThemeData(color: p.accent),
      unselectedIconTheme: IconThemeData(color: p.inkMuted),
      selectedLabelTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      unselectedLabelTextStyle: TextStyle(fontSize: 14, color: p.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: p.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.canvas, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
  );
}
