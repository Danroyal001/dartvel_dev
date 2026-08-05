// The spec's cache section: locks, stampede protection, tenant-aware keys,
// global helpers and stale-while-revalidate. Driven through DV.Cache against
// the real adapters — behaviour, not shape.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DV.Cache.configure(DVMemoryCacheAdapter());
    DVTenants.reset();
  });

  group('remember (stampede protection)', () {
    test('concurrent callers share one compute', () async {
      var computes = 0;
      Future<String> compute() async {
        computes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'value';
      }

      final results = await Future.wait(<Future<String>>[
        DV.Cache.remember('expensive', const Duration(minutes: 1), compute),
        DV.Cache.remember('expensive', const Duration(minutes: 1), compute),
        DV.Cache.remember('expensive', const Duration(minutes: 1), compute),
      ]);

      expect(results, everyElement('value'));
      expect(computes, 1, reason: 'a stampede would have computed three times');
    });

    test('a cached value skips the compute entirely', () async {
      await DV.Cache.set('warm', 'cached');
      var computed = false;

      final result = await DV.Cache.remember<String>(
        'warm',
        null,
        () async {
          computed = true;
          return 'fresh';
        },
      );

      expect(result, 'cached');
      expect(computed, isFalse);
    });

    test('a throwing compute does not wedge the key', () async {
      await expectLater(
        DV.Cache.remember<String>('bad', null, () async => throw StateError('x')),
        throwsStateError,
      );

      // The in-flight slot must have been cleared, or this second call would
      // await the failed future forever.
      final recovered = await DV.Cache.remember<String>(
        'bad',
        null,
        () async => 'ok',
      );
      expect(recovered, 'ok');
    });
  });

  group('locks', () {
    test('a held lock refuses a second acquirer until released', () async {
      final first = await DV.Cache.lock('checkout');
      expect(first, isNotNull);

      expect(await DV.Cache.lock('checkout'), isNull);

      await first!.release();
      expect(await DV.Cache.lock('checkout'), isNotNull);
    });

    test('an expired lock can be re-acquired', () async {
      final held = await DV.Cache.lock(
        'short',
        ttl: const Duration(milliseconds: 10),
      );
      expect(held, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The first holder crashed conceptually; the TTL bounds the damage.
      expect(await DV.Cache.lock('short'), isNotNull);
    });

    test('releasing an expired lock does not tear down its successor',
        () async {
      final first = await DV.Cache.lock(
        'handoff',
        ttl: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final second = await DV.Cache.lock('handoff');
      expect(second, isNotNull);

      await first!.release();

      // The second holder's lock must still be in force.
      expect(await DV.Cache.lock('handoff'), isNull);
    });
  });

  group('tenant-aware keys', () {
    test('tenants do not see each other\'s entries', () async {
      const tenants = DVTenants();

      await tenants.withTenant('acme', () async {
        await DV.Cache.set('users:list', 'acme-users');
      });
      await tenants.withTenant('globex', () async {
        await DV.Cache.set('users:list', 'globex-users');
      });

      final acme = await tenants.withTenant(
        'acme',
        () => DV.Cache.get<String>('users:list'),
      );
      final globex = await tenants.withTenant(
        'globex',
        () => DV.Cache.get<String>('users:list'),
      );
      expect(acme, 'acme-users');
      expect(globex, 'globex-users');
      // The default tenant sees neither.
      expect(await DV.Cache.get<String>('users:list'), isNull);
    });

    test('revalidating a tag removes only the tagging tenant\'s keys',
        () async {
      const tenants = DVTenants();

      await tenants.withTenant('acme', () async {
        await DV.Cache.set('users:list', 'acme-users');
        DV.Cache.tag('users:list', <String>['users']);
      });
      await tenants.withTenant('globex', () async {
        await DV.Cache.set('users:list', 'globex-users');
      });

      await DV.Cache.revalidateTag('users');

      expect(
        await tenants.withTenant(
          'acme',
          () => DV.Cache.get<String>('users:list'),
        ),
        isNull,
      );
      expect(
        await tenants.withTenant(
          'globex',
          () => DV.Cache.get<String>('users:list'),
        ),
        'globex-users',
      );
    });
  });

  group('global helpers', () {
    test('throw with a named fix until a global cache is configured', () {
      expect(
        () => DV.Cache.globalGet<String>('key'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('configureGlobal'),
          ),
        ),
      );
    });

    test('use their own adapter, separate from the per-client cache',
        () async {
      DV.Cache.configureGlobal(DVMemoryCacheAdapter());

      await DV.Cache.globalSet('shared', 'everyone');
      DV.Cache.globalTag('shared', <String>['broadcast']);

      expect(await DV.Cache.globalGet<String>('shared'), 'everyone');
      // Not visible through the per-client cache.
      expect(await DV.Cache.get<String>('shared'), isNull);

      final removed = await DV.Cache.globalRevalidateTag('broadcast');
      expect(removed, isNotEmpty);
      expect(await DV.Cache.globalGet<String>('shared'), isNull);
    });
  });

  group('stale-while-revalidate', () {
    test('serves stale immediately and refreshes once in the background',
        () async {
      var computes = 0;
      Future<String> compute() async => 'v${++computes}';

      final first = await DV.Cache.staleWhileRevalidate<String>(
        'feed',
        ttl: const Duration(milliseconds: 10),
        staleFor: const Duration(minutes: 1),
        compute: compute,
      );
      expect(first, 'v1');

      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Past the stored freshness but inside the stale window: the stale
      // value comes back without waiting on the refresh. Staleness is judged
      // from the stored entry; this call's ttl governs the refreshed one.
      final stale = await DV.Cache.staleWhileRevalidate<String>(
        'feed',
        ttl: const Duration(minutes: 1),
        staleFor: const Duration(minutes: 1),
        compute: compute,
      );
      expect(stale, 'v1');

      // Let the background refresh land, then the fresh value is served.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final fresh = await DV.Cache.staleWhileRevalidate<String>(
        'feed',
        ttl: const Duration(minutes: 1),
        staleFor: const Duration(minutes: 1),
        compute: compute,
      );
      expect(fresh, 'v2');
      expect(computes, 2);
    });

    test('a fully expired entry recomputes in the foreground', () async {
      var computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await DV.Cache.staleWhileRevalidate<String>(
        'gone',
        ttl: const Duration(milliseconds: 5),
        staleFor: const Duration(milliseconds: 5),
        compute: compute,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Past ttl + staleFor the adapter has dropped it: nothing stale exists
      // to serve, so the caller waits for a real value.
      final value = await DV.Cache.staleWhileRevalidate<String>(
        'gone',
        ttl: const Duration(minutes: 1),
        staleFor: const Duration(minutes: 1),
        compute: compute,
      );
      expect(value, 'v2');
    });
  });
}
