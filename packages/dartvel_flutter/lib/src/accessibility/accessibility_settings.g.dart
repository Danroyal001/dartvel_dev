// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from accessibility_settings.dart by tool/generate_framework_models.dart, with the
// same emitter as an application's @DVModel(storage: DVModelStorage.device).
// ignore_for_file: directives_ordering, unused_element
import 'dart:convert' as convert;

import '../../dartvel_flutter.dart' show DV;
import '../platform/storage/preference_store.dart';

/// What a visitor chose in the accessibility panel. The operating system's
/// own settings (reduce motion, more contrast, its text size) always count on
/// top of these. Kept as `{textScale, highContrast, reducedMotion}`, which
/// the SSR-first head reads before the first paint.
///
/// Kept on the visitor's device under `dartvel.accessibility`: read it with [kept] (or
/// `context.global<DVAccessibilitySettings>()` in a widget, which rebuilds on a change) and
/// write it with [keep].
class const DVAccessibilitySettings({
  final double textScale = 1.0,
  final bool highContrast = false,
  final bool reducedMotion = false,
}) {
  /// Where it is kept in [DVPreferenceStore].
  static const String storageKey = 'dartvel.accessibility';

  /// Every field at its default: what a visitor has before keeping anything.
  static const DVAccessibilitySettings defaults = DVAccessibilitySettings();

  static bool _dvRegistered = false;

  /// The value kept on this device, or [defaults]. Read once, then from
  /// `DV.global<DVAccessibilitySettings>()`, which [keep] and [forget] update.
  static DVAccessibilitySettings get kept {
    if (!_dvRegistered) {
      _dvRegistered = true;
      DV.global<DVAccessibilitySettings>(decode(DVPreferenceStore.instance.read(storageKey)));
    }
    return DV.global<DVAccessibilitySettings>();
  }

  /// Whether anything is kept on this device yet.
  static bool get isKept => DVPreferenceStore.instance.read(storageKey) != null;

  /// Keeps this value for the next visit and makes it [kept], rebuilding
  /// every widget that reads `context.global<DVAccessibilitySettings>()`.
  DVAccessibilitySettings keep() {
    DVPreferenceStore.instance.write(storageKey, encode());
    _dvRegistered = true;
    DV.global<DVAccessibilitySettings>(this);
    return this;
  }

  /// Forgets what this device kept: [kept] is [defaults] again.
  static void forget() {
    DVPreferenceStore.instance.remove(storageKey);
    _dvRegistered = true;
    DV.global<DVAccessibilitySettings>(defaults);
  }

  /// The value in [stored] (what [encode] wrote). Missing, unreadable or
  /// wrong-typed fields are their defaults, so an old or broken value never
  /// stops a page.
  static DVAccessibilitySettings decode(String? stored) {
    if (stored == null || stored.isEmpty) return defaults;
    final Object? decoded;
    try {
      decoded = convert.jsonDecode(stored);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, Object?>) return defaults;
    return DVAccessibilitySettingsParser.fromJson(decoded);
  }

  /// The stored form: JSON text.
  String encode() => convert.jsonEncode(toJson());

  /// This value as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'textScale': textScale,
        'highContrast': highContrast,
        'reducedMotion': reducedMotion,
      };

  /// A copy with the given fields replaced.
  DVAccessibilitySettings copyWith({double? textScale, bool? highContrast, bool? reducedMotion}) => DVAccessibilitySettings(
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        reducedMotion: reducedMotion ?? this.reducedMotion,
      );

  @override
  bool operator ==(Object other) =>
      other is DVAccessibilitySettings && other.textScale == textScale && other.highContrast == highContrast && other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hashAll(<Object?>[textScale, highContrast, reducedMotion]);

  @override
  String toString() => 'DVAccessibilitySettings(textScale: $textScale, highContrast: $highContrast, reducedMotion: $reducedMotion)';
}

/// Reads a [DVAccessibilitySettings] from JSON.
class DVAccessibilitySettingsParser {
  /// [json] as a [DVAccessibilitySettings]: a field that is missing or of the wrong type is
  /// its default, and keys it does not know are ignored.
  static DVAccessibilitySettings fromJson(Map<String, Object?> json) {
    const DVAccessibilitySettings defaults = DVAccessibilitySettings.defaults;
    final Object? textScale = json['textScale'];
    final Object? highContrast = json['highContrast'];
    final Object? reducedMotion = json['reducedMotion'];
    return DVAccessibilitySettings(
      textScale: textScale is num ? textScale.toDouble() : defaults.textScale,
      highContrast: highContrast is bool ? highContrast : defaults.highContrast,
      reducedMotion: reducedMotion is bool ? reducedMotion : defaults.reducedMotion,
    );
  }
}

