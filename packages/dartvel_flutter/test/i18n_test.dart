// Locale tags, parsed the way BCP 47 defines them.
//
// The status file recorded this section as designed with no evidence. The
// parsing was built; what it was not was correct for tags with a script
// subtag, and that failure is silent. `zh-Hant-TW` produced a locale whose
// country code was `Hant`, which is a script. Nothing throws. Supported-locale
// matching just quietly misses, and the app falls back to its default
// language while looking as though it resolved one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsing a locale tag', () {
    test('a bare language is just the language', () {
      expect(DvI18n.parseLocale('en'), const Locale('en'));
    });

    test('a two-letter second subtag is a region', () {
      final locale = DvI18n.parseLocale('en-US');

      expect(locale.languageCode, 'en');
      expect(locale.countryCode, 'US');
      expect(locale.scriptCode, isNull);
    });

    // The defect. In BCP 47 a four-letter subtag after the language is a
    // script, never a region, and regions are two letters or three digits.
    test('a four-letter second subtag is a script, not a region', () {
      final locale = DvI18n.parseLocale('zh-Hant');

      expect(locale.languageCode, 'zh');
      expect(locale.scriptCode, 'Hant');
      expect(locale.countryCode, isNull,
          reason: 'Hant is a script; putting it in countryCode breaks matching');
    });

    test('language, script and region together all survive', () {
      final locale = DvI18n.parseLocale('zh-Hant-TW');

      expect(locale.languageCode, 'zh');
      expect(locale.scriptCode, 'Hant');
      expect(locale.countryCode, 'TW');
    });

    test('a three-digit region is a region', () {
      // UN M.49 codes are legal regions: 419 is Latin America.
      final locale = DvI18n.parseLocale('es-419');

      expect(locale.languageCode, 'es');
      expect(locale.countryCode, '419');
    });

    test('an underscore separator parses the same as a hyphen', () {
      // Posix-style tags arrive from environment variables and older APIs.
      expect(DvI18n.parseLocale('pt_BR'), DvI18n.parseLocale('pt-BR'));
      expect(DvI18n.parseLocale('zh_Hant_TW'), DvI18n.parseLocale('zh-Hant-TW'));
    });

    test('case is normalised the way BCP 47 writes it', () {
      // Tags are case-insensitive, but Flutter compares locales by exact
      // string, so en-us and EN-US have to land on the same Locale as en-US
      // or supported-locale matching misses.
      final locale = DvI18n.parseLocale('ZH-hant-tw');

      expect(locale.languageCode, 'zh');
      expect(locale.scriptCode, 'Hant');
      expect(locale.countryCode, 'TW');
    });

    test('an empty or malformed tag falls back rather than throwing', () {
      expect(DvI18n.parseLocale(''), const Locale('en'));
      expect(DvI18n.parseLocale('-'), const Locale('en'));
    });
  });

  group('the scope resolves the same way', () {
    // The scope had its own copy of the parsing, so the same tag could
    // resolve one way through DvI18n and another through the widget tree.
    test('a scope and the parser agree on a script tag', () {
      const scope = DvI18nScope(
        localeTag: 'zh-Hant-TW',
        child: SizedBox.shrink(),
      );

      expect(scope.locale, DvI18n.parseLocale('zh-Hant-TW'));
      expect(scope.locale.scriptCode, 'Hant');
    });
  });

  group('normalising against the supported set', () {
    test('a supported tag is returned as the set spells it', () {
      expect(DvI18n.normalize('EN-us', <String>['en-US', 'fr-FR'], 'en-US'),
          'en-US');
    });

    test('an unsupported tag falls back', () {
      expect(DvI18n.normalize('de-DE', <String>['en-US'], 'en-US'), 'en-US');
    });

    test('a null or blank tag falls back', () {
      expect(DvI18n.normalize(null, <String>['en-US'], 'en-US'), 'en-US');
      expect(DvI18n.normalize('   ', <String>['en-US'], 'en-US'), 'en-US');
    });
  });

  group('text direction', () {
    test('the right-to-left languages are recognised', () {
      for (final String tag in <String>['ar', 'ar-EG', 'he-IL', 'fa', 'ur-PK']) {
        expect(LocaleTag(tag).isRightToLeft, isTrue, reason: tag);
      }
    });

    test('left-to-right languages are not', () {
      for (final String tag in <String>['en-US', 'fr-FR', 'zh-Hant-TW']) {
        expect(LocaleTag(tag).isRightToLeft, isFalse, reason: tag);
      }
    });
  });
}
