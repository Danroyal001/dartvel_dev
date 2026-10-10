/// The disk cache players read remote media through.
///
/// One cache for every player on a target with a filesystem, in Dart rather
/// than in each platform player: ExoPlayer, AVPlayer, GStreamer and Media
/// Foundation each have a different idea of caching (or none), and a feature
/// that works on one of them is a feature an application cannot rely on.
/// What every one of them can do is open an HTTP URL, so the cache is a
/// loopback HTTP server: the player opens `http://127.0.0.1:<port>/<key>`, the
/// cache answers from disk what it has and fetches from the origin, keeping
/// it, what it does not.
///
/// In a browser there is no filesystem to keep it in and the browser's own
/// HTTP cache does this job; `precache` there asks the browser to fetch.
library;

export 'media_cache_stub.dart' if (dart.library.io) 'media_cache_io.dart';

/// Where players get remote media from.
abstract interface class DVMediaCache {
  /// What a player should open for [url]: a loopback address that streams it
  /// through the cache, or [url] itself for anything that is not `http:` or
  /// `https:`.
  Future<String> playbackAddress(String url);

  /// Fetches [url] into the cache before anything plays it: the first
  /// [bytes] of it, or all of it when [bytes] is null. Completes when the
  /// bytes are on disk; throws `HttpException` when the origin refuses.
  Future<void> precache(String url, {int? bytes});

  /// Whether the first [bytes] of [url] -- all of it, when null -- are on
  /// disk.
  Future<bool> contains(String url, {int? bytes});

  /// Bytes on disk.
  Future<int> size();

  /// Deletes everything not being read right now.
  Future<void> clear();

  /// Stops the loopback server. Addresses it handed out stop working.
  Future<void> close();
}
