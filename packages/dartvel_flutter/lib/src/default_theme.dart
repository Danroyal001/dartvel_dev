import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// The default application theme, shared by new projects and standalone Studio.
///
/// Built from [tokens], the active token set unless one is given: the page
/// ground is `surface`, the colour scheme is seeded from the light `accent`
/// with `danger` as its error, the scrollbar groove is edged in `outline`,
/// and the face is the `body` role's family when it names one. With
/// dartvel.dev's tokens that is exactly the theme this always was.
ThemeData dartvelDefaultTheme(
  Brightness brightness, {
  String? fontPackage = 'dartvel_flutter',
  DVThemeTokens? tokens,
}) {
  final dark = brightness == Brightness.dark;
  final DVThemeTokens set = tokens ?? dvThemeTokens;
  final DVFontToken? bodyFont = set.fonts['body'];
  final String? bodyFamily = bodyFont?.family ?? set.text['body']?.family;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // The site's face, everywhere except code. Without it every page
    // renders in Roboto, which is Flutter's default and reads as nobody
    // having made a decision. Set on the theme rather than on each widget
    // so a page that styles nothing still gets it.
    //
    // Named by its asset path rather than with `package:`. A theme's package
    // is inherited by every TextStyle merged into it, so a widget that names
    // an installed font (`DV.Platform.fonts`) asked for
    // "packages/dartvel_flutter/<that font>", which does not exist, and was
    // drawn in Manrope instead.
    fontFamily: bodyFamily ??
        (fontPackage == null ? 'Manrope' : 'packages/$fontPackage/Manrope'),
    fontFamilyFallback:
        bodyFont == null || bodyFont.fallback.isEmpty ? null : bodyFont.fallback,
    scaffoldBackgroundColor: set.color['surface']!.resolve(brightness),
    colorScheme: ColorScheme.fromSeed(
      // Seeded from the site's own accent, so Material's generated roles
      // land in the same family as the palette the pages actually use.
      // It used to be seeded from a blue nobody picked, which is where
      // every cool grey on the site came from.
      //
      // The light accent, in both modes: the seed is a hue, and Material
      // derives each mode's tones from it.
      seedColor: set.color['accent']!.light,
      brightness: brightness,
      error: set.color['danger']!.resolve(brightness),
      onError: set.color['onDanger']!.resolve(brightness),
    ),
    // Always drawn, never faded. thumbVisibility keeps the thumb on screen
    // after the scroll stops; trackVisibility keeps the groove behind it, so
    // the thumb reads as a position in a whole rather than a mark floating at
    // the edge of the page.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStateProperty.all(true),
      trackVisibility: WidgetStateProperty.all(true),
      // Draggable on every platform. Flutter resolves this as
      // `interactive ?? theme.interactive ?? !_useAndroidScrollbar`, and a
      // phone browser reports Android, so without it the thumb was drawn and
      // ignored every touch -- a visible control that does nothing, which
      // reads as a broken page rather than a missing feature.
      interactive: true,
      // Wider while a finger holds it. Ten points is a comfortable mark for a
      // pointer and a thin target for a thumb.
      thickness: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.dragged) ? 14 : 10,
      ),
      radius: const Radius.circular(6),
      // Quiet against both grounds. A scrollbar that is permanently visible is
      // permanently in the corner of somebody's eye, so it is drawn at the
      // weight of a rule rather than of a control.
      thumbColor: WidgetStateProperty.all(
        dark ? const Color(0xFF39435A) : const Color(0xFFC2C9D8),
      ),
      trackColor: WidgetStateProperty.all(
        dark ? const Color(0xFF161B25) : const Color(0xFFF1F3F8),
      ),
      trackBorderColor: WidgetStateProperty.all(
        set.color['outline']!.resolve(brightness),
      ),
    ),
  );
}

/// [theme] with every page's scrollbar always on screen.
///
/// The always-visible defaults used to live only in [dartvelDefaultTheme], so
/// an application that brought its own theme got Flutter's: a thumb that
/// shows while scrolling and fades away. Visibility and dragging are forced;
/// the application's own thickness, radius and colours are kept, and
/// Dartvel's quiet ones fill whatever it did not set.
ThemeData dvWithPageScrollbars(ThemeData theme) {
  final ScrollbarThemeData own = theme.scrollbarTheme;
  final ScrollbarThemeData fallback = dartvelDefaultTheme(theme.brightness, fontPackage: null).scrollbarTheme;
  return theme.copyWith(
    scrollbarTheme: own.copyWith(
      thumbVisibility: WidgetStateProperty.all(true),
      trackVisibility: WidgetStateProperty.all(true),
      interactive: true,
      thickness: own.thickness ?? fallback.thickness,
      radius: own.radius ?? fallback.radius,
      thumbColor: own.thumbColor ?? fallback.thumbColor,
      trackColor: own.trackColor ?? fallback.trackColor,
      trackBorderColor: own.trackBorderColor ?? fallback.trackBorderColor,
    ),
  );
}
