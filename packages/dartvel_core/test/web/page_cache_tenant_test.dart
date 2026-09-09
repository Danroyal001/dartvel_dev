// A kept page belongs to the tenant it was resolved for.
//
// The cache was keyed on the request path alone. Under the subdomain source
// the spec lists first, acme.example.com/orders and globex.example.com/orders
// are the same path, so the first tenant to ask populated the entry and every
// other tenant was served that tenant's title, description, structured data
// and crawler text for as long as the ttl lasted.
//
// It cost nothing to reach: no login, no crafted request, just two customers
// on one server.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVPageData _page(String title) => DVPageData(title: title);

void main() {
  tearDown(DVTenants.reset);

  test('two tenants asking for one path get their own page', () async {
    final DVPageDataCache cache = DVPageDataCache();
    const DVTenants tenants = DVTenants();
    const DVPageRequest request = DVPageRequest(
      path: '/orders',
      pattern: '/orders',
      params: <String, String>{},
    );

    Future<DVPageData?> serve(String tenant) => tenants.withTenant(
          tenant,
          () => cache.resolve(
            request,
            (DVPageRequest r) async => _page('Orders for $tenant'),
            DVPageDataMode.cache,
          ),
        );

    expect((await serve('acme'))?.title, 'Orders for acme');
    expect((await serve('globex'))?.title, 'Orders for globex');
    // And the first tenant's page is still its own, rather than having been
    // replaced by the second one's.
    expect((await serve('acme'))?.title, 'Orders for acme');
  });

  test('a tenant is still served its own kept page rather than resolving again',
      () async {
    // Keeping pages apart by tenant is worth nothing if it is done by never
    // keeping any: this fails if the fix were to disable the cache.
    final DVPageDataCache cache = DVPageDataCache();
    const DVTenants tenants = DVTenants();
    const DVPageRequest request = DVPageRequest(
      path: '/orders',
      pattern: '/orders',
      params: <String, String>{},
    );
    int resolved = 0;

    Future<DVPageData?> serve() => tenants.withTenant(
          'acme',
          () => cache.resolve(
            request,
            (DVPageRequest r) async {
              resolved++;
              return _page('Orders');
            },
            DVPageDataMode.cache,
          ),
        );

    await serve();
    await serve();

    expect(resolved, 1);
  });

  test('a stale page is refreshed for the tenant that asked', () async {
    // Stale-while-revalidate refreshes behind the response, and the refresh
    // runs after the request has returned. Writing what it resolves under a
    // key built from whoever is current by then would file acme's refreshed
    // page under whichever tenant happened to be in flight.
    DateTime now = DateTime.utc(2026, 1, 1);
    final DVPageDataCache cache = DVPageDataCache(
      ttl: const Duration(seconds: 1),
      staleFor: const Duration(minutes: 10),
      now: () => now,
    );
    const DVTenants tenants = DVTenants();
    const DVPageRequest request = DVPageRequest(
      path: '/orders',
      pattern: '/orders',
      params: <String, String>{},
    );

    Future<DVPageData?> serve(String tenant, String title) => tenants.withTenant(
          tenant,
          () => cache.resolve(
            request,
            (DVPageRequest r) async => _page(title),
            DVPageDataMode.staleWhileRevalidate,
          ),
        );

    await serve('acme', 'Orders v1');
    now = now.add(const Duration(seconds: 5));
    // Serves the stale page and refreshes behind it.
    await serve('acme', 'Orders v2');
    // Let the refresh land.
    await Future<void>.delayed(Duration.zero);

    expect((await serve('acme', 'Orders v3'))?.title, 'Orders v2');
  });
}
