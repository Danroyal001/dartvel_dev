// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from former_settings.dart by tool/generate_framework_models.dart, with the
// same emitter as an application's @DVModel(storage: DVModelStorage.device).
// ignore_for_file: directives_ordering, unused_element
import 'dart:convert' as convert;

import '../../dartvel_flutter.dart' show DV;
import '../platform/storage/preference_store.dart';

/// What an earlier version of an app may have kept: a text scale or just
/// "large text", contrast, motion, and voice mode's position and language.
///
/// Kept on the visitor's device under `dartvel.accessibility.former`: read it with [kept] (or
/// `context.global<DVFormerAccessibilitySettings>()` in a widget, which rebuilds on a change) and
/// write it with [keep].
class const DVFormerAccessibilitySettings({
  final double? textScale,
  final bool largeText = false,
  final bool highContrast = false,
  final bool reducedMotion = false,
  final String? position,
  final String? zone,
  final String? language,
}) {
  /// Where it is kept in [DVPreferenceStore].
  static const String storageKey = 'dartvel.accessibility.former';

  /// Every field at its default: what a visitor has before keeping anything.
  static const DVFormerAccessibilitySettings defaults = DVFormerAccessibilitySettings();

  static bool _dvRegistered = false;

  /// The value kept on this device, or [defaults]. Read once, then from
  /// `DV.global<DVFormerAccessibilitySettings>()`, which [keep] and [forget] update.
  static DVFormerAccessibilitySettings get kept {
    if (!_dvRegistered) {
      _dvRegistered = true;
      DV.global<DVFormerAccessibilitySettings>(decode(DVPreferenceStore.instance.read(storageKey)));
    }
    return DV.global<DVFormerAccessibilitySettings>();
  }

  /// Whether anything is kept on this device yet.
  static bool get isKept => DVPreferenceStore.instance.read(storageKey) != null;

  /// Keeps this value for the next visit and makes it [kept], rebuilding
  /// every widget that reads `context.global<DVFormerAccessibilitySettings>()`.
  DVFormerAccessibilitySettings keep() {
    DVPreferenceStore.instance.write(storageKey, encode());
    _dvRegistered = true;
    DV.global<DVFormerAccessibilitySettings>(this);
    return this;
  }

  /// Forgets what this device kept: [kept] is [defaults] again.
  static void forget() {
    DVPreferenceStore.instance.remove(storageKey);
    _dvRegistered = true;
    DV.global<DVFormerAccessibilitySettings>(defaults);
  }

  /// The value in [stored] (what [encode] wrote). Missing, unreadable or
  /// wrong-typed fields are their defaults, so an old or broken value never
  /// stops a page.
  static DVFormerAccessibilitySettings decode(String? stored) {
    if (stored == null || stored.isEmpty) return defaults;
    final Object? decoded;
    try {
      decoded = convert.jsonDecode(stored);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, Object?>) return defaults;
    return DVFormerAccessibilitySettingsParser.fromJson(decoded);
  }

  /// The stored form: JSON text.
  String encode() => convert.jsonEncode(toJson());

  /// This value as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'textScale': textScale,
        'largeText': largeText,
        'highContrast': highContrast,
        'reducedMotion': reducedMotion,
        'position': position,
        'zone': zone,
        'language': language,
      };

  /// A copy with the given fields replaced.
  DVFormerAccessibilitySettings copyWith({double? textScale, bool? largeText, bool? highContrast, bool? reducedMotion, String? position, String? zone, String? language}) => DVFormerAccessibilitySettings(
        textScale: textScale ?? this.textScale,
        largeText: largeText ?? this.largeText,
        highContrast: highContrast ?? this.highContrast,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        position: position ?? this.position,
        zone: zone ?? this.zone,
        language: language ?? this.language,
      );

  @override
  bool operator ==(Object other) =>
      other is DVFormerAccessibilitySettings && other.textScale == textScale && other.largeText == largeText && other.highContrast == highContrast && other.reducedMotion == reducedMotion && other.position == position && other.zone == zone && other.language == language;

  @override
  int get hashCode => Object.hashAll(<Object?>[textScale, largeText, highContrast, reducedMotion, position, zone, language]);

  @override
  String toString() => 'DVFormerAccessibilitySettings(textScale: $textScale, largeText: $largeText, highContrast: $highContrast, reducedMotion: $reducedMotion, position: $position, zone: $zone, language: $language)';
}

/// Reads a [DVFormerAccessibilitySettings] from JSON.
class DVFormerAccessibilitySettingsParser {
  /// [json] as a [DVFormerAccessibilitySettings]: a field that is missing or of the wrong type is
  /// its default, and keys it does not know are ignored.
  static DVFormerAccessibilitySettings fromJson(Map<String, Object?> json) {
    const DVFormerAccessibilitySettings defaults = DVFormerAccessibilitySettings.defaults;
    final Object? textScale = json['textScale'];
    final Object? largeText = json['largeText'];
    final Object? highContrast = json['highContrast'];
    final Object? reducedMotion = json['reducedMotion'];
    final Object? position = json['position'];
    final Object? zone = json['zone'];
    final Object? language = json['language'];
    return DVFormerAccessibilitySettings(
      textScale: textScale is num ? textScale.toDouble() : defaults.textScale,
      largeText: largeText is bool ? largeText : defaults.largeText,
      highContrast: highContrast is bool ? highContrast : defaults.highContrast,
      reducedMotion: reducedMotion is bool ? reducedMotion : defaults.reducedMotion,
      position: position is String ? position : defaults.position,
      zone: zone is String ? zone : defaults.zone,
      language: language is String ? language : defaults.language,
    );
  }
}

