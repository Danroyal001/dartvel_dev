import '../dartvel_client/dartvel_client.dart';

Future<List<String>> fetchProductNames() async => <String>['Starter kit'];

Future<void> basics() async {
  // docs:start cache-basics
  await DV.Cache.set('greeting', 'hello', ttl: const Duration(hours: 1));
  final String? greeting = await DV.Cache.get<String>('greeting');
  final bool cached = await DV.Cache.has('greeting');
  await DV.Cache.delete('greeting');
  // docs:end
  DV.log('$greeting $cached');
}

// docs:start cache-compute
Future<List<String>?> productNames() => DV.Cache.get<List<String>>(
      'products:names',
      compute: fetchProductNames, // runs only when the key is missing or expired
      ttl: const Duration(minutes: 10),
      tags: <String>['products'],
    );
// docs:end

Future<void> tags() async {
  // docs:start cache-tags
  await DV.Cache.set('home:featured', <String>['Starter kit'],
      tags: <String>['products', 'home']);
  await DV.Cache.delete(const DVCacheTag('products')); // every key tagged products
  await DV.Cache.delete(DVCache.all); // every key
  // docs:end
}

Future<void> stale() async {
  // docs:start cache-stale
  final List<String>? names = await DV.Cache.get<List<String>>(
    'products:names',
    compute: fetchProductNames,
    ttl: const Duration(minutes: 1),
    staleFor: const Duration(minutes: 10),
  );
  // docs:end
  DV.log('$names');
}

Future<void> switchStore() async {
  // docs:start cache-switch
  final DVCacheView sessions = DV.Cache.withAdapter(
    await DVRedisCacheAdapter.connect(DV.Secrets.get('SESSIONS_REDIS_URL')),
  );
  await sessions.set('visitor:42', 'signed in', ttl: const Duration(hours: 8));
  final bool active = await sessions.has('visitor:42');
  // docs:end
  DV.log('$active');
}
