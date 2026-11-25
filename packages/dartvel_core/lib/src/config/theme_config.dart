/// `dartvel.theme`: the application's own colours, light and dark, declared
/// once and used by everything the framework draws.
///
/// ```yaml
/// dartvel:
///   theme:
///     seed: "#B83A12"          # the brand colour; roles not named are derived
///     mode: system             # system | light | dark
///     colors:
///       accent: { light: "#B83A12", dark: "#FF8A5C" }
///       background: { light: "#FAF7F2", dark: "#141210" }
///       focus: "#1C1917"       # one colour for both modes
/// ```
///
/// One declaration, and every place that shows the application's colour
/// reads it: the app's Material theme (buttons, fields, switches, progress),
/// Dartvel's own widgets (focus rings, links, text selection and its
/// handles), Studio, the splash and its loading bar, the server-rendered
/// first screen, the web manifest's `theme_color` and the browser's
/// `theme-color`. A project that declares nothing keeps Dartvel's own theme,
/// the one dartvel.dev uses.
///
/// The same object in a Dart config class is a [DVThemeConfig], and
/// [DVThemeConfig.toPubspec] writes exactly the map above: same keys, same
/// defaults, same validation, so the two spellings are one configuration.
library;

/// Which appearance the application follows.
enum DVThemeMode {
  /// The device's (or browser's) light/dark setting. The default.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// A colour the application names in `dartvel.theme.colors`.
///
/// Each is what a person sees, not a Material slot: [accent] is the colour
/// of buttons, links and the loading bar; [background] is the page behind
/// everything; [text] is the words on it.
enum DVColorRole {
  /// Buttons, switches, the loading bar, the PWA theme colour. Defaults to
  /// the seed.
  accent,

  /// Text and icons on [accent]. Defaults to white or near-black, whichever
  /// reads on it.
  onAccent,

  /// The page behind everything: the scaffold, the splash, the first screen.
  background,

  /// Body text on [background].
  text,

  /// Cards, sheets, menus and fields that sit on the page.
  surface,

  /// Text on [surface].
  onSurface,

  /// Secondary text: hints, captions, metadata.
  mutedText,

  /// Borders and rules.
  outline,

  /// Errors and destructive actions.
  danger,

  /// Text on [danger].
  onDanger,

  /// Links. Defaults to [accent].
  link,

  /// The keyboard focus ring. Defaults to [accent].
  focus,

  /// Selected text's highlight. Defaults to [accent] at 30% opacity.
  selection,
}

/// One colour per appearance, as `#RRGGBB` or `#RRGGBBAA` (CSS order).
class DVColorPair {
  /// A colour for light mode and one for dark mode.
  const DVColorPair({required this.light, required this.dark});

  /// The same colour in both modes.
  const DVColorPair.both(String colour)
      : light = colour,
        dark = colour;

  final String light;
  final String dark;

  /// The colour for one appearance.
  String of({required bool dark}) => dark ? this.dark : light;

  /// A single string when both modes agree, else `{light, dark}`.
  Object toPubspec() => light == dark ? light : <String, Object?>{'light': light, 'dark': dark};

  @override
  bool operator ==(Object other) => other is DVColorPair && other.light == light && other.dark == dark;

  @override
  int get hashCode => Object.hash(light, dark);

  @override
  String toString() => 'DVColorPair($light, $dark)';
}

/// The application's colours: `dartvel.theme` as a Dart value.
class DVThemeConfig {
  const DVThemeConfig({
    this.seed,
    this.mode = DVThemeMode.system,
    this.colors = const <DVColorRole, DVColorPair>{},
  });

  /// Dartvel's own theme, which a project that declares nothing gets: the
  /// one dartvel.dev uses.
  static const DVThemeConfig dartvel = DVThemeConfig();

  /// The seed every role is derived from when the project names none:
  /// dartvel.dev's blue.
  static const String dartvelSeed = '#2F6BFF';

  /// Dartvel's focus ring when the project names no colours at all.
  static const String dartvelFocus = '#1D4ED8';

