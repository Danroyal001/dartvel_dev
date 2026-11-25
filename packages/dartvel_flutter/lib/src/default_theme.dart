import 'package:dartvel_core/dartvel.dart' show DVColorRole, DVThemeConfig;
import 'package:flutter/material.dart';

/// The default application theme, shared by new projects and standalone
/// Studio: [dvThemeData] with nothing declared, which is dartvel.dev's.
ThemeData dartvelDefaultTheme(
  Brightness brightness, {
  String? fontPackage = 'dartvel_flutter',
}) =>
    dvThemeData(brightness, DVThemeConfig.dartvel, fontPackage: fontPackage);

/// The application's theme for one appearance, built from `dartvel.theme`
/// ([config]).
///
/// With nothing declared it is Dartvel's own theme, unchanged. A declared
/// seed becomes the light accent exactly and seeds every role not named; a
/// named role is used as written. What Material draws (buttons, fields,
/// switches, progress) reads the colour scheme; what Dartvel draws (focus
/// rings, links, the selection, Studio) reads [DVThemeColors], carried on
/// the theme as an extension so both come from the same place.
ThemeData dvThemeData(
  Brightness brightness,
  DVThemeConfig config, {
  String? fontPackage = 'dartvel_flutter',
}) {
  final bool dark = brightness == Brightness.dark;
  final Color seed = Color(DVThemeConfig.argb(config.seed ?? DVThemeConfig.dartvelSeed));
  final ColorScheme derived = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  Color? named(DVColorRole role) {
    final String? hex = config.declared(role, dark: dark);
    return hex == null ? null : Color(DVThemeConfig.argb(hex));
  }

  final Color background = named(DVColorRole.background) ??
      (dark ? const Color(0xFF0A0D13) : const Color(0xFFFFFFFF));
  // The seed is the brand colour: exactly that in light mode. In dark mode
  // Material's lighter tone of it, which reads on a dark page, unless the
  // project named a dark accent.
  final Color? namedAccent = named(DVColorRole.accent) ?? (!dark && config.seed != null ? seed : null);
  final Color accent = namedAccent ?? derived.primary;
  final Color onAccent = named(DVColorRole.onAccent) ?? (namedAccent == null ? derived.onPrimary : dvReadableOn(accent));
  final ColorScheme scheme = !config.declaresColours
      ? derived
      : derived.copyWith(
          primary: accent,
          onPrimary: onAccent,
          surface: named(DVColorRole.surface),
          onSurface: named(DVColorRole.onSurface),
          onSurfaceVariant: named(DVColorRole.mutedText),
          outline: named(DVColorRole.outline),
          error: named(DVColorRole.danger),
          onError: named(DVColorRole.onDanger),
        );
  final Color? text = named(DVColorRole.text);
  final Color? namedFocus = named(DVColorRole.focus);
  final Color? namedSelection = named(DVColorRole.selection);
  final DVThemeColors colours = DVThemeColors(
    accent: accent,
    onAccent: onAccent,
    background: background,
    text: text ?? scheme.onSurface,
    surface: scheme.surface,
    onSurface: scheme.onSurface,
    mutedText: scheme.onSurfaceVariant,
    outline: scheme.outline,
    danger: scheme.error,
    onDanger: scheme.onError,
    link: named(DVColorRole.link) ?? accent,
    // Dartvel's own ring until the project names a colour; then its accent.
    focus: namedFocus ??
        (config.declaresColours ? accent : Color(DVThemeConfig.argb(DVThemeConfig.dartvelFocus))),
    selection: namedSelection ?? accent.withValues(alpha: 0.3),
  );
  final ThemeData base = _dartvelThemeData(
    brightness,
    scheme: scheme,
    background: background,
    fontPackage: fontPackage,
  ).copyWith(extensions: <ThemeExtension<dynamic>>[colours]);
  if (!config.declaresColours) return base;
  return base.copyWith(
    canvasColor: background,
    // A fill behind a focused link or row: the ring's colour, light enough
    // to keep the words readable on it.
    focusColor: colours.focus.withValues(alpha: 0.16),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: colours.selection,
      selectionHandleColor: accent,
    ),
    textTheme: text == null ? null : base.textTheme.apply(bodyColor: text, displayColor: text),
  );
}

