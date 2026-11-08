import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';

/// A colour with a value per mode: light, dark and, where the token declares
/// one, high contrast.
///
/// It is a [Color], so every modifier that takes a colour takes a token, and
/// used unresolved -- handed straight to a Flutter widget -- it is its light
/// value rather than a transparent pixel. `DVBox` and `DVText` resolve it
/// against the mode they are drawn in; anything else asks with [of].
class DVColorToken extends Color {
  DVColorToken(
    this.name, {
    required this.light,
    required this.dark,
    this.highContrast,
  }) : super.from(
          alpha: light.a,
          red: light.r,
          green: light.g,
          blue: light.b,
          colorSpace: light.colorSpace,
        );

  /// The name the token is declared under, which every diagnostic about it
  /// names.
  final String name;
  final Color light;
  final Color dark;

  /// The value when the platform asks for more contrast, in either
  /// brightness. Optional: a token without one keeps its brightness value.
  final Color? highContrast;

  /// This token's value for [brightness], or for high contrast when the
  /// reader has asked for it and the token declares a value for it.
  Color resolve(Brightness brightness, {bool highContrast = false}) {
    final Color? contrast = this.highContrast;
    if (highContrast && contrast != null) return contrast;
    return brightness == Brightness.dark ? dark : light;
  }

  /// This token's value where [context] is drawn: the theme's brightness and
  /// the platform's high-contrast setting. Depends on both, so a widget that
  /// asks rebuilds when either changes.
  Color of(BuildContext context) => resolve(
        Theme.of(context).brightness,
        highContrast: MediaQuery.maybeHighContrastOf(context) ?? false,
      );

  DVColorToken _map(Color Function(Color value) change) => DVColorToken(
        name,
        light: change(light),
        dark: change(dark),
        highContrast: highContrast == null ? null : change(highContrast!),
      );

  /// Changed in every mode, so a translucent accent is still the dark
  /// accent in dark.
  @override
  DVColorToken withValues({
    double? alpha,
    double? red,
    double? green,
    double? blue,
    ColorSpace? colorSpace,
  }) =>
      _map((Color value) => value.withValues(
            alpha: alpha,
            red: red,
            green: green,
            blue: blue,
            colorSpace: colorSpace,
          ));

  @override
  DVColorToken withAlpha(int a) => _map((Color value) => value.withAlpha(a));

  @override
  bool operator ==(Object other) =>
      other is DVColorToken &&
      other.name == name &&
      other.light == light &&
      other.dark == dark &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(name, light, dark, highContrast);

  @override
  String toString() => 'DVColorToken($name, light: $light, dark: $dark'
      '${highContrast == null ? '' : ', highContrast: $highContrast'})';
}

/// A colour [color] resolved where [context] is drawn when it is a token,
/// and unchanged when it is not.
Color dvResolveColor(BuildContext context, Color color) =>
    color is DVColorToken ? color.of(context) : color;

/// A duration that carries the curve it is meant to be run on, so
/// `.animate(DVMotion.standard)` needs no second argument.
class DVMotionToken extends Duration {
  const DVMotionToken(this.name, {required int milliseconds, required this.curve})
      : super(milliseconds: milliseconds);

  final String name;
  final Curve curve;
}

/// A type role: what a piece of text is, rather than how big it is.
///
/// The family is left to the theme unless the role names one, so a role
/// inherits the application's face the way unstyled text does.
class DVTextRole {
  const DVTextRole({
    required this.size,
    this.weight = FontWeight.w400,
    this.lineHeight,
    this.letterSpacing,
    this.family,
  });

  final double size;
  final FontWeight weight;
  final double? lineHeight;
  final double? letterSpacing;
  final String? family;
}

/// The whole vocabulary an application's styling names: colour, type,
/// spacing, radius, elevation and motion.
///
/// The names are fixed and the values are not. [dartvel] is the set every
/// new project starts from, which is dartvel.dev's; the application's
/// `dartvel.theme.tokens` in pubspec.yaml overrides values through
/// [override], and so would a tenant.
class DVThemeTokens {
  const DVThemeTokens({
    required this.color,
    required this.space,
    required this.radius,
    required this.elevation,
    required this.motion,
    required this.text,
  });

