/// `dartvel.accessibility.defaultControls`: the accessibility button and panel every
/// Dartvel app can opt into, and what it offers.
///
/// ```yaml
/// dartvel:
///   accessibility:
///     defaultControls: true     # the framework's floating button on every page
///     # or, for an app that puts DVAccessibilityButton() in its own header,
///     # offers voice mode, and kept settings of its own before:
///     # defaultControls:
///     #   floatingButton: false
///     #   voice:
///     #     languages: [en, pcm, yo]
///     #     machineTranslated: [yo]
///     #   formerKey: shop.display
/// ```
///
/// The same object in a Dart config class is [DVAccessibilityDefaultControlsConfig],
/// returned from `DartvelConfig.accessibilityDefaultControls`. 3.47.16 called the
/// key `controls`; that spelling is still read for one release, with a build
/// warning.
///
/// What a visitor picks in the panel is a `DVAccessibilitySettings` (and, with
/// voice, a `DVVoiceSettings`): models kept on the visitor's device, in
/// dartvel_flutter. The accessibility one is kept under
/// [dvAccessibilityStorageKey], which the SSR-first head reads before the
/// first paint, so the server-rendered page is in the visitor's settings from
/// its first frame.
library;

import 'voice_languages.dart';

export 'voice_languages.dart';

/// Where a visitor's accessibility settings are kept.
const String dvAccessibilityStorageKey = 'dartvel.accessibility';

/// Where a visitor's voice settings are kept.
const String dvVoiceStorageKey = 'dartvel.voice';

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
  static DVTextSize fromScale(double value) {
    for (final DVTextSize size in values) {
      if ((size.scale - value).abs() < 0.01) return size;
    }
    return standard;
  }
}

final RegExp _plainKey = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

Never _refuse(Object? value, String path, String message) => throw ArgumentError.value(value, path, message);

/// The keys of a pubspec map, as strings; any other key is refused.
Set<String> _keysOf(Map<Object?, Object?> raw, String path, Set<String> allowed) {
  final Set<String> keys = <String>{};
  for (final Object? key in raw.keys) {
    if (key is! String || !allowed.contains(key)) {
      _refuse(raw, path, '$key is not a setting; the settings are ${allowed.join(', ')}');
    }
    keys.add(key);
  }
  return keys;
}

List<DVVoiceLanguage> _languages(Object? raw, String path) {
  if (raw is! List) _refuse(raw, path, 'must be a list of language codes');
  final List<DVVoiceLanguage> languages = <DVVoiceLanguage>[];
  for (final Object? code in raw) {
    final DVVoiceLanguage? language = DVVoiceLanguage.tryCode(code is String ? code : null);
    if (language == null) {
      _refuse(code, path,
          '$code is not a language voice mode knows; the codes are ${DVVoiceLanguage.values.map((DVVoiceLanguage l) => l.code).join(', ')}');
    }
    if (!languages.contains(language)) languages.add(language);
  }
  return languages;
}

/// `defaultControls.voice`: voice mode's settings in the panel -- where voice
/// mode sits on the screen and the language it speaks and listens in -- and
/// what the panel says about each language on this device.
final class DVAccessibilityVoiceConfig {
  const DVAccessibilityVoiceConfig({
    this.languages = const <DVVoiceLanguage>[DVVoiceLanguage.english],
    this.machineTranslated = const <DVVoiceLanguage>{},
  });

  /// The languages the panel offers, in this order; the first is the default.
  final List<DVVoiceLanguage> languages;

  /// The languages whose prompts were translated by a machine and not yet
  /// checked by a native speaker; the panel says so.
  final Set<DVVoiceLanguage> machineTranslated;

  static const Set<String> _keys = <String>{'languages', 'machineTranslated'};

  /// Whether [language]'s prompts were machine translated.
  bool isMachineTranslated(DVVoiceLanguage language) => machineTranslated.contains(language);

