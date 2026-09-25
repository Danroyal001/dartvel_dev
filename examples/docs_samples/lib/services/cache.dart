import '../dartvel_client/dartvel_client.dart';

Future<List<String>> fetchProductNames() async => <String>['Starter kit'];

Future<void> basics() async {
  // docs:start cache-basics
  await DV.Cache.set('greeting', 'hello', ttl: const Duration(hours: 1));
  final String? greeting = await DV.Cache.get<String>('greeting');
  final bool cached = await DV.Cache.has('greeting');
  await DV.Cache.delete('greeting');
  await DV.Cache.clear(); // every key
  // docs:end
  DV.log('$greeting $cached');
}

// docs:start cache-remember
Future<List<String>> productNames() => DV.Cache.remember<List<String>>(
      'products:names',
      fetchProductNames, // runs only when the key is missing or expired
      ttl: const Duration(minutes: 10),
      tags: <String>['products'],
    );

Future<void> productChanged() async {
  // Drops every key tagged "products"; the next productNames() recomputes.
  await DV.Cache.revalidateTag('products');
}
// docs:end

Future<void> stale() async {
  // docs:start cache-stale
  final List<String> names = await DV.Cache.remember<List<String>>(
    'products:names',
    fetchProductNames,
    ttl: const Duration(minutes: 1),
    staleFor: const Duration(minutes: 10),
  );
  // docs:end
  DV.log('$names');
}

Future<void> sendMonthlyReport() async {}

Future<void> lock() async {
  // docs:start cache-lock
  final bool? sent = await DV.Cache.lock('reports:monthly', () async {
    await sendMonthlyReport(); // one caller at a time, across every server
    return true;
  });
  if (sent == null) DV.log('Another server is sending the report.');
  // docs:end
}

Future<void> redis() async {
  // docs:start cache-redis
  final DVRedisClient client = await DVRedisClient.connect(host: 'cache.internal');
  DV.Cache.configure(DVRedisCacheAdapter(client));
  // docs:end
}
