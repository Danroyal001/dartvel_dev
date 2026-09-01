// Plural selection, per CLDR, for languages that are not English.
//
// DVPluralForms offered zero/one/other and selected with `count == 1`. That is
// English's rule wearing a general name. French makes 0 singular. Polish and
// Russian have four categories and pick by the last one or two digits, so
// "2 pliki" and "5 plików" are different words. Arabic has six.
//
// An application using the old rules is not slightly off in those languages,
// it is wrong on most numbers -- and the failure is invisible to anyone who
// only reads the English build.
//
// The cases below are the ones CLDR itself documents, chosen where the naive
// English rule gives a different answer.
import 'package:dartvel_core/src/i18n/plural_rules.dart';
import 'package:test/test.dart';

DVPluralCategory pick(String locale, num n) =>
    dvPluralCategory(locale: locale, count: n);

void main() {
  group('english', () {
    test('one is one, everything else is other', () {
      expect(pick('en', 1), DVPluralCategory.one);
      expect(pick('en', 0), DVPluralCategory.other);
      expect(pick('en', 2), DVPluralCategory.other);
      expect(pick('en', 21), DVPluralCategory.other);
    });

    test('a decimal is other even when it reads as one', () {
      // "1.0 files" takes the plural in English. The CLDR rule is i=1 and v=0
      // -- an integer one with no visible fraction digits.
      expect(pick('en', 1.0), DVPluralCategory.one);
      expect(pick('en', 1.5), DVPluralCategory.other);
    });
  });

  group('french', () {
    test('zero is singular', () {
      // The case the English rule gets wrong on the very first number:
      // French writes "0 message", not "0 messages".
      expect(pick('fr', 0), DVPluralCategory.one);
      expect(pick('fr', 1), DVPluralCategory.one);
      expect(pick('fr', 2), DVPluralCategory.other);
    });
  });

  group('polish', () {
    test('it has one, few and many', () {
      expect(pick('pl', 1), DVPluralCategory.one);
      expect(pick('pl', 2), DVPluralCategory.few);
      expect(pick('pl', 3), DVPluralCategory.few);
      expect(pick('pl', 4), DVPluralCategory.few);
      expect(pick('pl', 5), DVPluralCategory.many);
      expect(pick('pl', 0), DVPluralCategory.many);
    });

    test('the teens are many, not few', () {
      // 12..14 are the exception the modulo rule exists for. Without it, 12
      // reads as few because 12 % 10 == 2.
      expect(pick('pl', 12), DVPluralCategory.many);
      expect(pick('pl', 13), DVPluralCategory.many);
      expect(pick('pl', 14), DVPluralCategory.many);
      expect(pick('pl', 22), DVPluralCategory.few);
      expect(pick('pl', 112), DVPluralCategory.many);
      expect(pick('pl', 122), DVPluralCategory.few);
    });
  });

  group('russian', () {
    test('one comes back round at 21', () {
      expect(pick('ru', 1), DVPluralCategory.one);
      expect(pick('ru', 21), DVPluralCategory.one);
      expect(pick('ru', 101), DVPluralCategory.one);
      // But not 11, which is many.
      expect(pick('ru', 11), DVPluralCategory.many);
      expect(pick('ru', 111), DVPluralCategory.many);
    });

    test('few and many', () {
      expect(pick('ru', 2), DVPluralCategory.few);
      expect(pick('ru', 4), DVPluralCategory.few);
      expect(pick('ru', 5), DVPluralCategory.many);
      expect(pick('ru', 0), DVPluralCategory.many);
      expect(pick('ru', 12), DVPluralCategory.many);
      expect(pick('ru', 22), DVPluralCategory.few);
    });
  });

  group('arabic', () {
    test('all six categories', () {
      expect(pick('ar', 0), DVPluralCategory.zero);
      expect(pick('ar', 1), DVPluralCategory.one);
      expect(pick('ar', 2), DVPluralCategory.two);
      expect(pick('ar', 3), DVPluralCategory.few);
      expect(pick('ar', 10), DVPluralCategory.few);
      expect(pick('ar', 11), DVPluralCategory.many);
      expect(pick('ar', 99), DVPluralCategory.many);
      expect(pick('ar', 100), DVPluralCategory.other);
    });
  });

  group('languages with no plural at all', () {
    test('japanese, chinese, korean, vietnamese, thai', () {
      // One form for every number. Offering "one" here produces a string no
      // speaker would write.
      for (final String locale in <String>['ja', 'zh', 'ko', 'vi', 'th']) {
        for (final num n in <num>[0, 1, 2, 5, 100]) {
          expect(pick(locale, n), DVPluralCategory.other,
              reason: '$locale $n');
        }
      }
    });
  });

  group('czech', () {
    test('a fraction is many, whatever its value', () {
      expect(pick('cs', 1), DVPluralCategory.one);
      expect(pick('cs', 2), DVPluralCategory.few);
      expect(pick('cs', 4), DVPluralCategory.few);
      expect(pick('cs', 5), DVPluralCategory.other);
      expect(pick('cs', 1.5), DVPluralCategory.many);
    });
  });

  group('the locale tag itself', () {
    test('a region is ignored, the language decides', () {
      expect(pick('fr-FR', 0), DVPluralCategory.one);
      expect(pick('fr_CA', 0), DVPluralCategory.one);
      expect(pick('pt-BR', 1), DVPluralCategory.one);
    });

    test('case does not matter', () {
      expect(pick('FR', 0), DVPluralCategory.one);
      expect(pick('Pl', 2), DVPluralCategory.few);
    });

    test('an unknown language falls back to english rather than throwing', () {
      // A missing rule should degrade to a plausible plural, not take the
      // application down mid-render.
      expect(pick('xx', 1), DVPluralCategory.one);
      expect(pick('xx', 2), DVPluralCategory.other);
    });
  });

  group('negative and large numbers', () {
    test('the sign is ignored', () {
      // CLDR operates on the absolute value; -1 file is still singular.
      expect(pick('en', -1), DVPluralCategory.one);
      expect(pick('pl', -2), DVPluralCategory.few);
    });
  });

  test('every supported language reports which categories it uses', () {
    // So a catalogue can be validated: a Polish catalogue missing `few` is a
    // build error, not a string that silently falls back to `other`.
    expect(dvPluralCategoriesFor('en'),
        <DVPluralCategory>{DVPluralCategory.one, DVPluralCategory.other});
    expect(dvPluralCategoriesFor('ja'), <DVPluralCategory>{DVPluralCategory.other});
    expect(
      dvPluralCategoriesFor('pl'),
      <DVPluralCategory>{
        DVPluralCategory.one,
        DVPluralCategory.few,
        DVPluralCategory.many,
        DVPluralCategory.other,
      },
    );
  });
}
