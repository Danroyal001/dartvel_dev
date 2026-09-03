// The shared page cache against a real Redis — two connections, one cache.
//
// The point of a shared store is that the second server does not resolve
// what the first already did. A fake store proves the code path; only a
// real one proves the page survives leaving this process, JSON and expiry
// and all. When no Redis is reachable the suite skips visibly rather than
// passing silently.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<bool> _redisReachable() async {
  try {
    final Socket socket = await Socket.connect('127.0.0.1', 6379, timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

const DVPageRequest request = DVPageRequest(
  path: '/products/lamp',
  pattern: '/products/:slug',
  params: <String, String>{'slug': 'lamp'},
);

void main() async {
  if (!await _redisReachable()) {
    test('the shared page cache (skipped: no Redis at localhost:6379)', () {},
        skip: 'Start a local redis-server to run the shared page cache tests.');
    return;
  }

  late DVRedisClient first;
  late DVRedisClient second;
  late DVRedisCacheAdapter storeA;
  late DVRedisCacheAdapter storeB;
  var asked = 0;

  Future<DVPageData?> resolver(DVPageRequest r) async {
    asked++;
    return DVPageData(
      title: 'Desk lamp $asked',
      description: 'Warm light',
      image: '/img/lamp.png',
      favicon: '/icons/shop.png',
      text: <String>['Desk lamp', 'In stock'],
      structuredData: <String, Object?>{'@type': 'Product', 'name': 'Desk lamp'},
    );
  }

  setUp(() async {
    asked = 0;
    // Two connections, as two servers would have.
    first = await DVRedisClient.connect();
    second = await DVRedisClient.connect();
    storeA = DVRedisCacheAdapter(first, keyPrefix: 'dvpage_a:');
    storeB = DVRedisCacheAdapter(second, keyPrefix: 'dvpage_a:');
    await storeA.clear();
  });

  tearDown(() async {
    await storeA.clear();
    await first.close();
    await second.close();
  });

  test('the second server serves the page the first kept, whole', () async {
    final DVPageDataCache a = DVPageDataCache(ttl: const Duration(minutes: 5), shared: storeA);
    final DVPageDataCache b = DVPageDataCache(ttl: const Duration(minutes: 5), shared: storeB);

    final DVPageData? made = await a.resolve(request, resolver, DVPageDataMode.cache);
    final DVPageData? served = await b.resolve(request, resolver, DVPageDataMode.cache);

    expect(asked, 1, reason: 'the second server found it in Redis');
    expect(served!.title, made!.title);
    expect(served.description, 'Warm light');
    expect(served.image, '/img/lamp.png');
    expect(served.favicon, '/icons/shop.png');
    expect(served.text, <String>['Desk lamp', 'In stock']);
    expect(served.structuredData, containsPair('@type', 'Product'));
  });

  test('a hidden page stays hidden across servers', () async {
    Future<DVPageData?> draft(DVPageRequest r) async =>
        const DVPageData(title: 'Draft', visibility: DVPageVisibility.hidden);
    await DVPageDataCache(ttl: const Duration(minutes: 5), shared: storeA).resolve(request, draft, DVPageDataMode.cache);

    final DVPageData? served = await DVPageDataCache(ttl: const Duration(minutes: 5), shared: storeB)
        .resolve(request, draft, DVPageDataMode.cache);

    expect(served!.visibility, DVPageVisibility.hidden);
  });

  test('Redis holds the page for the ttl and the stale window, then lets it go', () async {
    // One second fresh, one second stale: short enough to watch expire.
    final DVPageDataCache a = DVPageDataCache(
      ttl: const Duration(seconds: 1),
      staleFor: const Duration(seconds: 1),
      shared: storeA,
    );
    await a.resolve(request, resolver, DVPageDataMode.cache);
    // The page is under the cache's own prefix, not the bare path.
    expect(await storeB.read('/products/lamp'), isNull);

    await Future<void>.delayed(const Duration(milliseconds: 2400));

    expect(await DVPageDataCache(ttl: const Duration(seconds: 1), shared: storeB)
        .resolve(request, resolver, DVPageDataMode.cache)
        .then((DVPageData? p) => p!.title), 'Desk lamp 2');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('what one server refreshes, the other then serves', () async {
    // Fresh for no time and servable stale for five minutes: every request
    // after the first is a stale one, which is what refreshing behind the
    // response is for.
    const Duration stale = Duration(minutes: 5);
    final DVPageDataCache a = DVPageDataCache(ttl: Duration.zero, staleFor: stale, shared: storeA);
    final DVPageDataCache b = DVPageDataCache(ttl: Duration.zero, staleFor: stale, shared: storeB);

    await a.resolve(request, resolver, DVPageDataMode.staleWhileRevalidate);
    // Stale at once: served as it stands while a refresh runs behind it.
    expect((await a.resolve(request, resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'Desk lamp 1');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect((await b.resolve(request, resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'Desk lamp 2');
  });
}
