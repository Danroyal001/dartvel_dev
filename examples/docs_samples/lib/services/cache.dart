import '../dartvel_client/dartvel_client.dart';

Future<List<String>> fetchProductNames() async => <String>['Starter kit'];

// docs:start cache-remember
Future<List<String>> productNames() async {
  final List<String> names = await DV.Cache.remember<List<String>>(
    'products:names',
    const Duration(minutes: 10),
    fetchProductNames, // runs only when the key is missing or expired
  );
  DV.Cache.tag('products:names', <String>['products']);
  return names;
}

Future<void> productChanged() async {
  // Drops every key tagged "products".
  await DV.Cache.revalidateTag('products');
}
// docs:end

Future<void> basics() async {
  // docs:start cache-basics
  await DV.Cache.set('greeting', 'hello', const Duration(hours: 1));
  final String? greeting = await DV.Cache.get<String>('greeting');
  await DV.Cache.delete('greeting');
  // docs:end
  // docs:start cache-stale
  final List<String> names = await DV.Cache.staleWhileRevalidate<List<String>>(
    'products:names',
    ttl: const Duration(minutes: 1),
    staleFor: const Duration(minutes: 10),
    compute: fetchProductNames,
  );
  // docs:end
  // docs:start cache-lock
  final DVCacheLock? lock = await DV.Cache.lock('reports:monthly');
  if (lock != null) {
    try {
      // Only one caller at a time gets here.
    } finally {
      await lock.release();
    }
  }
  // docs:end
  DV.log('$greeting $names');
}

Future<void> redis() async {
  // docs:start cache-redis
  final DVRedisClient client = await DVRedisClient.connect(host: 'cache.internal');
  DV.Cache.configure(DVRedisCacheAdapter(client));
  // docs:end
}
