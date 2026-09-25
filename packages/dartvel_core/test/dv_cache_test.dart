// DV.Cache as an application uses it: four calls, get, set, has and delete,
// with everything else a named option on them. get with compute: is
// read-through with one shared compute per key and an optional stale window;
// set takes tags; delete drops a key, a tag or everything.
//
// The lock, the store and tag inspection are the framework's, reached through
// DVCacheRuntime, and are tested here for the framework that uses them.
// Driven through the real adapters, on the server's DV -- behaviour, not
// shape.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';
import 'package:dartvel_core/framework.dart' show DVCacheRuntime;
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVCacheRuntime.configure(DVMemoryCacheAdapter());
    const DVTestHarness().resetCacheTags();
    DVTenants.reset();
  });

  group('the four calls', () {
    test('set, get, has and delete', () async {
      await DV.Cache.set('greeting', 'hello');

      expect(await DV.Cache.get<String>('greeting'), 'hello');
      expect(await DV.Cache.has('greeting'), isTrue);

      await DV.Cache.delete(key: 'greeting');
      expect(await DV.Cache.get<String>('greeting'), isNull);
      expect(await DV.Cache.has('greeting'), isFalse);
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

    test('the server DV.Cache and DVCache are one cache', () async {
      await DV.Cache.set('shared', 'one');
      expect(await const DVCache().get<String>('shared'), 'one');
    });
  });

  group('delete', () {
    // Dart cannot mix an optional positional parameter with named ones, so
    // the key is named too: delete(key: k), delete(tag: t), delete(all: true).
    test('delete(tag:) drops every key tagged, and only those', () async {
      await DV.Cache.set(
        'products:names',
        <String>['kit'],
        tags: <String>['products'],
      );
      await DV.Cache.set('products:count', 1, tags: <String>['products']);
      await DV.Cache.set('orders:open', 4, tags: <String>['orders']);

      await DV.Cache.delete(tag: 'products');

      expect(await DV.Cache.has('products:names'), isFalse);
      expect(await DV.Cache.has('products:count'), isFalse);
      expect(await DV.Cache.get<int>('orders:open'), 4);
    });

    test('delete(all: true) drops every key and every tag', () async {
      await DV.Cache.set('a', 1, tags: <String>['letters']);
      await DV.Cache.set('b', 2);

      await DV.Cache.delete(all: true);

      expect(await DV.Cache.has('a'), isFalse);
      expect(await DV.Cache.has('b'), isFalse);
      expect(DVCacheRuntime.tags, isEmpty);
    });

    // Each of these is a call that would otherwise do something plausible and
    // wrong: drop one key when the caller meant a tag, or nothing at all.
    final Map<String, Future<void> Function()> ambiguous =
        <String, Future<void> Function()>{
          'nothing': () => DV.Cache.delete(),
          'all: false alone': () => DV.Cache.delete(all: false),
          'a key and a tag': () => DV.Cache.delete(key: 'k', tag: 't'),
          'a key and all': () => DV.Cache.delete(key: 'k', all: true),
          'a tag and all': () => DV.Cache.delete(tag: 't', all: true),
          'all three': () => DV.Cache.delete(key: 'k', tag: 't', all: true),
        };
    for (final MapEntry<String, Future<void> Function()> call
        in ambiguous.entries) {
      test('delete with ${call.key} is an ArgumentError', () async {
        await DV.Cache.set('k', 'kept', tags: <String>['t']);

        await expectLater(call.value, throwsArgumentError);
        expect(
          await DV.Cache.get<String>('k'),
          'kept',
          reason: 'a refused delete removes nothing',
        );
      });
    }
  });

  group('get with compute:', () {
    test('computes on a miss and serves the stored value after', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      expect(await DV.Cache.get<String>('k', compute: compute), 'v1');
      expect(await DV.Cache.get<String>('k', compute: compute), 'v1');
      expect(computes, 1);
      expect(await DV.Cache.get<String>('k'), 'v1');
    });

    test('ttl is named and bounds how long the value is reused', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await DV.Cache.get<String>(
        'k',
        compute: compute,
        ttl: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        await DV.Cache.get<String>(
          'k',
          compute: compute,
          ttl: const Duration(milliseconds: 20),
        ),
        'v2',
      );
    });

    test(
      'tags are an option: deleting the tag makes it compute again',
      () async {
        int computes = 0;
        Future<List<String>> compute() async => <String>['kit ${++computes}'];

        await DV.Cache.get<List<String>>(
          'products:names',
          compute: compute,
          tags: <String>['products'],
        );
        await DV.Cache.delete(tag: 'products');
        final List<String>? again = await DV.Cache.get<List<String>>(
          'products:names',
          compute: compute,
          tags: <String>['products'],
        );

        expect(again, <String>['kit 2']);
        expect(computes, 2);
      },
    );

    test('concurrent callers share one compute', () async {
      int computes = 0;
      Future<String> compute() async {
        computes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'value';
      }

      final List<String?> results = await Future.wait(<Future<String?>>[
        DV.Cache.get<String>('expensive', compute: compute),
        DV.Cache.get<String>('expensive', compute: compute),
        DV.Cache.get<String>('expensive', compute: compute),
      ]);

      expect(results, everyElement('value'));
      expect(computes, 1, reason: 'a stampede would have computed three times');
    });

    test('a value already set skips the compute', () async {
      await DV.Cache.set('warm', 'cached');
      bool computed = false;

      final String? result = await DV.Cache.get<String>(
        'warm',
        compute: () async {
          computed = true;
          return 'fresh';
        },
      );

      expect(result, 'cached');
      expect(computed, isFalse);
    });

    test(
      'a throwing compute is not cached and does not wedge the key',
      () async {
        await expectLater(
          DV.Cache.get<String>(
            'bad',
            compute: () async => throw StateError('x'),
          ),
          throwsStateError,
        );
        expect(
          await DV.Cache.get<String>('bad', compute: () async => 'ok'),
          'ok',
        );
      },
    );

    test(
      'a list read back from a JSON store is a hit, not a recompute',
      () async {
        // A database, Redis or Memcached store hands back List<dynamic>. Read
        // as List<String> that used to be a type miss, so a read-through get
        // computed on every call against any store but memory -- a cache that
        // never caches, and nothing says so.
        DVCacheRuntime.configure(
          DVDatabaseCacheAdapter(MemoryDVDatabaseAdapter()),
        );
        int computes = 0;
        Future<List<String>> compute() async {
          computes++;
          return <String>['kit'];
        }

        await DV.Cache.get<List<String>>('names', compute: compute);
        final List<String>? second = await DV.Cache.get<List<String>>(
          'names',
          compute: compute,
        );

        expect(second, <String>['kit']);
        expect(computes, 1);
        expect(await DV.Cache.get<List<String>>('names'), <String>['kit']);
      },
    );

    // Options that only mean something to a compute would otherwise be
    // dropped without a word: a ttl that never applies, a tag that never
    // lands, a stale window that is never served.
    final Map<String, Future<Object?> Function()> orphaned =
        <String, Future<Object?> Function()>{
          'ttl:': () =>
              DV.Cache.get<String>('k', ttl: const Duration(minutes: 1)),
          'tags:': () => DV.Cache.get<String>('k', tags: <String>['t']),
          'staleFor:': () =>
              DV.Cache.get<String>('k', staleFor: const Duration(minutes: 1)),
        };
    for (final MapEntry<String, Future<Object?> Function()> call
        in orphaned.entries) {
      test('${call.key} without compute: is an ArgumentError', () async {
        await expectLater(call.value, throwsArgumentError);
      });
    }

    test('staleFor: without ttl: is an ArgumentError', () async {
      // Without a ttl there is no point at which a value turns stale, so the
      // window could never be served.
      await expectLater(
        () => DV.Cache.get<String>(
          'k',
          compute: () async => 'v',
          staleFor: const Duration(minutes: 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('get with staleFor:', () {
    test(
      'serves the stale value at once and refreshes it once behind',
      () async {
        int computes = 0;
        Future<String> compute() async => 'v${++computes}';

        expect(
          await DV.Cache.get<String>(
            'feed',
            compute: compute,
            ttl: const Duration(milliseconds: 10),
            staleFor: const Duration(minutes: 1),
          ),
          'v1',
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final List<String?> stale = await Future.wait(<Future<String?>>[
          DV.Cache.get<String>(
            'feed',
            compute: compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1),
          ),
          DV.Cache.get<String>(
            'feed',
            compute: compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1),
          ),
        ]);
        expect(stale, everyElement('v1'));

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          await DV.Cache.get<String>(
            'feed',
            compute: compute,
            ttl: const Duration(minutes: 1),
            staleFor: const Duration(minutes: 1),
          ),
          'v2',
        );
        expect(computes, 2, reason: 'two stale readers share one refresh');
      },
    );

    test('past ttl and staleFor the caller waits for a real value', () async {
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await DV.Cache.get<String>(
        'gone',
        compute: compute,
        ttl: const Duration(milliseconds: 5),
        staleFor: const Duration(milliseconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        await DV.Cache.get<String>(
          'gone',
          compute: compute,
          ttl: const Duration(minutes: 1),
          staleFor: const Duration(minutes: 1),
        ),
        'v2',
      );
    });

    test('the key holds the plain value, so a plain get reads it', () async {
      await DV.Cache.get<String>(
        'feed',
        compute: () async => 'value',
        ttl: const Duration(minutes: 1),
        staleFor: const Duration(minutes: 1),
      );

      expect(await DV.Cache.get<String>('feed'), 'value');
    });
  });

  group('withAdapter', () {
    // dartvel.cache sets the store DV.Cache uses; withAdapter switches store
    // in code, with the same four calls and options.
    test(
      'every call goes to the given adapter and never to the default',
      () async {
        final DVMemoryCacheAdapter fallback = DVMemoryCacheAdapter();
        DVCacheRuntime.configure(fallback);
        final DVMemoryCacheAdapter other = DVMemoryCacheAdapter();
        final DVCacheView cache = DV.Cache.withAdapter(other);

        await cache.set('k', 'v', ttl: const Duration(minutes: 1));
        expect(await other.read('k'), 'v');
        expect(await fallback.read('k'), isNull);
        expect(await DV.Cache.has('k'), isFalse);
        expect(await cache.has('k'), isTrue);
        expect(await cache.get<String>('k'), 'v');

        expect(
          await cache.get<String>('computed', compute: () async => 'c'),
          'c',
        );
        expect(await other.read('computed'), 'c');
        expect(await fallback.read('computed'), isNull);

        await DV.Cache.set('k', 'default');
        await cache.delete(key: 'k');
        expect(await other.read('k'), isNull);
        expect(await DV.Cache.get<String>('k'), 'default');

        await cache.set('x', 1);
        await cache.delete(all: true);
        expect(await other.read('x'), isNull);
        expect(await DV.Cache.get<String>('k'), 'default');
      },
    );

    test('tags stay separate per adapter', () async {
      final DVCacheView a = DV.Cache.withAdapter(DVMemoryCacheAdapter());
      final DVCacheView b = DV.Cache.withAdapter(DVMemoryCacheAdapter());
      await DV.Cache.set('k', 'default', tags: <String>['t']);
      await a.set('k', 'a', tags: <String>['t']);
      await b.set('k', 'b', tags: <String>['t']);

      await a.delete(tag: 't');

      expect(await a.has('k'), isFalse);
      expect(await b.get<String>('k'), 'b');
      expect(await DV.Cache.get<String>('k'), 'default');
      expect(DVCacheRuntime.keysForTag('t'), <String>{'k'});

      await DV.Cache.delete(tag: 't');
      expect(await b.get<String>('k'), 'b');
    });

    test('two views of one adapter are one cache, tags included', () async {
      final DVMemoryCacheAdapter store = DVMemoryCacheAdapter();
      await DV.Cache.withAdapter(store).set('k', 'v', tags: <String>['t']);

      await DV.Cache.withAdapter(store).delete(tag: 't');

      expect(await store.read('k'), isNull);
    });

    test(
      'concurrent computes are shared per adapter, not across them',
      () async {
        int computes = 0;
        Future<String> compute() async {
          computes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'value';
        }

        final DVCacheView a = DV.Cache.withAdapter(DVMemoryCacheAdapter());
        final DVCacheView b = DV.Cache.withAdapter(DVMemoryCacheAdapter());
        await Future.wait(<Future<String?>>[
          a.get<String>('k', compute: compute),
          a.get<String>('k', compute: compute),
          b.get<String>('k', compute: compute),
          b.get<String>('k', compute: compute),
        ]);

        expect(computes, 2, reason: 'one compute per adapter');
        expect(await DV.Cache.has('k'), isFalse);
      },
    );

    test('the stale window works on a switched adapter', () async {
      final DVMemoryCacheAdapter store = DVMemoryCacheAdapter();
      final DVCacheView cache = DV.Cache.withAdapter(store);
      int computes = 0;
      Future<String> compute() async => 'v${++computes}';

      await cache.get<String>(
        'feed',
        compute: compute,
        ttl: const Duration(milliseconds: 10),
        staleFor: const Duration(minutes: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        await cache.get<String>(
          'feed',
          compute: compute,
          ttl: const Duration(minutes: 1),
          staleFor: const Duration(minutes: 1),
        ),
        'v1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await store.read('feed'), 'v2');
    });

    test('delete on a switched adapter still takes exactly one target', () {
      final DVCacheView cache = DV.Cache.withAdapter(DVMemoryCacheAdapter());
      expect(() => cache.delete(), throwsArgumentError);
    });
  });

  group('the framework\'s runtime', () {
    test('configure swaps the store behind every call', () async {
      final DVMemoryCacheAdapter store = DVMemoryCacheAdapter();
      DVCacheRuntime.configure(store);

      await DV.Cache.set('k', 'v');
      expect(await store.read('k'), 'v');
      expect(DVCacheRuntime.adapter, same(store));
    });

    test('keysForTag and tags name what delete(tag:) would drop', () async {
      await DV.Cache.set('users:list', 'everyone', tags: <String>['users']);

      expect(DVCacheRuntime.tags, contains('users'));
      expect(DVCacheRuntime.keysForTag('users'), <String>{'users:list'});

      await DV.Cache.delete(tag: 'users');
      expect(DVCacheRuntime.keysForTag('users'), isEmpty);
    });

    test('the global cache is refused until one is configured', () async {
      DVCacheRuntime.configureGlobal(null);
      await expectLater(
        DVCacheRuntime.global.get<String>('k'),
        throwsStateError,
      );
    });

    test('the global cache keeps its entries apart from DV.Cache', () async {
      final DVMemoryCacheAdapter shared = DVMemoryCacheAdapter();
      DVCacheRuntime.configureGlobal(shared);
      addTearDown(() => DVCacheRuntime.configureGlobal(null));

      await DVCacheRuntime.global.set(
        'k',
        'everyone',
        tags: <String>['broadcast'],
      );
      expect(await shared.read('k'), 'everyone');
      expect(await DV.Cache.has('k'), isFalse);

      await DVCacheRuntime.global.delete(tag: 'broadcast');
      expect(await DVCacheRuntime.global.has('k'), isFalse);
    });

    test('purgeExpired reclaims what has expired', () async {
      await DV.Cache.set('short', 'v', ttl: const Duration(milliseconds: 5));
      await DV.Cache.set('long', 'v');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await DVCacheRuntime.purgeExpired(), 1);
      expect(await DV.Cache.has('long'), isTrue);
    });
  });

  group('lock', () {
    test('runs the body under the lock and returns what it returns', () async {
      final int? result = await DVCacheRuntime.lock<int>(
        'report',
        () async => 42,
      );
      expect(result, 42);
    });

    test('a second caller is refused while the body runs', () async {
      final Completer<void> inside = Completer<void>();
      final Completer<void> finish = Completer<void>();
      final Future<String?> first = DVCacheRuntime.lock<String>(
        'report',
        () async {
          inside.complete();
          await finish.future;
          return 'first';
        },
      );
      await inside.future;

      bool ran = false;
      final String? second = await DVCacheRuntime.lock<String>(
        'report',
        () async {
          ran = true;
          return 'second';
        },
      );

      expect(second, isNull);
      expect(ran, isFalse);
      finish.complete();
      expect(await first, 'first');
    });

    test(
      'the lock is released after the body, so the next caller runs',
      () async {
        await DVCacheRuntime.lock<void>('report', () async {});
        expect(
          await DVCacheRuntime.lock<String>('report', () async => 'next'),
          'next',
        );
      },
    );

    test('a body that throws still releases the lock', () async {
      await expectLater(
        DVCacheRuntime.lock<void>(
          'report',
          () async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(
        await DVCacheRuntime.lock<String>('report', () async => 'again'),
        'again',
      );
    });

    test('wait: waits for the holder to finish, then runs', () async {
      final Completer<void> inside = Completer<void>();
      final Future<void> holder = DVCacheRuntime.lock<void>('report', () async {
        inside.complete();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await inside.future;

      final String? waited = await DVCacheRuntime.lock<String>(
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
      final Future<void> holder = DVCacheRuntime.lock<void>('report', () async {
        inside.complete();
        await finish.future;
      });
      await inside.future;

      final String? gaveUp = await DVCacheRuntime.lock<String>(
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
      unawaited(
        DVCacheRuntime.lock<void>(
          'report',
          () => never.future,
          ttl: const Duration(milliseconds: 20),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        await DVCacheRuntime.lock<String>('report', () async => 'free'),
        'free',
      );
    });

    test('a lock does not use up the key of the same name', () async {
      await DV.Cache.set('report', 'cached');
      expect(
        await DVCacheRuntime.lock<String>('report', () async => 'ran'),
        'ran',
      );
      expect(await DV.Cache.get<String>('report'), 'cached');
    });
  });

  group('tenant-aware keys', () {
    test('tenants do not see each other\'s entries', () async {
      const DVTenants tenants = DVTenants();
      await tenants.withTenant('acme', () => DV.Cache.set('k', 'acme'));
      await tenants.withTenant('globex', () => DV.Cache.set('k', 'globex'));

      expect(
        await tenants.withTenant('acme', () => DV.Cache.get<String>('k')),
        'acme',
      );
      expect(
        await tenants.withTenant('globex', () => DV.Cache.get<String>('k')),
        'globex',
      );
      expect(await DV.Cache.get<String>('k'), isNull);
    });

    test('deleting a tag removes only the tagging tenant\'s keys', () async {
      const DVTenants tenants = DVTenants();
      await tenants.withTenant(
        'acme',
        () => DV.Cache.set('users', 'acme', tags: <String>['users']),
      );
      await tenants.withTenant('globex', () => DV.Cache.set('users', 'globex'));

      await DV.Cache.delete(tag: 'users');

      expect(
        await tenants.withTenant('acme', () => DV.Cache.has('users')),
        isFalse,
      );
      expect(
        await tenants.withTenant('globex', () => DV.Cache.get<String>('users')),
        'globex',
      );
    });
  });
}
