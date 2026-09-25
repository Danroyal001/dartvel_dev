// DV.Cache as an application uses it: five CRUD calls, then remember with
// tags and a stale window, revalidation by tag, and a lock that runs a body.
// Driven through the real adapters, on the server's DV -- behaviour, not
// shape.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    const DVCache().configure(DVMemoryCacheAdapter());
    const DVTestHarness().resetCacheTags();
    DVTenants.reset();
  });

  group('the five calls', () {
    test('set, get, has, delete and clear', () async {
      await DV.Cache.set('greeting', 'hello');

      expect(await DV.Cache.get<String>('greeting'), 'hello');
      expect(await DV.Cache.has('greeting'), isTrue);

      await DV.Cache.delete('greeting');
      expect(await DV.Cache.get<String>('greeting'), isNull);
      expect(await DV.Cache.has('greeting'), isFalse);

      await DV.Cache.set('a', 1);
      await DV.Cache.set('b', 2);
      await DV.Cache.clear();
      expect(await DV.Cache.has('a'), isFalse);
      expect(await DV.Cache.has('b'), isFalse);
    });

    test('a ttl is named, and an expired key is absent', () async {
      await DV.Cache.set('short', 'v', ttl: const Duration(milliseconds: 20));
      expect(await DV.Cache.has('short'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await DV.Cache.has('short'), isFalse);
      expect(await DV.Cache.get<String>('short'), isNull);
    });

    test('get of the wrong type is a miss rather than a cast error', () async {
      await DV.Cache.set('count', 3);
      expect(await DV.Cache.get<String>('count'), isNull);
      expect(await DV.Cache.get<int>('count'), 3);
    });

    test('set takes tags, and revalidating one drops the key', () async {
      await DV.Cache.set('products:names', <String>['kit'],
          tags: <String>['products']);
      await DV.Cache.set('orders:open', 4, tags: <String>['orders']);

      final Set<String> dropped = await DV.Cache.revalidateTag('products');

      expect(dropped, <String>{'products:names'});
      expect(await DV.Cache.has('products:names'), isFalse);
      expect(await DV.Cache.get<int>('orders:open'), 4);
    });

    test('tag adds tags to an entry that already exists', () async {
      await DV.Cache.set('users:list', 'everyone');
      DV.Cache.tag('users:list', <String>['users']);

      await DV.Cache.revalidateTag('users');
      expect(await DV.Cache.has('users:list'), isFalse);
    });

    test('the server DV.Cache and DVCache are one cache', () async {
      await DV.Cache.set('shared', 'one');
      expect(await const DVCache().get<String>('shared'), 'one');
    });

    test('configure swaps the store behind every call', () async {
      final DVMemoryCacheAdapter store = DVMemoryCacheAdapter();
      const DVCache().configure(store);

      await DV.Cache.set('k', 'v');
      expect(await store.read('k'), 'v');
    });
  });

  group('remember', () {
    test('computes on a miss and serves the stored value after', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      expect(await DV.Cache.remember<String>('k', compute), 'v1');
      expect(await DV.Cache.remember<String>('k', compute), 'v1');
      expect(computes, 1);
      expect(await DV.Cache.get<String>('k'), 'v1');
    });

    test('ttl is named and bounds how long the value is reused', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await DV.Cache.remember<String>('k', compute,
          ttl: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        await DV.Cache.remember<String>('k', compute,
            ttl: const Duration(milliseconds: 20)),
        'v2',
      );
    });

    test('tags are a parameter: revalidating one makes it compute again',
        () async {
      int computes = 0;
      Future<List<String>> compute() async => <String>['kit ${++computes}'];

      await DV.Cache.remember<List<String>>('products:names', compute,
          tags: <String>['products']);
      await DV.Cache.revalidateTag('products');
      final List<String> again = await DV.Cache.remember<List<String>>(
          'products:names', compute,
          tags: <String>['products']);

      expect(again, <String>['kit 2']);
      expect(computes, 2);
    });

    test('concurrent callers share one compute', () async {
      int computes = 0;
      Future<String> compute() async {
        computes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'value';
      }

      final List<String> results = await Future.wait(<Future<String>>[
        DV.Cache.remember('expensive', compute),
        DV.Cache.remember('expensive', compute),
        DV.Cache.remember('expensive', compute),
      ]);

      expect(results, everyElement('value'));
      expect(computes, 1, reason: 'a stampede would have computed three times');
    });

    test('a value already set skips the compute', () async {
      await DV.Cache.set('warm', 'cached');
      bool computed = false;

      final String result = await DV.Cache.remember<String>('warm', () async {
        computed = true;
        return 'fresh';
      });

      expect(result, 'cached');
      expect(computed, isFalse);
    });

    test('a throwing compute is not cached and does not wedge the key',
        () async {
      await expectLater(
        DV.Cache.remember<String>('bad', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await DV.Cache.remember<String>('bad', () async => 'ok'), 'ok');
    });

    test('a list read back from a JSON store is a hit, not a recompute',
        () async {
      // A database, Redis or Memcached store hands back List<dynamic>. Read
      // as List<String> that used to be a type miss, so remember computed
      // on every call against any store but memory -- a cache that never
      // caches, and nothing says so.
      const DVCache()
          .configure(DVDatabaseCacheAdapter(MemoryDVDatabaseAdapter()));
      int computes = 0;
      Future<List<String>> compute() async {
        computes++;
        return <String>['kit'];
      }

      await DV.Cache.remember<List<String>>('names', compute);
      final List<String> second =
          await DV.Cache.remember<List<String>>('names', compute);

      expect(second, <String>['kit']);
      expect(computes, 1);
      expect(await DV.Cache.get<List<String>>('names'), <String>['kit']);
    });
  });

  group('remember with staleFor', () {
    test('serves the stale value at once and refreshes it once behind',
        () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      expect(
        await DV.Cache.remember<String>('feed', compute,
            ttl: const Duration(milliseconds: 10),
            staleFor: const Duration(minutes: 1)),
        'v1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final List<String> stale = await Future.wait(<Future<String>>[
        DV.Cache.remember<String>('feed', compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1)),
        DV.Cache.remember<String>('feed', compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1)),
      ]);
      expect(stale, everyElement('v1'));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await DV.Cache.remember<String>('feed', compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1)),
        'v2',
      );
      expect(computes, 2, reason: 'two stale readers share one refresh');
    });

    test('past ttl and staleFor the caller waits for a real value', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await DV.Cache.remember<String>('gone', compute,
          ttl: const Duration(milliseconds: 5),
          staleFor: const Duration(milliseconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        await DV.Cache.remember<String>('gone', compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1)),
        'v2',
      );
    });

    test('the key holds the plain value, so get reads it', () async {
      await DV.Cache.remember<String>('feed', () async => 'value',
          ttl: const Duration(minutes: 1),
          staleFor: const Duration(minutes: 1));

      expect(await DV.Cache.get<String>('feed'), 'value');
    });

    test('staleWhileRevalidate, the old name, still works', () async {
      // ignore: deprecated_member_use_from_same_package
      final String value = await DV.Cache.staleWhileRevalidate<String>(
        'old',
        ttl: const Duration(minutes: 1),
        compute: () async => 'value',
      );
      expect(value, 'value');
      expect(await DV.Cache.get<String>('old'), 'value');
    });
  });

  group('lock', () {
    test('runs the body under the lock and returns what it returns',
        () async {
      final int? result = await DV.Cache.lock<int>('report', () async => 42);
      expect(result, 42);
    });

    test('a second caller is refused while the body runs', () async {
      final Completer<void> inside = Completer<void>();
      final Completer<void> finish = Completer<void>();
      final Future<String?> first = DV.Cache.lock<String>('report', () async {
        inside.complete();
        await finish.future;
        return 'first';
      });
      await inside.future;

      bool ran = false;
      final String? second = await DV.Cache.lock<String>('report', () async {
        ran = true;
        return 'second';
      });

      expect(second, isNull);
      expect(ran, isFalse);
      finish.complete();
      expect(await first, 'first');
    });

    test('the lock is released after the body, so the next caller runs',
        () async {
      await DV.Cache.lock<void>('report', () async {});
      expect(await DV.Cache.lock<String>('report', () async => 'next'), 'next');
    });

    test('a body that throws still releases the lock', () async {
      await expectLater(
        DV.Cache.lock<void>('report', () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await DV.Cache.lock<String>('report', () async => 'again'),
          'again');
    });

    test('wait: waits for the holder to finish, then runs', () async {
      final Completer<void> inside = Completer<void>();
      final Future<void> holder = DV.Cache.lock<void>('report', () async {
        inside.complete();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await inside.future;

      final String? waited = await DV.Cache.lock<String>(
        'report',
        () async => 'after',
        wait: const Duration(seconds: 2),
      );

      expect(waited, 'after');
      await holder;
    });

    test('wait: gives up with null when the holder outlasts it', () async {
      final Completer<void> inside = Completer<void>();
      final Completer<void> finish = Completer<void>();
      final Future<void> holder = DV.Cache.lock<void>('report', () async {
        inside.complete();
        await finish.future;
      });
      await inside.future;

      final String? gaveUp = await DV.Cache.lock<String>(
        'report',
        () async => 'never',
        wait: const Duration(milliseconds: 40),
      );

      expect(gaveUp, isNull);
      finish.complete();
      await holder;
    });

    test('a holder that died frees the lock when its ttl runs out', () async {
      // A process that crashed mid-body never releases; the ttl is what
      // bounds how long it can wedge the lock.
      final Completer<void> never = Completer<void>();
      unawaited(DV.Cache.lock<void>('report', () => never.future,
          ttl: const Duration(milliseconds: 20)));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await DV.Cache.lock<String>('report', () async => 'free'),
          'free');
    });

    test('a lock does not use up the key of the same name', () async {
      await DV.Cache.set('report', 'cached');
      expect(await DV.Cache.lock<String>('report', () async => 'ran'), 'ran');
      expect(await DV.Cache.get<String>('report'), 'cached');
    });
  });

  group('tenant-aware keys', () {
    test('tenants do not see each other\'s entries', () async {
      const DVTenants tenants = DVTenants();
      await tenants.withTenant('acme', () => DV.Cache.set('k', 'acme'));
      await tenants.withTenant('globex', () => DV.Cache.set('k', 'globex'));

      expect(await tenants.withTenant('acme', () => DV.Cache.get<String>('k')),
          'acme');
      expect(
          await tenants.withTenant('globex', () => DV.Cache.get<String>('k')),
          'globex');
      expect(await DV.Cache.get<String>('k'), isNull);
    });

    test('revalidating a tag removes only the tagging tenant\'s keys',
        () async {
      const DVTenants tenants = DVTenants();
      await tenants.withTenant(
          'acme',
          () => DV.Cache.set('users', 'acme', tags: <String>['users']));
      await tenants.withTenant('globex', () => DV.Cache.set('users', 'globex'));

      await DV.Cache.revalidateTag('users');

      expect(
          await tenants.withTenant('acme', () => DV.Cache.has('users')), isFalse);
      expect(
          await tenants.withTenant(
              'globex', () => DV.Cache.get<String>('users')),
          'globex');
    });
  });
}
