// DV.Cache from a page. The behaviour -- read-through, tags, the stale
// window, tenant-aware keys, and the framework's lock -- is covered in
// dartvel_core's dv_cache_test, where the cache lives; this checks that a page
// reaches that same cache through the same four calls.
import 'package:dartvel_core/dartvel.dart' show DVMemoryCacheAdapter;
import 'package:dartvel_core/dv.dart' as server;
import 'package:dartvel_core/framework.dart' show DVCacheRuntime;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DVCacheRuntime.configure(DVMemoryCacheAdapter());
    DVTenants.reset();
  });

  test('a page and a backend function share one cache', () async {
    await DV.Cache.set('greeting', 'hello', ttl: const Duration(minutes: 1));
    expect(await server.DV.Cache.get<String>('greeting'), 'hello');

    await server.DV.Cache.delete('greeting');
    expect(await DV.Cache.has('greeting'), isFalse);
  });

  test('get reads through with compute:, and ttl and tags by name', () async {
    int computes = 0;
    Future<List<String>> compute() async => <String>['kit ${++computes}'];

    await DV.Cache.get<List<String>>('products:names',
        compute: compute,
        ttl: const Duration(minutes: 10),
        tags: <String>['products']);
    await DV.Cache.delete(const DVCacheTag('products'));
    final List<String>? names = await DV.Cache.get<List<String>>(
        'products:names',
        compute: compute,
        ttl: const Duration(minutes: 10),
        tags: <String>['products']);

    expect(names, <String>['kit 2']);
  });

  test('delete(DVCache.all) empties the cache a page sees', () async {
    await DV.Cache.set('a', 1);
    await server.DV.Cache.set('b', 2);

    await DV.Cache.delete(DVCache.all);

    expect(await DV.Cache.has('a'), isFalse);
    expect(await server.DV.Cache.has('b'), isFalse);
  });
}
