// DVPluralForms, once it knows which language it is in.
//
// It had zero/one/other and selected with `count == 1`, so every catalogue was
// really an English catalogue. A French app rendered "0 messages" where French
// writes "0 message", and Polish -- which needs one, few and many, chosen by
// the last one or two digits -- had no way to be written correctly at all.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVPluralForms _english = DVPluralForms(
  one: '{count} message',
  other: '{count} messages',
);

const DVPluralForms _polish = DVPluralForms(
  one: '{count} plik',
  few: '{count} pliki',
  many: '{count} plików',
  other: '{count} pliku',
);

void main() {
  group('selecting a form', () {
    test('english', () {
      expect(_english.select(1, locale: 'en'), '{count} message');
      expect(_english.select(0, locale: 'en'), '{count} messages');
      expect(_english.select(2, locale: 'en'), '{count} messages');
    });

    test('french makes zero singular', () {
      expect(_english.select(0, locale: 'fr'), '{count} message');
      expect(_english.select(2, locale: 'fr'), '{count} messages');
    });

    test('polish uses all three of its forms', () {
      expect(_polish.select(1, locale: 'pl'), '{count} plik');
      expect(_polish.select(3, locale: 'pl'), '{count} pliki');
      expect(_polish.select(5, locale: 'pl'), '{count} plików');
      // The teens exception.
      expect(_polish.select(13, locale: 'pl'), '{count} plików');
      expect(_polish.select(23, locale: 'pl'), '{count} pliki');
    });
  });

  group('a form the catalogue does not provide', () {
    test('falls back to other rather than rendering nothing', () {
      // A Polish catalogue written before anyone knew about `few` should read
      // awkwardly, not produce an empty string.
      const DVPluralForms partial = DVPluralForms(
        one: 'one',
        other: 'other',
      );
      expect(partial.select(3, locale: 'pl'), 'other');
      expect(partial.select(5, locale: 'pl'), 'other');
    });

    test('zero falls through to the language rule when unset', () {
      // `zero` is an explicit override for English-style "no messages", not a
      // CLDR category in most languages. Unset, 0 takes whatever the language
      // says -- other in English, one in French.
      expect(_english.select(0, locale: 'en'), '{count} messages');
      expect(_english.select(0, locale: 'fr'), '{count} message');
    });

    test('an explicit zero wins where it is set', () {
      const DVPluralForms withZero = DVPluralForms(
        zero: 'no messages',
        one: 'one message',
        other: '{count} messages',
      );
      expect(withZero.select(0, locale: 'en'), 'no messages');
    });
  });

  group('what the catalogue is missing', () {
    test('it can report the forms its language needs', () {
      // So strict mode can fail a build rather than shipping a Polish string
      // that silently reads as the wrong word on most numbers.
      expect(_polish.missingFor('pl'), isEmpty);
      expect(
        const DVPluralForms(one: 'a', other: 'b').missingFor('pl'),
        containsAll(<DVPluralCategory>[
          DVPluralCategory.few,
          DVPluralCategory.many,
        ]),
      );
    });

    test('an english catalogue is complete for english', () {
      expect(_english.missingFor('en'), isEmpty);
    });

    test('a single form is complete for japanese', () {
      expect(const DVPluralForms(other: 'x').missingFor('ja'), isEmpty);
    });
  });

  group('through DV.I18n', () {
    setUp(() => const DVI18n().reset());

    test('plural picks by the loaded locale', () {
      const DVTranslationKey files = DVTranslationKey('files.count');
      const DVI18n i18n = DVI18n();
      i18n.load(const DVTranslationCatalog(
        locale: LocaleTag('pl-PL'),
        plurals: <DVTranslationKey, DVPluralForms>{files: _polish},
      ));
      i18n.useLocale(const LocaleTag('pl-PL'));

      expect(const DVI18n().plural(files, 1), '1 plik');
      expect(const DVI18n().plural(files, 3), '3 pliki');
      expect(const DVI18n().plural(files, 5), '5 plików');
    });

    test('the old zero/one/other catalogues still work in english', () {
      // Existing applications must not change behaviour.
      const DVTranslationKey msgs = DVTranslationKey('inbox.count');
      const DVI18n i18n = DVI18n();
      i18n.load(const DVTranslationCatalog(
        locale: LocaleTag.enUS,
        plurals: <DVTranslationKey, DVPluralForms>{msgs: _english},
      ));
      i18n.useLocale(LocaleTag.enUS);

      expect(const DVI18n().plural(msgs, 1), '1 message');
      expect(const DVI18n().plural(msgs, 4), '4 messages');
    });
  });
}