  /// The brand colour, `#RRGGBB`. The light theme's [DVColorRole.accent] is
  /// exactly this unless `colors.accent` says otherwise; in dark mode a
  /// lighter tone of it is used, so it reads on a dark page. Every role not
  /// named in [colors] is derived from it.
  final String? seed;

  /// Light, dark, or the device's setting.
  final DVThemeMode mode;

  /// Roles named explicitly, per mode.
  final Map<DVColorRole, DVColorPair> colors;

  /// Whether the project declared any colour. A theme that only sets [mode]
  /// keeps Dartvel's colours.
  bool get declaresColours => seed != null || colors.isNotEmpty;

  /// The colour the project named for [role] in one mode, without deriving
  /// anything: null when it named none.
  String? declared(DVColorRole role, {required bool dark}) => colors[role]?.of(dark: dark);

  /// The accent the build can know without Flutter: the declared one, else
  /// the seed in light mode. Null when the project declared neither, so the
  /// caller keeps its own default.
  String? accentHex({required bool dark}) =>
      declared(DVColorRole.accent, dark: dark) ?? (dark ? null : seed);

  /// The link colour the build can know without Flutter: `colors.link`,
  /// else [accentHex].
  String? linkHex({required bool dark}) => declared(DVColorRole.link, dark: dark) ?? accentHex(dark: dark);

  /// The page colour the build can know without Flutter: `colors.background`.
  String? backgroundHex({required bool dark}) => declared(DVColorRole.background, dark: dark);

  /// The `dartvel.theme` object, keys in a fixed order, defaults left out.
  Map<String, Object?> toPubspec() => <String, Object?>{
        if (seed != null) 'seed': seed,
        if (mode != DVThemeMode.system) 'mode': mode.name,
        if (colors.isNotEmpty)
          'colors': <String, Object?>{
            for (final DVColorRole role in DVColorRole.values)
              if (colors[role] != null) role.name: colors[role]!.toPubspec(),
          },
      };

  /// A copy with some settings changed; [colors] are merged role by role.
  DVThemeConfig copyWith({String? seed, DVThemeMode? mode, Map<DVColorRole, DVColorPair>? colors}) =>
      DVThemeConfig(
        seed: seed ?? this.seed,
        mode: mode ?? this.mode,
        colors: colors == null
            ? this.colors
            : Map<DVColorRole, DVColorPair>.unmodifiable(<DVColorRole, DVColorPair>{...this.colors, ...colors}),
      );

  /// `#RGB`, `#RRGGBB` or `#RRGGBBAA` as upper-case `#RRGGBB`/`#RRGGBBAA`,
  /// or null when [value] is none of them.
  static String? normalise(Object? value) {
    if (value is! String) return null;
    final Match? match = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(value.trim());
    if (match == null) return null;
    String digits = match.group(1)!;
    if (digits.length == 3) digits = digits.split('').map((String c) => '$c$c').join();
    return '#${digits.toUpperCase()}';
  }

  /// [hex] (`#RRGGBB` or `#RRGGBBAA`) as a Flutter-style ARGB integer.
  static int argb(String hex) {
    final String digits = hex.substring(1);
    final int rgb = int.parse(digits.substring(0, 6), radix: 16);
    final int alpha = digits.length == 8 ? int.parse(digits.substring(6), radix: 16) : 0xFF;
    return (alpha << 24) | rgb;
  }

  /// [hex] without its alpha: `#RRGGBB`, for places that take no
  /// transparency (a manifest, a meta tag, a splash).
  static String opaque(String hex) => hex.length == 9 ? hex.substring(0, 7) : hex;

