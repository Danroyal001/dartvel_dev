// A rate limit that counts in one process is a rate limit per process.
//
// Two instances behind a load balancer give an attacker twice the budget,
// three give three times, and a restart hands everyone a fresh one. Nothing
// about that looks wrong from inside either process: each refuses exactly
// what it was told to refuse, and the total is whatever the deployment
// happens to be scaled to.
//
// So the counter can live in the cache every instance already shares. What
// these tests hold it to: the count is shared, the window still rolls, one
// caller's budget is not another's, a store that cannot count atomically is
// refused out loud rather than quietly losing hits, and a store that is down
// does not take the application down with it.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> request({String peer = '198.51.100.7:4000'}) =>
    <String, Object?>{
      'peerAddress': peer,
      'method': 'GET',
      'path': '/orders',
      'headers': const <String, String>{},
      'url': 'https://shop.example.test/orders',
    };

/// A cache every "instance" in a test shares, and which can count.
class _SharedCache implements DVCacheAdapter, DVCountingCacheAdapter {
  final Map<String, Object?> values = <String, Object?>{};
  int increments = 0;

  @override
  Future<int> increment(String key, {int by = 1, Duration? ttl}) async {
    increments++;
    final int next = ((values[key] as int?) ?? 0) + by;
    values[key] = next;
    return next;
  }

  @override
  Future<Object?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Object? value, Duration? ttl) async =>
      values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> clear() async => values.clear();
  @override
  Future<int> purgeExpired() async => 0;
}

/// A cache that cannot count: read-modify-write across instances loses hits.
class _PlainCache implements DVCacheAdapter {
  @override
  Future<Object?> read(String key) async => null;
  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {}
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<int> purgeExpired() async => 0;
}

/// A store that is there and not working.
class _BrokenCache extends _SharedCache {
  @override
  Future<int> increment(String key, {int by = 1, Duration? ttl}) async =>
      throw StateError('connection refused');
}

Future<bool> allowed(Middleware limit, Map<String, Object?> req) async {
  final MiddlewareChain chain = MiddlewareChain()..use(limit);
  final MiddlewareContext context = await chain.execute(req);
  return !context.data.containsKey('rateLimitError');
}

void main() {
  group('a counter every instance shares', () {
    test('two instances spend one budget, not one each', () async {
      final _SharedCache cache = _SharedCache();
      // Two limiters, as two servers behind a load balancer.
      final Middleware first = CommonMiddleware.rateLimit(
        maxRequests: 2,
        store: cache,
      );
      final Middleware second = CommonMiddleware.rateLimit(
        maxRequests: 2,
        store: cache,
      );

      expect(await allowed(first, request()), isTrue);
      expect(await allowed(second, request()), isTrue);
      // The third request is over the limit wherever it lands.
      expect(await allowed(second, request()), isFalse);
      expect(await allowed(first, request()), isFalse);
    });

    test('the window rolls, and the budget comes back', () async {
      final _SharedCache cache = _SharedCache();
      DateTime now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final Middleware limit = CommonMiddleware.rateLimit(
        maxRequests: 1,
        window: const Duration(minutes: 1),
        store: cache,
        clock: () => now,
      );

      expect(await allowed(limit, request()), isTrue);
      expect(await allowed(limit, request()), isFalse);

      now = now.add(const Duration(minutes: 1));
      expect(await allowed(limit, request()), isTrue,
          reason: 'a counter that never rolls blocks the caller for ever');
    });

    test('one caller does not spend another caller\'s budget', () async {
      final _SharedCache cache = _SharedCache();
      final Middleware limit =
          CommonMiddleware.rateLimit(maxRequests: 1, store: cache);

      expect(await allowed(limit, request(peer: '198.51.100.1:4000')), isTrue);
      expect(await allowed(limit, request(peer: '198.51.100.2:4000')), isTrue);
      expect(await allowed(limit, request(peer: '198.51.100.1:4000')), isFalse);
    });

    test('a store that cannot count is refused when it is handed over', () {
      // Read, add one, write back: two instances that read the same number
      // both write the same number, and the hits in between are gone. A
      // limiter that silently does that is worse than no limiter, because
      // the deployment believes it has one.
      expect(
        () => CommonMiddleware.rateLimit(maxRequests: 1, store: _PlainCache()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a store that is down does not take the application with it',
        () async {
      // Refusing every request while the cache is unreachable turns a cache
      // outage into an outage. It allows, and says so where somebody can see
      // it.
      final Middleware limit =
          CommonMiddleware.rateLimit(maxRequests: 1, store: _BrokenCache());

      expect(await allowed(limit, request()), isTrue);
      expect(await allowed(limit, request()), isTrue);
    });
  });

  group('without a store', () {
    test('the limit still counts, in this process', () async {
      final Middleware limit = CommonMiddleware.rateLimit(maxRequests: 1);

      expect(await allowed(limit, request(peer: '203.0.113.5:4000')), isTrue);
      expect(await allowed(limit, request(peer: '203.0.113.5:4000')), isFalse);
    });
  });

  group('the memory adapter', () {
    test('counts, so a single-process deployment can use the same path',
        () async {
      final DVMemoryCacheAdapter cache = DVMemoryCacheAdapter();
      expect(cache, isA<DVCountingCacheAdapter>());

      final DVCountingCacheAdapter counter = cache as DVCountingCacheAdapter;
      expect(await counter.increment('hits'), 1);
      expect(await counter.increment('hits'), 2);
      expect(await counter.increment('hits', by: 5), 7);
    });

    test('a counter expires with its window', () async {
      final DVMemoryCacheAdapter cache = DVMemoryCacheAdapter();
      final DVCountingCacheAdapter counter = cache as DVCountingCacheAdapter;

      await counter.increment('hits', ttl: Duration.zero);
      // Expired, so the next hit starts again rather than adding to a count
      // from a window that has passed.
      expect(await counter.increment('hits', ttl: Duration.zero), 1);
    });
  });
}
