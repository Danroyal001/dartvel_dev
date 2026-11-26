/// The languages voice mode can speak and listen in, for
/// `dartvel.accessibility.defaultControls.voice.languages`.
///
/// An app names the ones it offers by [code]; the panel lists them in that
/// order. [speechTag] is what the device's speech engines are asked for, so a
/// language with no voice of its own (Nigerian Pidgin) is read by the nearest
/// one (Nigerian English).
library;

/// One language voice mode can use.
enum DVVoiceLanguage {
  english('en', 'en-US', 'English', 'English'),
  pidgin('pcm', 'en-NG', 'Nigerian Pidgin', 'Naijá'),
  yoruba('yo', 'yo-NG', 'Yoruba', 'Yorùbá'),
  igbo('ig', 'ig-NG', 'Igbo', 'Igbo'),
  hausa('ha', 'ha-NG', 'Hausa', 'Hausa'),
  ibibio('ibb', 'ibb-NG', 'Ibibio', 'Ibibio'),
  swahili('sw', 'sw-KE', 'Swahili', 'Kiswahili'),
  amharic('am', 'am-ET', 'Amharic', 'አማርኛ'),
  zulu('zu', 'zu-ZA', 'Zulu', 'isiZulu'),
  afrikaans('af', 'af-ZA', 'Afrikaans', 'Afrikaans'),
  french('fr', 'fr-FR', 'French', 'Français'),
  spanish('es', 'es-ES', 'Spanish', 'Español'),
  portuguese('pt', 'pt-BR', 'Portuguese', 'Português'),
  german('de', 'de-DE', 'German', 'Deutsch'),
  italian('it', 'it-IT', 'Italian', 'Italiano'),
  dutch('nl', 'nl-NL', 'Dutch', 'Nederlands'),
  arabic('ar', 'ar-SA', 'Arabic', 'العربية'),
  turkish('tr', 'tr-TR', 'Turkish', 'Türkçe'),
  russian('ru', 'ru-RU', 'Russian', 'Русский'),
  hindi('hi', 'hi-IN', 'Hindi', 'हिन्दी'),
  chinese('zh', 'zh-CN', 'Chinese', '中文'),
  japanese('ja', 'ja-JP', 'Japanese', '日本語'),
  korean('ko', 'ko-KR', 'Korean', '한국어');

  const DVVoiceLanguage(this.code, this.speechTag, this.englishName, this.nativeName);

  /// ISO 639 code: how a language is named in the pubspec and kept.
  final String code;

  /// The BCP 47 tag asked of the device's speech engines.
  final String speechTag;

  /// The language's name in English.
  final String englishName;

  /// The language's name in itself.
  final String nativeName;

  /// The language whose [code] is [code], or null.
  static DVVoiceLanguage? tryCode(String? code) {
    for (final DVVoiceLanguage language in values) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// The language whose [code] is [code], or [english].
  static DVVoiceLanguage fromCode(String? code) => tryCode(code) ?? english;

  /// What a menu shows: the English name, and the native one where it differs.
  String get displayName => nativeName == englishName ? englishName : '$englishName ($nativeName)';

  /// Whether one of the device's voices, by their language [tags] (`en-US`,
  /// `yo_NG`), speaks this language.
  bool hasVoiceIn(Set<String> tags) {
    final String wanted = speechTag.split('-').first.toLowerCase();
    return tags.any((String tag) => tag.split(RegExp('[-_]')).first.toLowerCase() == wanted);
  }
}
