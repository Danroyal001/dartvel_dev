/// `dartvel.accessibility.controls`: the accessibility button and panel every
/// Dartvel app can opt into, and the visitor's choices it keeps.
///
/// ```yaml
/// dartvel:
///   accessibility:
///     controls: true            # the framework's floating button on every page
///     # or, for an app that puts DVAccessibilityButton() in its own header:
///     # controls:
///     #   floatingButton: false
/// ```
///
/// The same object in a Dart config class is [DVAccessibilityControlsConfig],
/// returned from `DartvelConfig.accessibilityControls`.
///
/// What a visitor picks in the panel is a [DVAccessibilitySettings], kept as
/// one small JSON value under [dvAccessibilityStorageKey]: `localStorage` in
/// a browser, a file on a device. The SSR-first head reads the same value
/// before the first paint, so the server-rendered page is in the visitor's
/// settings from its first frame.
library;

import 'dart:convert';

/// Where a visitor's accessibility settings are kept.
const String dvAccessibilityStorageKey = 'dartvel.accessibility';

/// The text sizes the panel offers, on top of the device's own text size.
enum DVTextSize {
  /// The app's own sizes.
  standard(1.0, 'Default'),

  /// About a third bigger.
  large(1.35, 'Large'),

  /// About two thirds bigger.
  larger(1.7, 'Larger');

  const DVTextSize(this.scale, this.label);

  /// How much bigger text is drawn.
  final double scale;

  /// The name the panel shows.
  final String label;

  /// The size whose [scale] is [value], or [standard].
  static DVTextSize fromScale(Object? value) {
    if (value is! num) return standard;
    for (final DVTextSize size in values) {
      if ((size.scale - value).abs() < 0.01) return size;
    }
    return standard;
  }
}

/// What a visitor chose in the accessibility panel. The operating system's
/// own settings (reduce motion, more contrast, its text size) always count on
/// top of these; see `DV.Accessibility.controls` in dartvel_flutter.
final class DVAccessibilitySettings {
  const DVAccessibilitySettings({
    this.textSize = DVTextSize.standard,
    this.highContrast = false,
    this.reducedMotion = false,
  });

  final DVTextSize textSize;
  final bool highContrast;
  final bool reducedMotion;

  /// How much bigger text is drawn, on top of the device's text size.
  double get textScale => textSize.scale;

  /// Nothing chosen.
  bool get isDefault => textSize == DVTextSize.standard && !highContrast && !reducedMotion;

  DVAccessibilitySettings copyWith({DVTextSize? textSize, bool? highContrast, bool? reducedMotion}) =>
      DVAccessibilitySettings(
        textSize: textSize ?? this.textSize,
        highContrast: highContrast ?? this.highContrast,
        reducedMotion: reducedMotion ?? this.reducedMotion,
      );

  /// The stored form, the one the SSR-first head reads.
  String encode() => jsonEncode(<String, Object?>{
        'v': 1,
        'textScale': textScale,
        'highContrast': highContrast,
        'reducedMotion': reducedMotion,
      });

  /// Settings from [stored]. Anything unreadable is the default, so a broken
  /// value never stops a page.
  static DVAccessibilitySettings decode(String? stored) {
    if (stored == null || stored.isEmpty) return const DVAccessibilitySettings();
    final Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return const DVAccessibilitySettings();
    }
    if (decoded is! Map) return const DVAccessibilitySettings();
    return DVAccessibilitySettings(
      textSize: DVTextSize.fromScale(decoded['textScale']),
      highContrast: decoded['highContrast'] == true,
      reducedMotion: decoded['reducedMotion'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVAccessibilitySettings &&
      other.textSize == textSize &&
      other.highContrast == highContrast &&
      other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hash(textSize, highContrast, reducedMotion);

  @override
  String toString() => 'DVAccessibilitySettings(${encode()})';
}

/// `dartvel.accessibility.controls`: whether the app has the accessibility
/// button and panel, and whether the framework places the button.
final class DVAccessibilityControlsConfig {
  const DVAccessibilityControlsConfig({this.enabled = false, this.floatingButton = true});

  /// Off: the default. An app gets the controls only when it asks.
  static const DVAccessibilityControlsConfig off = DVAccessibilityControlsConfig();

  /// The controls are on: every page is drawn in the visitor's settings and
  /// the panel can be opened.
  final bool enabled;

  /// The framework draws the button over every page, in the bottom corner on
  /// the reading side. False for an app that puts `DVAccessibilityButton()`
  /// where it wants it (usually its header).
  final bool floatingButton;

  static const Set<String> _keys = <String>{'enabled', 'floatingButton'};

  /// Reads the value of `controls`: absent or false is off, true is on with
  /// the floating button, a map is on unless it says `enabled: false`.
  /// A key it does not know is refused, naming it.
  static DVAccessibilityControlsConfig parse(Object? raw) {
    if (raw == null || raw == false) return off;
    if (raw == true) return const DVAccessibilityControlsConfig(enabled: true);
    if (raw is! Map) {
      throw ArgumentError.value(raw, 'dartvel.accessibility.controls', 'must be true, false or a map');
    }
    for (final Object? key in raw.keys) {
      if (!_keys.contains(key)) {
        throw ArgumentError.value(
            raw, 'dartvel.accessibility.controls', '$key is not a setting; the settings are ${_keys.join(', ')}');
      }
    }
    bool flag(String key, bool fallback) {
      final Object? value = raw[key];
      if (value == null) return fallback;
      if (value is! bool) {
        throw ArgumentError.value(value, 'dartvel.accessibility.controls.$key', 'must be true or false');
      }
      return value;
    }

    return DVAccessibilityControlsConfig(enabled: flag('enabled', true), floatingButton: flag('floatingButton', true));
  }

  /// Reads `accessibility.controls` from the `dartvel:` object.
  static DVAccessibilityControlsConfig fromSection(Map<Object?, Object?> section) {
    final Object? accessibility = section['accessibility'];
    return parse(accessibility is Map ? accessibility['controls'] : null);
  }

  /// The value of `controls` as the YAML writes it; null when off.
  Object? toPubspec() {
    if (!enabled) return null;
    if (floatingButton) return true;
    return <String, Object?>{'floatingButton': false};
  }

  @override
  bool operator ==(Object other) =>
      other is DVAccessibilityControlsConfig && other.enabled == enabled && other.floatingButton == floatingButton;

  @override
  int get hashCode => Object.hash(enabled, floatingButton);
}
