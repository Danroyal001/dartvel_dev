// A tenant's own default locale.
//
// A multi-tenant application serves companies whose users mostly share a
// language, and the application's fallback -- usually English -- is the wrong
// answer for a French tenant's visitor who sent no Accept-Language. The
// tenant's default sits between the visitor's own signals and the
// application's fallback: it never overrides what a person asked for, and it
// is what they get when they asked for nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVTenants.clearLocaleDefaults);
  tearDown(DVTenants.clearLocaleDefaults);

  const List<String> supported = <String>['en', 'fr', 'de'];

  DVLocaleChoice negotiate({String? acceptLanguage, String? preferred, String? path, String? tenant}) =>
      dvNegotiateLocale(
        supported: supported,
        fallback: 'en',
        acceptLanguage: acceptLanguage,
        preferred: preferred,
        path: path,
        tenantDefault: tenant == null ? null : const DVTenants().localeDefaultFor(tenant),
      );

  group('the registry', () {
    test('a default can be set and read back', () {
      DVTenants.setLocaleDefault('acme', 'fr');
      expect(const DVTenants().localeDefaultFor('acme'), 'fr');
    });

    test('a tenant with no default has none', () {
      expect(const DVTenants().localeDefaultFor('nobody'), isNull);
    });

    test('clearing forgets every default', () {
      DVTenants.setLocaleDefault('acme', 'fr');
      DVTenants.clearLocaleDefaults();
      expect(const DVTenants().localeDefaultFor('acme'), isNull);
    });

    test('the current tenant\'s default is one call', () {
      DVTenants.setLocaleDefault('acme', 'de');
      const DVTenants().currentTenant = 'acme';
      addTearDown(() => const DVTenants().currentTenant = DVTenants.defaultTenant);
      expect(const DVTenants().currentLocaleDefault, 'de');
    });
  });

  group('in negotiation', () {
    setUp(() => DVTenants.setLocaleDefault('acme', 'fr'));

    test('a visitor who asked for nothing gets the tenant\'s language', () {
      final DVLocaleChoice c = negotiate(tenant: 'acme');
      expect(c.locale, 'fr');
      expect(c.source, DVLocaleSource.tenant);
    });

    test('it never overrides what the visitor asked for', () {
      // The tenant is French; this visitor said German. German.
      expect(negotiate(tenant: 'acme', acceptLanguage: 'de').locale, 'de');
      expect(negotiate(tenant: 'acme', preferred: 'de').locale, 'de');
      expect(negotiate(tenant: 'acme', path: '/de/orders').locale, 'de');
    });

    test('but it beats the application fallback', () {
      // Only unsupported requests remain; the tenant default wins over 'en'.
      expect(negotiate(tenant: 'acme', acceptLanguage: 'is').locale, 'fr');
    });

    test('a tenant default the application does not support is skipped', () {
      // A tenant configured for a language whose catalogue was removed must
      // not pin every visitor to a locale nothing can render.
      DVTenants.setLocaleDefault('acme', 'is');
      final DVLocaleChoice c = negotiate(tenant: 'acme');
      expect(c.locale, 'en');
      expect(c.source, DVLocaleSource.fallback);
    });

    test('no tenant default changes nothing', () {
      expect(negotiate(tenant: 'other').source, DVLocaleSource.fallback);
    });
  });
}
