/// Plural selection, per CLDR.
///
/// The categories a language actually uses are not a style choice. French
/// makes 0 singular. Polish and Russian have four and pick by the last one or
/// two digits, so "2 pliki" and "5 plików" are different words. Arabic has six.
/// Selecting with `count == 1` is English's rule wearing a general name, and an
/// application using it is not slightly off in those languages -- it is wrong
/// on most numbers, invisibly to anyone who only reads the English build.
///
/// The rules here are transcribed from the CLDR plural specification. Only the
/// integer and visible-fraction operands are modelled, which is what the
/// cardinal rules for these languages need.
library dartvel.i18n.plural_rules;

/// The CLDR plural categories.
///
/// A language uses a subset; [dvPluralCategoriesFor] says which, so a
/// catalogue missing a form a language needs can be a build error rather than
/// a string that silently falls back.
enum DVPluralCategory { zero, one, two, few, many, other }

/// The category [count] takes in [locale].
///
/// [locale] may be a full tag: the region is ignored, because plural rules are
/// a property of the language. An unknown language falls back to the English
/// rule rather than throwing -- a missing rule should degrade to a plausible
/// plural, not take the application down mid-render.
DVPluralCategory dvPluralCategory({
  required String locale,
  required num count,
}) {
  final String language = dvLanguageOf(locale);

  // CLDR operates on the absolute value; -1 file is still singular.
  final num n = count.abs();

  // The CLDR operands this needs: i is the integer part, v the number of
  // visible fraction digits. `1.0` has v=0 once it is a double that prints
  // without a fraction, which is why English calls 1.0 singular and 1.5 not.
  final int i = n.floor();
  final int v = _visibleFractionDigits(n);

  switch (language) {
    // One form for every number. Offering "one" here produces a string no
    // speaker would write.
    case 'ja':
    case 'zh':
    case 'ko':
    case 'vi':
    case 'th':
    case 'id':
    case 'ms':
    case 'my':
    case 'lo':
    case 'km':
      return DVPluralCategory.other;

    case 'fr':
    case 'hy':
    case 'ff':
    case 'kab':
      // 0 and 1 are both singular.
      return i == 0 || i == 1 ? DVPluralCategory.one : DVPluralCategory.other;

    case 'pt':
      return i == 0 || i == 1 ? DVPluralCategory.one : DVPluralCategory.other;

    case 'pl':
      if (v == 0 && i == 1) return DVPluralCategory.one;
      if (v == 0 &&
          i % 10 >= 2 &&
          i % 10 <= 4 &&
          !(i % 100 >= 12 && i % 100 <= 14)) {
        return DVPluralCategory.few;
      }
      if (v == 0) return DVPluralCategory.many;
      return DVPluralCategory.other;

    case 'ru':
    case 'uk':
      if (v == 0 && i % 10 == 1 && i % 100 != 11) return DVPluralCategory.one;
      if (v == 0 &&
          i % 10 >= 2 &&
          i % 10 <= 4 &&
          !(i % 100 >= 12 && i % 100 <= 14)) {
        return DVPluralCategory.few;
      }
      if (v == 0) return DVPluralCategory.many;
      return DVPluralCategory.other;

    case 'cs':
    case 'sk':
      if (i == 1 && v == 0) return DVPluralCategory.one;
      if (i >= 2 && i <= 4 && v == 0) return DVPluralCategory.few;
      // A fraction is its own category here, whatever its value.
      if (v != 0) return DVPluralCategory.many;
      return DVPluralCategory.other;

    case 'ar':
      if (n == 0) return DVPluralCategory.zero;
      if (n == 1) return DVPluralCategory.one;
      if (n == 2) return DVPluralCategory.two;
      final int mod100 = i % 100;
      if (mod100 >= 3 && mod100 <= 10) return DVPluralCategory.few;
      if (mod100 >= 11 && mod100 <= 99) return DVPluralCategory.many;
      return DVPluralCategory.other;

    case 'lt':
      if (i % 10 == 1 && !(i % 100 >= 11 && i % 100 <= 19)) {
        return DVPluralCategory.one;
      }
      if (i % 10 >= 2 &&
          i % 10 <= 9 &&
          !(i % 100 >= 11 && i % 100 <= 19)) {
        return DVPluralCategory.few;
      }
      if (v != 0) return DVPluralCategory.many;
      return DVPluralCategory.other;

    case 'ro':
      if (i == 1 && v == 0) return DVPluralCategory.one;
      if (v != 0 || n == 0 || (n != 1 && i % 100 >= 1 && i % 100 <= 19)) {
        return DVPluralCategory.few;
      }
      return DVPluralCategory.other;

    // en, de, es, it, nl, sv, da, nb, fi, et, and the rest of the
    // one/other languages.
    default:
      return i == 1 && v == 0 ? DVPluralCategory.one : DVPluralCategory.other;
  }
}

/// Which categories [locale] uses.
///
/// So a catalogue can be validated: a Polish catalogue missing `few` is a
/// build error rather than a string that silently falls back to `other`.
Set<DVPluralCategory> dvPluralCategoriesFor(String locale) {
  switch (dvLanguageOf(locale)) {
    case 'ja':
    case 'zh':
    case 'ko':
    case 'vi':
    case 'th':
    case 'id':
    case 'ms':
    case 'my':
    case 'lo':
    case 'km':
      return <DVPluralCategory>{DVPluralCategory.other};

    case 'pl':
    case 'ru':
    case 'uk':
      return <DVPluralCategory>{
        DVPluralCategory.one,
        DVPluralCategory.few,
        DVPluralCategory.many,
        DVPluralCategory.other,
      };

    case 'cs':
    case 'sk':
    case 'lt':
      return <DVPluralCategory>{
        DVPluralCategory.one,
        DVPluralCategory.few,
        DVPluralCategory.many,
        DVPluralCategory.other,
      };

    case 'ro':
      return <DVPluralCategory>{
        DVPluralCategory.one,
        DVPluralCategory.few,
        DVPluralCategory.other,
      };

    case 'ar':
      return DVPluralCategory.values.toSet();

    default:
      return <DVPluralCategory>{DVPluralCategory.one, DVPluralCategory.other};
  }
}

/// The language subtag of [locale], lower-cased.
///
/// Both separators are accepted because both are in the wild: BCP 47 writes
/// `fr-CA` and Dart's Locale prints `fr_CA`.
String dvLanguageOf(String locale) {
  final String trimmed = locale.trim().toLowerCase();
  for (int i = 0; i < trimmed.length; i += 1) {
    final String c = trimmed[i];
    if (c == '-' || c == '_') return trimmed.substring(0, i);
  }
  return trimmed;
}

/// How many fraction digits [n] shows.
///
/// The CLDR `v` operand. It is about the printed form rather than the value:
/// 1.0 shows none and counts as an integer, 1.50 shows two.
int _visibleFractionDigits(num n) {
  if (n is int) return 0;
  final String text = n.toString();
  final int dot = text.indexOf('.');
  if (dot < 0) return 0;
  final String fraction = text.substring(dot + 1);
  // Dart prints a whole double as "1.0"; that is not a visible fraction digit
  // in the CLDR sense, and treating it as one makes every integer-valued
  // double take the plural.
  if (fraction == '0') return 0;
  return fraction.length;
}
