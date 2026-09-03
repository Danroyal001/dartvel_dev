// The kept pages, shared.
//
// The page cache kept its pages in the process, so two servers behind a load
// balancer each resolved every page and `cache: redis` in the declaration
// meant nothing. A shared store is any DVCacheAdapter: the page goes in as
// JSON with when it was kept, and the next server -- or the next process --
// serves it without asking the database again.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// One store both caches use, standing in for redis.
class _SharedAdapter implements DVCacheAdapter {
  final Map<String, Object?> values = <String, Object?>{};
  final List<String> written = <String>[];

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    values[key] = value;
    written.add(key);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<int> purgeExpired() async => 0;
}

const DVPageRequest request = DVPageRequest(
  path: '/products/1',
  pattern: '/products/:id',
  params: <String, String>{'id': '1'},
);

void main() {
  late _SharedAdapter store;
  late int now;
  var asked = 0;

  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(now * 1000);

  Future<DVPageData?> resolver(DVPageRequest r) async {
    asked++;
    return DVPageData(
      title: 'Product $asked',
      description: 'Made once',
      image: '/img/$asked.png',
      favicon: '/icons/p.png',
      text: <String>['Product $asked', 'In stock'],
      structuredData: <String, Object?>{'@type': 'Product', 'name': 'Product $asked'},
    );
  }

  DVPageDataCache cache() => DVPageDataCache(ttl: const Duration(seconds: 10), now: clock, shared: store);

  setUp(() {
    store = _SharedAdapter();
    now = 0;
    asked = 0;
  });

  test('what one server keeps, another serves without asking again', () async {
    final DVPageData? first = await cache().resolve(request, resolver, DVPageDataMode.cache);
    final DVPageData? second = await cache().resolve(request, resolver, DVPageDataMode.cache);

    expect(asked, 1, reason: 'the second server found the page already kept');
    expect(second!.title, first!.title);
  });

  test('the kept page carries everything the page is made from', () async {
    await cache().resolve(request, resolver, DVPageDataMode.cache);
    final DVPageData kept = (await cache().resolve(request, resolver, DVPageDataMode.cache))!;

    expect(kept.title, 'Product 1');
    expect(kept.description, 'Made once');
    expect(kept.image, '/img/1.png');
    expect(kept.favicon, '/icons/p.png');
    expect(kept.text, <String>['Product 1', 'In stock']);
    expect(kept.structuredData, containsPair('@type', 'Product'));
    expect(kept.visibility, DVPageVisibility.public);
  });

  test('a page hidden by the resolver is kept hidden', () async {
    Future<DVPageData?> hidden(DVPageRequest r) async =>
        const DVPageData(title: 'Draft', visibility: DVPageVisibility.hidden);
    await cache().resolve(request, hidden, DVPageDataMode.cache);

    final DVPageData? kept = await cache().resolve(request, hidden, DVPageDataMode.cache);

    expect(kept!.visibility, DVPageVisibility.hidden);
  });

  test('past the ttl the next server resolves again, and its answer is what the first then serves', () async {
    await cache().resolve(request, resolver, DVPageDataMode.cache);
    now = 11;

    expect((await cache().resolve(request, resolver, DVPageDataMode.cache))!.title, 'Product 2');
    expect((await cache().resolve(request, resolver, DVPageDataMode.cache))!.title, 'Product 2',
        reason: 'the refreshed page is in the shared store, not one process');
    expect(asked, 2);
  });

  test('stale-while-revalidate serves the shared stale page and refreshes it there', () async {
    await cache().resolve(request, resolver, DVPageDataMode.staleWhileRevalidate);
    now = 11;

    expect((await cache().resolve(request, resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'Product 1');
    await Future<void>.delayed(Duration.zero);
    expect((await cache().resolve(request, resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'Product 2');
  });

  test('a page too old even to be stale is resolved again, not served', () async {
    await cache().resolve(request, resolver, DVPageDataMode.staleWhileRevalidate);
    // Fresh for the ttl, servable stale for the same again; past both it is
    // gone rather than served as a page from an hour ago.
    now = 30;

    expect((await cache().resolve(request, resolver, DVPageDataMode.staleWhileRevalidate))!.title, 'Product 2');
  });

  test('an entry that is not a page is ignored rather than served', () async {
    await cache().resolve(request, resolver, DVPageDataMode.cache);
    store.values.updateAll((String key, Object? value) => 'not json at all');

    expect((await cache().resolve(request, resolver, DVPageDataMode.cache))!.title, 'Product 2');
  });

  test('the key names the route, so one page cannot serve another', () async {
    await cache().resolve(request, resolver, DVPageDataMode.cache);
    await cache().resolve(
      const DVPageRequest(path: '/products/2', pattern: '/products/:id', params: <String, String>{'id': '2'}),
      resolver,
      DVPageDataMode.cache,
    );

    expect(asked, 2);
    expect(store.values.keys, hasLength(2));
    expect(store.values.keys.every((String k) => k.contains('/products/')), isTrue);
  });

  test('await asks every time even with a store, and defer asks never', () async {
    await cache().resolve(request, resolver, DVPageDataMode.await_);
    await cache().resolve(request, resolver, DVPageDataMode.await_);
    expect(asked, 2);
    expect(store.written, isEmpty, reason: 'nothing is kept for a mode that does not keep');

    expect(await cache().resolve(request, resolver, DVPageDataMode.defer), isNull);
    expect(asked, 2);
  });
  unkeepable();
}

// A page that can be kept for no time is not written at all: a store is
// entitled to refuse a lifetime of nothing, and Redis does -- "invalid
// expire time in 'set' command" -- which a fake store never says.
void unkeepable() {
  test('a page with no lifetime is not written to the store', () async {
    final _SharedAdapter store = _SharedAdapter();
    var asked = 0;
    Future<DVPageData?> resolver(DVPageRequest r) async {
      asked++;
      return DVPageData(title: 'Product $asked');
    }

    final DVPageDataCache cache =
        DVPageDataCache(ttl: Duration.zero, staleFor: Duration.zero, shared: store);
    await cache.resolve(request, resolver, DVPageDataMode.cache);

    expect(store.written, isEmpty);
    expect((await cache.resolve(request, resolver, DVPageDataMode.cache))!.title, 'Product 2');
  });
}
