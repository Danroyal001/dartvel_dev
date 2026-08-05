import 'package:dartvel_core/dartvel.dart';
// The middleware library is not part of the barrel, so the tenant middleware
// is reached the way middleware_test.dart reaches the rest of it.
import 'package:dartvel_core/src/middleware/middleware.dart';
import 'package:test/test.dart';

void main() {
  const DVTenants tenants = DVTenants();

  tearDown(DVTenants.reset);

  group('resolution', () {
    test('reads a subdomain by default', () {
      expect(
        tenants.resolve(Uri.parse('https://acme.example.com/orders')),
        'acme',
      );
    });

    test('an apex domain and localhost name no tenant', () {
      // `example.com` is the site itself, not a tenant called "example".
      expect(tenants.resolve(Uri.parse('https://example.com/orders')), isNull);
      expect(tenants.resolve(Uri.parse('http://localhost:8080/')), isNull);
    });

    test('www is the site, not a tenant', () {
      expect(tenants.resolve(Uri.parse('https://www.example.com/')), isNull);
    });

    test('reads a header when configured', () {
      tenants.configure(source: DVTenantSource.header);

      expect(
        tenants.resolve(
          Uri.parse('https://example.com/'),
          headers: <String, String>{'X-Tenant': 'acme'},
        ),
        'acme',
      );
      // Header names are case-insensitive on the wire.
      expect(
        tenants.resolve(
          Uri.parse('https://example.com/'),
          headers: <String, String>{'x-tenant': 'acme'},
        ),
        'acme',
      );
    });

    test('reads a path prefix when configured', () {
      tenants.configure(source: DVTenantSource.pathPrefix);

      expect(
        tenants.resolve(Uri.parse('https://example.com/acme/orders')),
        'acme',
      );
      expect(tenants.resolve(Uri.parse('https://example.com/')), isNull);
    });

    test('reads a query parameter when configured', () {
      tenants.configure(
        source: DVTenantSource.queryParameter,
        queryParameterName: 'org',
      );

      expect(
        tenants.resolve(Uri.parse('https://example.com/?org=acme')),
        'acme',
      );
    });

    test('a custom resolver overrides the source', () {
      tenants.configure(
        resolver: (Uri uri, Map<String, String> headers) =>
            headers['authorization'] == 'token-acme' ? 'acme' : null,
      );

      expect(
        tenants.resolve(
          Uri.parse('https://other.example.com/'),
          headers: <String, String>{'authorization': 'token-acme'},
        ),
        'acme',
      );
      expect(tenants.resolve(Uri.parse('https://acme.example.com/')), isNull);
    });

    test('an empty value is no tenant rather than an empty tenant', () {
      tenants.configure(source: DVTenantSource.header);

      expect(
        tenants.resolve(
          Uri.parse('https://example.com/'),
          headers: <String, String>{'x-tenant': '   '},
        ),
        isNull,
      );
    });
  });

  group('current tenant', () {
    test('adopt falls back to the default when nothing resolves', () {
      expect(tenants.adopt(Uri.parse('https://example.com/')), 'default');
      expect(tenants.currentTenant, 'default');

      expect(tenants.adopt(Uri.parse('https://acme.example.com/')), 'acme');
      expect(tenants.currentTenant, 'acme');
    });

    test('withTenant restores the previous tenant, even on a throw', () {
      tenants.currentTenant = 'acme';

      expect(
        () => tenants.withTenant('other', () => throw StateError('boom')),
        throwsStateError,
      );
      expect(tenants.currentTenant, 'acme');
    });

    test('an empty tenant falls back to the default', () {
      tenants.currentTenant = '  ';

      expect(tenants.currentTenant, 'default');
    });
  });

  group('isolation', () {
    test('a shared database has nothing to qualify', () {
      expect(tenants.qualifierFor('acme'), isNull);
    });

    test('per-schema and per-database isolation qualify by tenant', () {
      tenants.configure(isolation: DVTenantIsolation.schemaPerTenant);
      expect(tenants.qualifierFor('acme'), 'dartvel_acme');

      tenants.configure(isolation: DVTenantIsolation.databasePerTenant);
      expect(tenants.qualifierFor('acme', base: 'app'), 'app_acme');
    });

    test('a qualifier is a plain identifier, not whatever the tenant is', () {
      // Tenant ids reach SQL identifiers here, so they cannot pass through.
      tenants.configure(isolation: DVTenantIsolation.schemaPerTenant);

      expect(tenants.qualifierFor('Acme Corp.'), 'dartvel_acme_corp');
      expect(
        tenants.qualifierFor('a"; DROP TABLE users; --'),
        'dartvel_a_drop_table_users',
      );
      expect(
        () => tenants.qualifierFor('!!!'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('middleware', () {
    test('makes the request tenant current', () async {
      final chain = MiddlewareChain()..use(CommonMiddleware.tenant());

      final context = await chain.execute(
        Uri.parse('https://acme.example.com/orders'),
      );

      expect(context.shouldContinue, isTrue);
      expect(context.data['tenant'], 'acme');
      expect(tenants.currentTenant, 'acme');
    });

    test('require aborts rather than serving the default tenant', () async {
      final chain = MiddlewareChain()
        ..use(CommonMiddleware.tenant(require: true));

      final context = await chain.execute(Uri.parse('https://example.com/'));

      expect(context.shouldContinue, isFalse);
      expect(context.data['tenantError'], contains('No tenant'));
    });

    test('resolves from a header on a map-shaped request', () async {
      tenants.configure(source: DVTenantSource.header);
      final chain = MiddlewareChain()..use(CommonMiddleware.tenant());

      final context = await chain.execute(<String, Object?>{
        'url': 'https://example.com/orders',
        'headers': <String, String>{'X-Tenant': 'acme'},
      });

      expect(context.data['tenant'], 'acme');
    });
  });
}