  /// Reads the `dartvel.theme` value, as YAML or as the map a Dart config
  /// class wrote. Validation is here and only here, so both spellings are
  /// refused for the same reasons in the same words. A bad entry costs that
  /// entry, never the build.
  static DVThemeConfigReading parse(Object? value) {
    if (value == null) return const DVThemeConfigReading(DVThemeConfig.dartvel);
    if (value is! Map) {
      return const DVThemeConfigReading(DVThemeConfig.dartvel,
          problems: <String>['dartvel.theme must be a map with seed, mode and colors.']);
    }
    final List<String> problems = <String>[];
    for (final Object? key in value.keys) {
      if (!const <String>{'seed', 'mode', 'colors'}.contains(key)) {
        problems.add('dartvel.theme has an unknown key "$key"; the keys are seed, mode and colors.');
      }
    }
    String? seed;
    if (value['seed'] != null) {
      seed = normalise(value['seed']);
      if (seed == null || seed.length != 7) {
        problems.add('dartvel.theme.seed is "${value['seed']}", which is not a #RRGGBB or #RGB colour, so it was not used.');
        seed = null;
      }
    }
    DVThemeMode mode = DVThemeMode.system;
    final Object? rawMode = value['mode'];
    if (rawMode != null) {
      final DVThemeMode? found =
          DVThemeMode.values.where((DVThemeMode candidate) => candidate.name == '$rawMode'.trim()).firstOrNull;
      if (found == null) {
        problems.add('dartvel.theme.mode is "$rawMode"; it is system, light or dark.');
      } else {
        mode = found;
      }
    }
    final Map<DVColorRole, DVColorPair> colors = <DVColorRole, DVColorPair>{};
    final Object? rawColors = value['colors'];
    if (rawColors != null && rawColors is! Map) {
      problems.add('dartvel.theme.colors must be a map of colour roles.');
    } else if (rawColors is Map) {
      final String roleNames = DVColorRole.values.map((DVColorRole role) => role.name).join(', ');
      for (final MapEntry<Object?, Object?> entry in rawColors.entries) {
        final String where = 'dartvel.theme.colors.${entry.key}';
        final DVColorRole? role =
            DVColorRole.values.where((DVColorRole candidate) => candidate.name == '${entry.key}').firstOrNull;
        if (role == null) {
          problems.add('$where is not a colour role; the roles are $roleNames.');
          continue;
        }
        final Object? raw = entry.value;
        String? light;
        String? dark;
        if (raw is Map) {
          for (final Object? key in raw.keys) {
            if (key != 'light' && key != 'dark') {
              problems.add('$where has an unknown key "$key"; a role takes light and dark.');
            }
          }
          light = normalise(raw['light']);
          dark = normalise(raw['dark']);
          if (raw['light'] != null && light == null) {
            problems.add('$where.light is "${raw['light']}", which is not a #RRGGBB, #RRGGBBAA or #RGB colour.');
          }
          if (raw['dark'] != null && dark == null) {
            problems.add('$where.dark is "${raw['dark']}", which is not a #RRGGBB, #RRGGBBAA or #RGB colour.');
          }
          if (light == null && dark == null) {
            if (raw['light'] == null && raw['dark'] == null) problems.add('$where names neither light nor dark.');
            continue;
          }
          // One mode named: that colour in both, since a role half-declared
          // would switch to Dartvel's blue when the reader switches mode.
          light ??= dark;
          dark ??= light;
        } else {
          light = dark = normalise(raw);
          if (light == null) {
            problems.add('$where is "$raw", which is not a #RRGGBB, #RRGGBBAA or #RGB colour, '
                'nor a map of light and dark.');
            continue;
          }
        }
        colors[role] = DVColorPair(light: light!, dark: dark!);
      }
    }
    return DVThemeConfigReading(
      DVThemeConfig(seed: seed, mode: mode, colors: Map<DVColorRole, DVColorPair>.unmodifiable(colors)),
      problems: List<String>.unmodifiable(problems),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! DVThemeConfig || other.seed != seed || other.mode != mode) return false;
    if (other.colors.length != colors.length) return false;
    for (final MapEntry<DVColorRole, DVColorPair> entry in colors.entries) {
      if (other.colors[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        seed,
        mode,
        Object.hashAllUnordered(colors.entries.map((MapEntry<DVColorRole, DVColorPair> e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'DVThemeConfig(${toPubspec()})';
}

/// What reading `dartvel.theme` found.
class DVThemeConfigReading {
  const DVThemeConfigReading(this.config, {this.problems = const <String>[]});

  final DVThemeConfig config;

  /// Why a setting was left out. Reported rather than thrown.
  final List<String> problems;
}