  final Map<String, DVColorToken> color;
  final Map<String, double> space;
  final Map<String, double> radius;
  final Map<String, List<BoxShadow>> elevation;
  final Map<String, DVMotionToken> motion;
  final Map<String, DVTextRole> text;

  /// dartvel.dev's own palette, type scale, radii and motion, which every
  /// project has until it says otherwise.
  static final DVThemeTokens dartvel = DVThemeTokens(
    color: <String, DVColorToken>{
      // The page ground. Also the default theme's scaffold background.
      'surface': DVColorToken('surface', light: const Color(0xFFFFFFFF), dark: const Color(0xFF0A0D13)),
      // A card, a panel, an inset: one step off the page.
      'raised': DVColorToken('raised', light: const Color(0xFFF4F6FB), dark: const Color(0xFF11161F)),
      'onSurface': DVColorToken('onSurface', light: const Color(0xFF0B1020), dark: const Color(0xFFF2F5FA)),
      'muted': DVColorToken('muted', light: const Color(0xFF5A6478), dark: const Color(0xFF9AA7BD)),
      'outline': DVColorToken('outline', light: const Color(0xFFE3E7EF), dark: const Color(0xFF222A38)),
      'accent': DVColorToken('accent', light: const Color(0xFF2F6BFF), dark: const Color(0xFF7BA2FF)),
      // Dark text on the dark-mode accent: white on #7BA2FF is under 3:1.
      'onAccent': DVColorToken('onAccent', light: const Color(0xFFFFFFFF), dark: const Color(0xFF0A0D13)),
      // Material's error tones, which the default theme's scheme already uses.
      'danger': DVColorToken('danger', light: const Color(0xFFBA1A1A), dark: const Color(0xFFFFB4AB)),
      'onDanger': DVColorToken('onDanger', light: const Color(0xFFFFFFFF), dark: const Color(0xFF690005)),
    },
    space: const <String, double>{'xs': 4, 'sm': 8, 'md': 16, 'lg': 24, 'xl': 32},
    radius: const <String, double>{'sm': 6, 'md': 10, 'lg': 12, 'full': 999},
    elevation: <String, List<BoxShadow>>{
      'flat': const <BoxShadow>[],
      'raised': <BoxShadow>[
        BoxShadow(
          color: DVColorToken('elevation.raised',
              light: const Color(0x17000000), dark: const Color(0x66000000)),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
      'overlay': <BoxShadow>[
        BoxShadow(
          color: DVColorToken('elevation.overlay',
              light: const Color(0x24000000), dark: const Color(0x80000000)),
          blurRadius: 32,
          offset: const Offset(0, 14),
        ),
      ],
    },
    motion: const <String, DVMotionToken>{
      'quick': DVMotionToken('quick', milliseconds: 140, curve: Curves.easeOut),
      'standard': DVMotionToken('standard', milliseconds: 180, curve: Curves.easeOut),
      'slow': DVMotionToken('slow', milliseconds: 420, curve: Curves.easeInOut),
    },
    text: const <String, DVTextRole>{
      'display': DVTextRole(size: 50, weight: FontWeight.w700, lineHeight: 1.1, letterSpacing: -1),
      'heading1': DVTextRole(size: 30, weight: FontWeight.w700, lineHeight: 1.2, letterSpacing: -0.5),
      'heading2': DVTextRole(size: 24, weight: FontWeight.w700, lineHeight: 1.25),
      'heading3': DVTextRole(size: 20, weight: FontWeight.w600, lineHeight: 1.3),
      'body': DVTextRole(size: 17, lineHeight: 1.6),
      'small': DVTextRole(size: 15, lineHeight: 1.55),
      'caption': DVTextRole(size: 14, lineHeight: 1.45),
      'label': DVTextRole(size: 12, weight: FontWeight.w600, lineHeight: 1.3, letterSpacing: 0.2),
    },
  );

  /// This set with the named tokens replaced and every other kept.
  ///
  /// A name this set does not have is refused, naming it: the vocabulary is
  /// what styling refers to, and a token nothing can name is a typo that
  /// would otherwise do nothing.
  DVThemeTokens override({
    Map<String, DVColorToken>? color,
    Map<String, double>? space,
    Map<String, double>? radius,
    Map<String, List<BoxShadow>>? elevation,
    Map<String, DVMotionToken>? motion,
    Map<String, DVTextRole>? text,
  }) =>
      DVThemeTokens(
        color: _merged('color', this.color, color),
        space: _merged('space', this.space, space),
        radius: _merged('radius', this.radius, radius),
        elevation: _merged('elevation', this.elevation, elevation),
        motion: _merged('motion', this.motion, motion),
        text: _merged('text', this.text, text),
      );

  static Map<String, V> _merged<V>(String kind, Map<String, V> base, Map<String, V>? changes) {
    if (changes == null || changes.isEmpty) return base;
    for (final String name in changes.keys) {
      if (!base.containsKey(name)) {
        throw ArgumentError.value(
          name,
          kind,
          'There is no $kind token named "$name". The $kind tokens are '
              '${base.keys.join(', ')}.',
        );
      }
    }
    return Map<String, V>.unmodifiable(<String, V>{...base, ...changes});
  }
}

DVThemeTokens _active = DVThemeTokens.dartvel;

/// The token set styling resolves against. Read through `DV.Theme.tokens`.
DVThemeTokens get dvThemeTokens => _active;

/// Replaces the token set. Called through `DV.Theme.useTokens`.
void dvUseThemeTokens(DVThemeTokens tokens) => _active = tokens;

/// Colour tokens. Each is correct in light, dark and high contrast, which a
/// raw colour is in exactly one of.
abstract final class DVColor {
  static DVColorToken get surface => _active.color['surface']!;
  static DVColorToken get raised => _active.color['raised']!;
  static DVColorToken get onSurface => _active.color['onSurface']!;
  static DVColorToken get muted => _active.color['muted']!;
  static DVColorToken get outline => _active.color['outline']!;
  static DVColorToken get accent => _active.color['accent']!;
  static DVColorToken get onAccent => _active.color['onAccent']!;
  static DVColorToken get danger => _active.color['danger']!;
  static DVColorToken get onDanger => _active.color['onDanger']!;
}

/// Spacing tokens, in logical pixels: `.padding(DVSpace.md)`.
abstract final class DVSpace {
  static double get xs => _active.space['xs']!;
  static double get sm => _active.space['sm']!;
  static double get md => _active.space['md']!;
  static double get lg => _active.space['lg']!;
  static double get xl => _active.space['xl']!;
}

/// Corner radius tokens: `.rounded(DVRadius.md)`.
abstract final class DVRadius {
  static double get sm => _active.radius['sm']!;
  static double get md => _active.radius['md']!;
  static double get lg => _active.radius['lg']!;

  /// A pill: not a radius but a shape.
  static double get full => _active.radius['full']!;
}

/// Elevation tokens: `.shadow(DVElevation.raised)`. The shadow's colour is a
/// token, so a shadow is heavier on a dark ground where it would vanish.
abstract final class DVElevation {
  static List<BoxShadow> get flat => _active.elevation['flat']!;
  static List<BoxShadow> get raised => _active.elevation['raised']!;
  static List<BoxShadow> get overlay => _active.elevation['overlay']!;
}

/// Motion tokens: `.animate(DVMotion.standard)`. Reduced motion still turns
/// every one of them off.
abstract final class DVMotion {
  static DVMotionToken get quick => _active.motion['quick']!;
  static DVMotionToken get standard => _active.motion['standard']!;
  static DVMotionToken get slow => _active.motion['slow']!;
}