  /// Reads the value of `voice`: absent or false is off, true is English, a
  /// map names the languages.
  static DVAccessibilityVoiceConfig? parse(Object? raw, {required String path}) {
    if (raw == null || raw == false) return null;
    if (raw == true) return const DVAccessibilityVoiceConfig();
    if (raw is! Map<Object?, Object?>) _refuse(raw, path, 'must be true, false or a map');
    final Set<String> keys = _keysOf(raw, path, _keys);
    final List<DVVoiceLanguage> languages =
        keys.contains('languages') ? _languages(raw['languages'], '$path.languages') : const <DVVoiceLanguage>[DVVoiceLanguage.english];
    if (languages.isEmpty) _refuse(raw['languages'], '$path.languages', 'must name at least one language');
    final List<DVVoiceLanguage> translated =
        keys.contains('machineTranslated') ? _languages(raw['machineTranslated'], '$path.machineTranslated') : const <DVVoiceLanguage>[];
    for (final DVVoiceLanguage language in translated) {
      if (!languages.contains(language)) {
        _refuse(language.code, '$path.machineTranslated', '${language.code} is not one of the languages (${languages.map((DVVoiceLanguage l) => l.code).join(', ')})');
      }
    }
    return DVAccessibilityVoiceConfig(languages: languages, machineTranslated: translated.toSet());
  }

  /// The value of `voice` as the YAML writes it.
  Object toPubspec() {
    if (this == const DVAccessibilityVoiceConfig()) return true;
    return <String, Object?>{
      'languages': <Object?>[for (final DVVoiceLanguage language in languages) language.code],
      if (machineTranslated.isNotEmpty)
        'machineTranslated': <Object?>[
          for (final DVVoiceLanguage language in languages)
            if (machineTranslated.contains(language)) language.code,
        ],
    };
  }

  /// This value as Dart source, for the generated runtime.
  String toSource() => 'const DVAccessibilityVoiceConfig('
      'languages: <DVVoiceLanguage>[${languages.map((DVVoiceLanguage l) => 'DVVoiceLanguage.${l.name}').join(', ')}]'
      '${machineTranslated.isEmpty ? '' : ', machineTranslated: <DVVoiceLanguage>{${languages.where(machineTranslated.contains).map((DVVoiceLanguage l) => 'DVVoiceLanguage.${l.name}').join(', ')}}'}'
      ')';

  @override
  bool operator ==(Object other) =>
      other is DVAccessibilityVoiceConfig &&
      _sameList(other.languages, languages) &&
      other.machineTranslated.length == machineTranslated.length &&
      other.machineTranslated.containsAll(machineTranslated);

  @override
  int get hashCode => Object.hash(Object.hashAll(languages), Object.hashAllUnordered(machineTranslated));
}

