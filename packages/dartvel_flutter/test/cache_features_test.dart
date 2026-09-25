// DV.Cache from a page. The behaviour -- remember, tags, the stale window,
// locks, tenant-aware keys -- is covered in dartvel_core's dv_cache_test,
// where the cache lives; this checks that a page reaches that same cache
// through the same calls, and the global helpers only the client has.
import 'package:dartvel_core/dartvel.dart' show DVMemoryCacheAdapter;
import 'package:dartvel_core/dv.dart' as server;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DV.Cache.configure(DVMemoryCacheAdapter());
    DVTenants.reset();
  });

  test('a page and a backend function share one cache', () async {
    await DV.Cache.set('greeting', 'hello', ttl: const Duration(minutes: 1));
    expect(await server.DV.Cache.get<String>('greeting'), 'hello');

    await server.DV.Cache.delete('greeting');
    expect(await DV.Cache.has('greeting'), isFalse);
  });

  test('remember takes the compute, then ttl and tags by name', () async {
    int computes = 0;
    Future<List<String>> compute() async => <String>['kit ${++computes}'];

    await DV.Cache.remember<List<String>>('products:names', compute,
        ttl: const Duration(minutes: 10), tags: <String>['products']);
    await DV.Cache.revalidateTag('products');
    final List<String> names = await DV.Cache.remember<List<String>>(
        'products:names', compute,
        ttl: const Duration(minutes: 10), tags: <String>['products']);

    expect(names, <String>['kit 2']);
  });

  test('lock runs the body and hands back its result', () async {
    expect(await DV.Cache.lock<int>('report', () async => 7), 7);
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

      await DV.Cache.globalSet('shared', 'everyone',
          ttl: const Duration(minutes: 1));
      DV.Cache.globalTag('shared', <String>['broadcast']);

      expect(await DV.Cache.globalGet<String>('shared'), 'everyone');
      // Not visible through the per-client cache.
      expect(await DV.Cache.get<String>('shared'), isNull);

      final Set<String> removed = await DV.Cache.globalRevalidateTag('broadcast');
      expect(removed, isNotEmpty);
      expect(await DV.Cache.globalGet<String>('shared'), isNull);
    });
  });
}
