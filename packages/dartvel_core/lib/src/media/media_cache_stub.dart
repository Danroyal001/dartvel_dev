/// No filesystem. The browser's HTTP cache keeps media, and a web player
/// registers its own precache.
library;

import 'media_cache.dart';

final class DVDiskMediaCache implements DVMediaCache {
  DVDiskMediaCache(this.directory, {this.maxBytes = 512 * 1024 * 1024});

  final String directory;
  final int maxBytes;

  Never _unsupported() => throw UnsupportedError(
      'DVDiskMediaCache needs a filesystem; this target has none.');

  @override
  Future<String> playbackAddress(String url) async => url;

  @override
  Future<void> precache(String url, {int? bytes}) async => _unsupported();

  @override
  Future<bool> contains(String url, {int? bytes}) async => false;

  @override
  Future<int> size() async => 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}
