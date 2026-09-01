// Choosing which language to answer in.
//
// Listed in the specification as "route locale negotiation" and never built,
// so an application with translated catalogues had no way to pick between
// them: every request got the fallback, and the translations were dead weight.
//
// Everything that can go wrong here is quiet. A q-value read in the wrong
// order serves French to a German speaker; `q=0` honoured as a preference
// serves the one language the client said it could not read; an unknown path
// segment taken for a locale eats the first segment of every URL. None of
// those throw.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const List<String> supported = <String>['en', 'fr', 'de-DE', 'zh-Hant-TW'];

DVLocaleChoice negotiate({
  String? path,
  String? acceptLanguage,
  String? preferred,
}) =>
    dvNegotiateLocale(
      supported: supported,
      fallback: 'en',
      path: path,
      acceptLanguage: acceptLanguage,
      preferred: preferred,
    );

void main() {
  group('precedence', () {
    test('a locale in the path wins over everything', () {
      // It is in the URL the user shared, so it has to survive being opened
      // by someone whose browser prefers another language.
      final DVLocaleChoice c = negotiate(
        path: '/fr/orders',
        acceptLanguage: 'de-DE',
        preferred: 'en',
      );

      expect(c.locale, 'fr');
      expect(c.source, DVLocaleSource.path);
    });

    test('a stored preference beats the browser', () {
      // The user chose it; Accept-Language is what their OS was installed as.
      final DVLocaleChoice c =
          negotiate(acceptLanguage: 'de-DE', preferred: 'fr');

      expect(c.locale, 'fr');
      expect(c.source, DVLocaleSource.preference);
    });

    test('the browser beats the fallback', () {
      expect(negotiate(acceptLanguage: 'fr').locale, 'fr');
    });

    test('with nothing to go on, the fallback', () {
      final DVLocaleChoice c = negotiate();
      expect(c.locale, 'en');
      expect(c.source, DVLocaleSource.fallback);
    });

    test('an unsupported preference does not win', () {
      // Otherwise a stale cookie pins a user to a language that was removed.
      expect(negotiate(acceptLanguage: 'fr', preferred: 'is').locale, 'fr');
    });
  });

  group('the path', () {
    test('the locale segment is stripped from the route', () {
      final DVLocaleChoice c = negotiate(path: '/fr/orders/42');
      expect(c.path, '/orders/42');
    });

    test('a path that is only a locale becomes the root', () {
      expect(negotiate(path: '/fr').path, '/');
    });

    test('an unknown first segment is not a locale', () {
      // /orders must not be read as locale "orders" with an empty path.
      final DVLocaleChoice c = negotiate(path: '/orders');
      expect(c.locale, 'en');
      expect(c.path, '/orders');
      expect(c.source, DVLocaleSource.fallback);
    });

    test('a supported locale is matched case-insensitively', () {
      expect(negotiate(path: '/DE-de/orders').locale, 'de-DE');
    });

    test('the root path carries no locale', () {
      final DVLocaleChoice c = negotiate(path: '/');
      expect(c.path, '/');
      expect(c.source, DVLocaleSource.fallback);
    });
  });

  group('Accept-Language', () {
    test('q-values order the choice, not the written order', () {
      // The header lists de first, and says it means it less.
      expect(negotiate(acceptLanguage: 'de-DE;q=0.3, fr;q=0.9').locale, 'fr');
    });

    test('a missing q means 1, which outranks anything written', () {
      expect(negotiate(acceptLanguage: 'de-DE;q=0.9, fr').locale, 'fr');
    });

    test('q=0 means "not acceptable" and is never chosen', () {
      // Serving it would give the client the one language it said it could
      // not read.
      final DVLocaleChoice c = negotiate(acceptLanguage: 'fr;q=0, de-DE;q=0.1');
      expect(c.locale, 'de-DE');
    });

    test('q=0 on everything falls back', () {
      expect(negotiate(acceptLanguage: 'fr;q=0').locale, 'en');
    });

    test('a region falls back to the language', () {
      // fr-CA is not offered; fr is, and is a better answer than English.
      expect(negotiate(acceptLanguage: 'fr-CA').locale, 'fr');
    });

    test('a bare language matches a supported region', () {
      // de is asked for, de-DE is what exists.
      expect(negotiate(acceptLanguage: 'de').locale, 'de-DE');
    });

    test('a script subtag is kept', () {
      expect(negotiate(acceptLanguage: 'zh-Hant-TW').locale, 'zh-Hant-TW');
      expect(negotiate(acceptLanguage: 'zh-Hant').locale, 'zh-Hant-TW');
    });

    test('* matches nothing in particular, so the fallback stands', () {
      expect(negotiate(acceptLanguage: '*').locale, 'en');
    });

    test('an exact match beats a language-only one at the same weight', () {
      expect(negotiate(acceptLanguage: 'de, de-DE').locale, 'de-DE');
    });

    test('whitespace and case in the header do not matter', () {
      expect(negotiate(acceptLanguage: '  FR ;  Q=0.8 ').locale, 'fr');
    });

    test('a malformed header falls back rather than throwing', () {
      for (final String header in <String>['', ';;;', 'q=', 'fr;q=abc', ',,']) {
        expect(() => negotiate(acceptLanguage: header), returnsNormally,
            reason: header);
      }
      expect(negotiate(acceptLanguage: ';;;').locale, 'en');
    });

    test('an unparseable q is treated as unweighted, not as zero', () {
      // Zero would mean "refuses this language", which the client did not say.
      expect(negotiate(acceptLanguage: 'fr;q=abc').locale, 'fr');
    });
  });

  group('the supported list', () {
    test('an empty one always gives the fallback', () {
      expect(
        dvNegotiateLocale(
                supported: const <String>[], fallback: 'en', acceptLanguage: 'fr')
            .locale,
        'en',
      );
    });

    test('the answer is always one of the supported locales, spelled as they '
        'are', () {
      // A caller looks the catalogue up by this string.
      for (final String header in <String>['de', 'DE-de', 'de-CH', 'zh-Hant']) {
        final String chosen = negotiate(acceptLanguage: header).locale;
        expect(supported, contains(chosen), reason: header);
      }
    });
  });
}
