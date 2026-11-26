// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from voice_settings.dart by tool/generate_framework_models.dart, with the
// same emitter as an application's @DVModel(storage: DVModelStorage.device).
// ignore_for_file: directives_ordering, unused_element
import 'dart:convert' as convert;

import '../../dartvel_flutter.dart' show DV;
import '../platform/storage/preference_store.dart';

/// Where voice mode, its confirmations and receipts sit on the screen.
enum DVVoicePosition {
  /// At the top, the usual place.
  top,

  /// In the middle of the screen, for a narrow field of view.
  centre,
}

/// The reader's voice-mode settings: where it sits and the language it
/// speaks and listens in (a language code from the app's voice languages).
///
/// Kept on the visitor's device under `dartvel.voice`: read it with [kept] (or
/// `context.global<DVVoiceSettings>()` in a widget, which rebuilds on a change) and
/// write it with [keep].
class const DVVoiceSettings({
  final DVVoicePosition position = DVVoicePosition.top,
  final String language = 'en',
}) {
  /// Where it is kept in [DVPreferenceStore].
  static const String storageKey = 'dartvel.voice';

  /// Every field at its default: what a visitor has before keeping anything.
  static const DVVoiceSettings defaults = DVVoiceSettings();

  static bool _dvRegistered = false;

  /// The value kept on this device, or [defaults]. Read once, then from
  /// `DV.global<DVVoiceSettings>()`, which [keep] and [forget] update.
  static DVVoiceSettings get kept {
    if (!_dvRegistered) {
      _dvRegistered = true;
      DV.global<DVVoiceSettings>(decode(DVPreferenceStore.instance.read(storageKey)));
    }
    return DV.global<DVVoiceSettings>();
  }

  /// Whether anything is kept on this device yet.
  static bool get isKept => DVPreferenceStore.instance.read(storageKey) != null;

  /// Keeps this value for the next visit and makes it [kept], rebuilding
  /// every widget that reads `context.global<DVVoiceSettings>()`.
  DVVoiceSettings keep() {
    DVPreferenceStore.instance.write(storageKey, encode());
    _dvRegistered = true;
    DV.global<DVVoiceSettings>(this);
    return this;
  }

  /// Forgets what this device kept: [kept] is [defaults] again.
  static void forget() {
    DVPreferenceStore.instance.remove(storageKey);
    _dvRegistered = true;
    DV.global<DVVoiceSettings>(defaults);
  }

  /// The value in [stored] (what [encode] wrote). Missing, unreadable or
  /// wrong-typed fields are their defaults, so an old or broken value never
  /// stops a page.
  static DVVoiceSettings decode(String? stored) {
    if (stored == null || stored.isEmpty) return defaults;
    final Object? decoded;
    try {
      decoded = convert.jsonDecode(stored);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, Object?>) return defaults;
    return DVVoiceSettingsParser.fromJson(decoded);
  }

  /// The stored form: JSON text.
  String encode() => convert.jsonEncode(toJson());

  /// This value as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'position': position.name,
        'language': language,
      };

  /// A copy with the given fields replaced.
  DVVoiceSettings copyWith({DVVoicePosition? position, String? language}) => DVVoiceSettings(
        position: position ?? this.position,
        language: language ?? this.language,
      );

  @override
  bool operator ==(Object other) =>
      other is DVVoiceSettings && other.position == position && other.language == language;

  @override
  int get hashCode => Object.hashAll(<Object?>[position, language]);

  @override
  String toString() => 'DVVoiceSettings(position: $position, language: $language)';
}

/// Reads a [DVVoiceSettings] from JSON.
class DVVoiceSettingsParser {
  /// [json] as a [DVVoiceSettings]: a field that is missing or of the wrong type is
  /// its default, and keys it does not know are ignored.
  static DVVoiceSettings fromJson(Map<String, Object?> json) {
    const DVVoiceSettings defaults = DVVoiceSettings.defaults;
    final Object? position = json['position'];
    final Object? language = json['language'];
    return DVVoiceSettings(
      position: position is String ? (DVVoicePosition.values.asNameMap()[position] ?? defaults.position) : defaults.position,
      language: language is String ? language : defaults.language,
    );
  }
}

