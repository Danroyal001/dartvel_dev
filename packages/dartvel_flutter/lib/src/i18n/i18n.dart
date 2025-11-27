import 'package:flutter/widgets.dart';

/// Internationalization support
class I18n {
  static Locale? _locale;
  static final Map<String, Map<String, String>> _translations = {};

  static void load(Locale locale, Map<String, String> translations) {
    _locale = locale;
    _translations[locale.languageCode] = translations;
  }

  static String tr(String key, [Map<String, dynamic>? args]) {
    final lang = _locale?.languageCode ?? 'en';
    var text = _translations[lang]?[key] ?? key;

    if (args != null) {
      args.forEach((k, v) {
        text = text.replaceAll('{$k}', v.toString());
      });
    }
    return text;
  }
}

extension StringI18n on String {
  String tr([Map<String, dynamic>? args]) => I18n.tr(this, args);
}
