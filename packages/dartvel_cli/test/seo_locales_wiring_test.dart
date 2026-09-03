// hreflang reaching the pages dartvel build web actually writes.
//
// dvSeoHead can write alternates and dvSeoAlternatesFor can build them, and
// neither was called: the prerender wrote every static page with canonical,
// OpenGraph and Twitter and no language. This is the wiring, and the
// configuration it reads: dartvel.i18n.locales and defaultLocale.
import 'package:dartvel_cli/src/build/seo_head.dart';
import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:test/test.dart';

const String shell = '<!doctype html><html><head><title>x</title></head><body></body></html>';

void main() {
  group('reading the locales', () {
    test('locales and the default come from dartvel.i18n', () {
      final DVI18nLocales l = DVI18nLocales.parse(<String, Object?>{
        'i18n': <String, Object?>{'locales': <String>['en', 'fr', 'de'], 'defaultLocale': 'en'},
      });
      expect(l.locales, <String>['en', 'fr', 'de']);
      expect(l.defaultLocale, 'en');
      expect(l.problems, isEmpty);
    });

    test('with no i18n section there is one implicit locale and no alternates', () {
      final DVI18nLocales l = DVI18nLocales.parse(null);
      expect(l.locales, hasLength(1));
      expect(l.problems, isEmpty);
    });

    test('the default locale must be one of the locales', () {
      // A default the site does not have sends x-default to a 404.
      final DVI18nLocales l = DVI18nLocales.parse(<String, Object?>{
        'i18n': <String, Object?>{'locales': <String>['en', 'fr'], 'defaultLocale': 'de'},
      });
      expect(l.problems.single, contains('de'));
    });

    test('with locales but no default, the first is the default', () {
      final DVI18nLocales l = DVI18nLocales.parse(<String, Object?>{
        'i18n': <String, Object?>{'locales': <String>['fr', 'en']},
      });
      expect(l.defaultLocale, 'fr');
    });

    test('a malformed section does not throw', () {
      expect(() => DVI18nLocales.parse(<String, Object?>{'i18n': 'yes'}), returnsNormally);
      expect(() => DVI18nLocales.parse(<String, Object?>{'i18n': <String, Object?>{'locales': 'en'}}), returnsNormally);
    });
  });

  group('the static page', () {
    test('carries hreflang for its route when alternates are given', () {
      final String page = dvStaticPage(
        shell: shell,
        route: '/pricing',
        title: 'Pricing',
        siteUrl: 'https://example.com',
        alternates: <String, String>{
          'en': 'https://example.com/pricing',
          'fr': 'https://example.com/fr/pricing',
        },
        defaultAlternate: 'https://example.com/pricing',
      );
      expect(page, contains('hreflang="fr" href="https://example.com/fr/pricing"'));
      expect(page, contains('hreflang="x-default"'));
    });

    test('and none when it is a single-language site', () {
      final String page = dvStaticPage(shell: shell, route: '/pricing', title: 'Pricing', siteUrl: 'https://example.com');
      expect(page, isNot(contains('hreflang')));
    });
  });

  group('the whole route set', () {
    test('every locale gets a URL and the default is x-default', () {
      final DVI18nLocales l = DVI18nLocales.parse(<String, Object?>{
        'i18n': <String, Object?>{'locales': <String>['en', 'fr'], 'defaultLocale': 'en'},
      });
      final Map<String, String> alternates =
          dvSeoAlternatesFor(siteUrl: 'https://example.com', route: '/pricing', locales: l.locales, defaultLocale: l.defaultLocale);
      expect(alternates['fr'], 'https://example.com/fr/pricing');
      expect(alternates[l.defaultLocale], 'https://example.com/pricing');
    });
  });
}
