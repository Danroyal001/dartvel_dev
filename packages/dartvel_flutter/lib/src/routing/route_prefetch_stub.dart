/// Off the web there is no prerendered document and no browser cache to fill,
/// so a route prefetches its code through `loadLibrary()` and nothing else.
library dartvel_flutter.routing.route_prefetch.stub;

/// Nothing to fetch: no images to hand to the image cache.
Future<List<String>> dvPrefetchDocument(String path) async => const <String>[];

/// Nothing to forget.
void dvResetPrefetchDocument() {}
