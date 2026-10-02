import 'package:flutter/material.dart';

/// The default application theme, shared by new projects and standalone Studio.
ThemeData dartvelDefaultTheme(
  Brightness brightness, {
  String? fontPackage = 'dartvel_flutter',
}) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // The site's face, everywhere except code. Without it every page
    // renders in Roboto, which is Flutter's default and reads as nobody
    // having made a decision. Set on the theme rather than on each widget
    // so a page that styles nothing still gets it.
    fontFamily: 'Manrope',
    package: fontPackage,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0A0D13)
        : const Color(0xFFFFFFFF),
    colorScheme: ColorScheme.fromSeed(
      // Seeded from the site's own accent, so Material's generated roles
      // land in the same family as the palette the pages actually use.
      // It used to be seeded from a blue nobody picked, which is where
      // every cool grey on the site came from.
      seedColor: const Color(0xFF2F6BFF),
      brightness: brightness,
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
        dark ? const Color(0xFF222A38) : const Color(0xFFE3E7EF),
      ),
    ),
  );
}