bool _sameList(List<DVVoiceLanguage> a, List<DVVoiceLanguage> b) {
  if (a.length != b.length) return false;
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// `dartvel.accessibility.defaultControls`: whether the app has the
/// accessibility button and panel, whether the framework places the button,
/// whether the panel offers voice mode's settings, and where the app kept its
/// own settings before.
final class DVAccessibilityDefaultControlsConfig {
  const DVAccessibilityDefaultControlsConfig({
    this.enabled = false,
    this.floatingButton = true,
    this.voice,
    this.formerKey,
  });

  /// Off: the default. An app gets the controls only when it asks.
  static const DVAccessibilityDefaultControlsConfig off = DVAccessibilityDefaultControlsConfig();

  /// The pubspec key, under `dartvel.accessibility`.
  static const String key = 'defaultControls';

  /// The key 3.47.16 shipped. Read for one more release, with a build
  /// warning naming [key]; removed after that.
  static const String deprecatedKey = 'controls';

  /// The controls are on: every page is drawn in the visitor's settings and
  /// the panel can be opened.
  final bool enabled;

  /// The framework draws the button over every page, in the bottom corner on
  /// the reading side. False for an app that puts `DVAccessibilityButton()`
  /// where it wants it (usually its header).
  final bool floatingButton;

  /// Voice mode's settings in the panel, or null for none.
  final DVAccessibilityVoiceConfig? voice;

  /// The storage key an app kept its own display or voice settings under
  /// before it used these controls. Read once, on a visitor's first visit
  /// after the move: text size (`textScale`, or `largeText: true`), high
  /// contrast, reduced motion, voice position (`position` or `zone`, top or
  /// centre) and voice language (`language`, a code) are carried over, so
  /// nobody loses what they chose. The old value is left where it was.
  final String? formerKey;

  static const Set<String> _keys = <String>{'enabled', 'floatingButton', 'voice', 'formerKey'};

  /// Reads the value of `defaultControls`: absent or false is off, true is on
  /// with the floating button, a map is on unless it says `enabled: false`.
  /// A key it does not know is refused, naming it. [key] is the key the
  /// value was written under, for the error.
  static DVAccessibilityDefaultControlsConfig parse(Object? raw, {String key = key}) {
    final String path = 'dartvel.accessibility.$key';
    if (raw == null || raw == false) return off;
    if (raw == true) return const DVAccessibilityDefaultControlsConfig(enabled: true);
    if (raw is! Map<Object?, Object?>) _refuse(raw, path, 'must be true, false or a map');
    _keysOf(raw, path, _keys);
    bool flag(String setting, bool fallback) {
      final Object? value = raw[setting];
      if (value == null) return fallback;
      if (value is! bool) _refuse(value, '$path.$setting', 'must be true or false');
      return value;
    }

    final Object? former = raw['formerKey'];
    if (former != null && (former is! String || !_plainKey.hasMatch(former) || former.contains('..'))) {
      _refuse(former, '$path.formerKey', 'must be a storage key: letters, digits, ".", "_" or "-"');
    }
    return DVAccessibilityDefaultControlsConfig(
      enabled: flag('enabled', true),
      floatingButton: flag('floatingButton', true),
      voice: DVAccessibilityVoiceConfig.parse(raw['voice'], path: '$path.voice'),
      formerKey: former as String?,
    );
  }

  /// Reads `accessibility.defaultControls` from the `dartvel:` object, or the
  /// deprecated `accessibility.controls` when that is the one written. Both
  /// at once is refused rather than one silently winning.
  static DVAccessibilityDefaultControlsConfig fromSection(Map<Object?, Object?> section) {
    final Object? accessibility = section['accessibility'];
    if (accessibility is! Map<Object?, Object?>) return off;
    final bool hasNew = accessibility.containsKey(key);
    final bool hasOld = accessibility.containsKey(deprecatedKey);
    if (hasNew && hasOld) {
      _refuse(accessibility, 'dartvel.accessibility',
          'has both $key and $deprecatedKey; $deprecatedKey was renamed $key, so keep only $key');
    }
    if (hasOld) return parse(accessibility[deprecatedKey], key: deprecatedKey);
    return parse(accessibility[key]);
  }

  /// The value of `defaultControls` as the YAML writes it; null when off.
  Object? toPubspec() {
    if (!enabled) return null;
    if (floatingButton && voice == null && formerKey == null) return true;
    return <String, Object?>{
      if (!floatingButton) 'floatingButton': false,
      if (voice != null) 'voice': voice!.toPubspec(),
      if (formerKey != null) 'formerKey': formerKey,
    };
  }

  /// The generated runtime's call that turns the controls on for [app].
  String installSource({required String app}) {
    final String escaped = app.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return 'DVAccessibilityControls.instance.install(floatingButton: $floatingButton, app: \'$escaped\''
        '${voice == null ? '' : ', voice: ${voice!.toSource()}'}'
        "${formerKey == null ? '' : ", formerKey: '$formerKey'"});";
  }

  @override
  bool operator ==(Object other) =>
      other is DVAccessibilityDefaultControlsConfig &&
      other.enabled == enabled &&
      other.floatingButton == floatingButton &&
      other.voice == voice &&
      other.formerKey == formerKey;

  @override
  int get hashCode => Object.hash(enabled, floatingButton, voice, formerKey);
}

/// The 3.47.16 name of [DVAccessibilityDefaultControlsConfig].
@Deprecated('Renamed DVAccessibilityDefaultControlsConfig (dartvel.accessibility.defaultControls); '
    'this name is removed in the next release.')
typedef DVAccessibilityControlsConfig = DVAccessibilityDefaultControlsConfig;
