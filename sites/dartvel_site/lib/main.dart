import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main() {
  runApp(createDartvelApp());
}

/// The site, in whichever appearance the visitor already prefers.
///
/// `ThemeMode.system` rather than a stored choice: a visitor who has set their
/// machine to dark has already answered the question, and handing them white
/// is the site overriding an answer it was given.
Widget createDartvelApp() => MaterialApp.router(
      title: 'Dartvel — Flutter, full stack',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: dartvelSiteTheme(Brightness.light),
      darkTheme: dartvelSiteTheme(Brightness.dark),
      scrollBehavior: const DartvelSiteScrollBehavior(),
      routerConfig: createDartvelRouter(),
    );

/// A scrollbar on every scrollable, for every input.
///
/// Flutter's Material behaviour draws one for a mouse or a trackpad and none
/// for touch, which on the web means a tablet gets no indication of how long a
/// page is. The docs page is nine sections; without a thumb it looks the same
/// near the top as near the bottom.
///
/// Overridden rather than configured because the platform switch is inside
/// `buildScrollbar` and there is no flag for "also touch". The theme handles
/// the other half — see [dartvelSiteTheme] — since a scrollbar that exists and
/// fades after a second is barely better than none.
class DartvelSiteScrollBehavior extends MaterialScrollBehavior {
  const DartvelSiteScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      Scrollbar(controller: details.controller, child: child);
}

/// The theme every page is given.
///
/// Public so a test can read what the pages actually get rather than asserting
/// against a copy of it.
ThemeData dartvelSiteTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0A0D13) : const Color(0xFFFFFFFF),
    colorScheme: ColorScheme.fromSeed(
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