/// White or near-black, whichever reads better on [background].
Color dvReadableOn(Color background) {
  final double light = background.computeLuminance();
  final double onWhite = 1.05 / (light + 0.05);
  final double onInk = (light + 0.05) / (const Color(0xFF111111).computeLuminance() + 0.05);
  return onWhite >= onInk ? const Color(0xFFFFFFFF) : const Color(0xFF111111);
}

/// The application's colours by what they are for, as Dartvel draws them:
/// `dartvel.theme` resolved for one appearance. Read it with
/// `DV.Theme.colors(context)`.
@immutable
class DVThemeColors extends ThemeExtension<DVThemeColors> {
  const DVThemeColors({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.text,
    required this.surface,
    required this.onSurface,
    required this.mutedText,
    required this.outline,
    required this.danger,
    required this.onDanger,
    required this.link,
    required this.focus,
    required this.selection,
  });

  /// The colours a theme Dartvel did not build implies: an application's own
  /// `ThemeData` in an `@DVAppRoot`, or no theme at all.
  factory DVThemeColors.fromTheme(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    return DVThemeColors(
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      background: theme.scaffoldBackgroundColor,
      text: theme.textTheme.bodyMedium?.color ?? scheme.onSurface,
      surface: scheme.surface,
      onSurface: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      outline: scheme.outline,
      danger: scheme.error,
      onDanger: scheme.onError,
      link: scheme.primary,
      focus: Color(DVThemeConfig.argb(DVThemeConfig.dartvelFocus)),
      selection: theme.textSelectionTheme.selectionColor ?? scheme.primary.withValues(alpha: 0.3),
    );
  }

  final Color accent;
  final Color onAccent;
  final Color background;
  final Color text;
  final Color surface;
  final Color onSurface;
  final Color mutedText;
  final Color outline;
  final Color danger;
  final Color onDanger;
  final Color link;
  final Color focus;
  final Color selection;

  @override
  DVThemeColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? text,
    Color? surface,
    Color? onSurface,
    Color? mutedText,
    Color? outline,
    Color? danger,
    Color? onDanger,
    Color? link,
    Color? focus,
    Color? selection,
  }) =>
      DVThemeColors(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        background: background ?? this.background,
        text: text ?? this.text,
        surface: surface ?? this.surface,
        onSurface: onSurface ?? this.onSurface,
        mutedText: mutedText ?? this.mutedText,
        outline: outline ?? this.outline,
        danger: danger ?? this.danger,
        onDanger: onDanger ?? this.onDanger,
        link: link ?? this.link,
        focus: focus ?? this.focus,
        selection: selection ?? this.selection,
      );

  @override
  DVThemeColors lerp(covariant DVThemeColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return DVThemeColors(
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      background: mix(background, other.background),
      text: mix(text, other.text),
      surface: mix(surface, other.surface),
      onSurface: mix(onSurface, other.onSurface),
      mutedText: mix(mutedText, other.mutedText),
      outline: mix(outline, other.outline),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      link: mix(link, other.link),
      focus: mix(focus, other.focus),
      selection: mix(selection, other.selection),
    );
  }
}

ThemeData _dartvelThemeData(
  Brightness brightness, {
  required ColorScheme scheme,
  required Color background,
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
    //
    // Named by its asset path rather than with `package:`. A theme's package
    // is inherited by every TextStyle merged into it, so a widget that names
    // an installed font (`DV.Platform.fonts`) asked for
    // "packages/dartvel_flutter/<that font>", which does not exist, and was
    // drawn in Manrope instead.
    fontFamily: fontPackage == null ? 'Manrope' : 'packages/$fontPackage/Manrope',
    scaffoldBackgroundColor: background,
    // Seeded from the application's accent (dartvel.dev's blue by
    // default), so Material's generated roles land in the same family as
    // the palette the pages actually use.
    colorScheme: scheme,
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
