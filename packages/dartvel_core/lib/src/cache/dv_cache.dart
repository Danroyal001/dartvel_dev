/// `DV.Cache`: the cache an application reads and writes.
///
/// Five calls cover it -- [DVCache.set], [DVCache.get], [DVCache.has],
/// [DVCache.delete] and [DVCache.clear] -- with [DVCache.remember] for
/// compute-on-miss, tags for dropping a group of keys at once, and
/// [DVCache.lock] for work only one caller at a time may do.
///
/// It lives here rather than in the Flutter layer so a backend function, a
/// job and a page all reach the same cache through the same spelling. Where
/// entries are kept is configuration (`dartvel.cache` in pubspec.yaml), not
/// something application code chooses.
library dartvel_core.cache.dv_cache;

import 'dart:async';
import 'dart:math' as math;

import '../../dartvel.dart' show DVCacheTags, DVTenants;
import 'adapters.dart';

/// The cache behind `DV.Cache`.
class DVCache {
  const DVCache();

  static DVCacheAdapter _adapter = DVMemoryCacheAdapter();
  static DVCacheAdapter? _globalAdapter;
  static const DVCacheTags _tags = DVCacheTags();
  static const DVCacheTags _globalTags = DVCacheTags();

  /// In-flight computations, so concurrent callers of the same key share one
  /// compute instead of stampeding it.
  static final Map<String, Future<Object?>> _inFlight =
      <String, Future<Object?>>{};

  static final math.Random _random = math.Random();
  static int _lockSerial = 0;

  /// Swaps the store behind the cache.
  ///
  /// For the framework and for tests. An application names its store in
  /// `dartvel.cache` and the generated server configures it at startup.
  void configure(DVCacheAdapter adapter) {
    _adapter = adapter;
  }

  /// Configures the backend/global cache used by the `global*` helpers.
  void configureGlobal(DVCacheAdapter adapter) {
    _globalAdapter = adapter;
  }

  /// The store currently behind the cache.
  DVCacheAdapter get adapter => _adapter;

  static DVCacheAdapter get _global {
    final DVCacheAdapter? adapter = _globalAdapter;
    if (adapter == null) {
      throw StateError(
        'No global cache is configured. Call DV.Cache.configureGlobal(...) '
        'with the backend/shared cache adapter before using the global '
        'helpers.',
      );
    }
    return adapter;
  }

  /// Scopes [key] to the current tenant, so tenants cannot read each other's
  /// entries through a shared store. The default tenant stays unprefixed:
  /// single-tenant applications keep plain keys.
  static String _scoped(String key) {
    final String tenant = const DVTenants().currentTenant;
    return tenant == DVTenants.defaultTenant ? key : 'tenant:$tenant:$key';
  }

  /// [value] as a [T], or null when it is not one.
  ///
  /// A store that keeps JSON -- a database, Redis, Memcached -- hands a list
  /// back as `List<dynamic>` and a map as `Map<String, dynamic>`, which a
  /// plain `is List<String>` rejects. Treated as a miss, that made
  /// [remember] compute on every call against every store but memory: a
  /// cache that never caches, with nothing to say so. Lists of the JSON
  /// scalars and maps with string keys are converted when every element
  /// fits; anything else is still a miss rather than a wrong value.
  static T? _typed<T>(Object? value) {
    if (value is T) return value;
    if (value is List) {
      Object? list;
      List<E>? all<E>() =>
          value.every((Object? e) => e is E) ? List<E>.from(value) : null;
      if (<String>[] is T) {
        list = all<String>();
      } else if (<int>[] is T) {
        list = all<int>();
      } else if (<double>[] is T) {
        list = all<double>();
      } else if (<num>[] is T) {
        list = all<num>();
      } else if (<bool>[] is T) {
        list = all<bool>();
      } else if (<Map<String, Object?>>[] is T &&
          value.every((Object? e) => e is Map)) {
        list = <Map<String, Object?>>[
          for (final Object? e in value) Map<String, Object?>.from(e! as Map),
        ];
      }
      return list is T ? list : null;
    }
    if (value is Map && <String, Object?>{} is T) {
      return Map<String, Object?>.from(value) as T;
    }
    return null;
  }

  // --- the five calls --------------------------------------------------------

  /// Stores [value] under [key].
  ///
  /// With a [ttl] the entry expires after it; without one it stays until it
  /// is deleted or evicted. [tags] name groups [revalidateTag] can drop.
  Future<void> set(
    String key,
    Object? value, {
    Duration? ttl,
    List<String> tags = const <String>[],
  }) async {
    final String scoped = _scoped(key);
    await _adapter.write(scoped, value, ttl);
    if (tags.isNotEmpty) _tags.tag(scoped, tags);
  }

  /// The value under [key], or null when there is none, it expired, or it is
  /// not a [T].
  Future<T?> get<T>(String key) async =>
      _typed<T>(await _adapter.read(_scoped(key)));

  /// Whether [key] holds a value that has not expired.
  Future<bool> has(String key) async =>
      await _adapter.read(_scoped(key)) != null;

  /// Removes [key].
  Future<void> delete(String key) => _adapter.delete(_scoped(key));

  /// Drops every entry. Tag associations are cleared with it.
  Future<void> clear() async {
    await _adapter.clear();
    _tags.clear();
  }

  // --- remember --------------------------------------------------------------

  /// The value under [key], computing and storing it on a miss.
  ///
  /// Concurrent callers of the same key share one [compute] -- the stampede
  /// a cold cache otherwise sends at an expensive query. A compute that
  /// throws stores nothing.
  ///
  /// [tags] are applied on every call, so a key keeps its tags after the
  /// process that set them restarted.
  ///
  /// With [staleFor], a value older than [ttl] but inside the stale window
  /// is returned at once while one background [compute] refreshes it; past
  /// both, the caller waits for a real value. The key still holds the plain
  /// value, so [get] reads it.
  Future<T> remember<T>(
    String key,
    Future<T> Function() compute, {
    Duration? ttl,
    List<String> tags = const <String>[],
    Duration? staleFor,
  }) async {
    final String scoped = _scoped(key);
    if (tags.isNotEmpty) _tags.tag(scoped, tags);

    final Object? raw = await _adapter.read(scoped);
    final T? cached = raw == null ? null : _typed<T>(raw);
    if (cached != null) {
      if (staleFor != null && ttl != null) {
        final Object? fresh = await _adapter.read(_freshKey(scoped));
        if (fresh == null) {
          // Serve the stale value now; exactly one refresh runs behind it.
          unawaited(
            _compute<T>(
              scoped,
              compute,
              ttl,
              staleFor,
            ).then<void>((_) {}, onError: (Object _) {}),
          );
        }
      }
      return cached;
    }
    return _compute<T>(scoped, compute, ttl, staleFor);
  }

  static String _freshKey(String scoped) => 'dv:fresh:$scoped';

  Future<T> _compute<T>(
    String scoped,
    Future<T> Function() compute,
    Duration? ttl,
    Duration? staleFor,
  ) async {
    final Future<Object?>? pending = _inFlight[scoped];
    if (pending != null) return await pending as T;

    final Future<Object?> future = () async {
      try {
        final T value = await compute();
        if (staleFor != null && ttl != null) {
          // The value outlives its freshness by the stale window; a marker
          // that expires at the ttl says whether it is still fresh, since a
          // store treats expiry as absence and cannot say "old but here".
          await _adapter.write(scoped, value, ttl + staleFor);
          await _adapter.write(_freshKey(scoped), true, ttl);
        } else {
          await _adapter.write(scoped, value, ttl);
        }
        return value as Object?;
      } finally {
        // The removed value is this very future; nothing awaits it here.
        _inFlight.remove(scoped)?.ignore();
      }
    }();
    _inFlight[scoped] = future;
    return await future as T;
  }

  /// The earlier spelling of `remember(key, compute, ttl:, staleFor:)`.
  @Deprecated('Use remember(key, compute, ttl: ..., staleFor: ...).')
  Future<T> staleWhileRevalidate<T>(
    String key, {
    required Duration ttl,
    Duration staleFor = const Duration(minutes: 5),
    required Future<T> Function() compute,
  }) => remember<T>(key, compute, ttl: ttl, staleFor: staleFor);

  // --- tags ------------------------------------------------------------------

  /// Adds [tags] to the entry already under [key].
  void tag(String key, Iterable<String> tags) {
    // Tags record the scoped key: revalidation removes exactly the entries
    // the tenant that tagged them can see.
    _tags.tag(_scoped(key), tags);
  }

  /// Removes every key tagged [tag] and returns their names.
  Future<Set<String>> revalidateTag(String tag) async {
    final Set<String> keys = _tags.revalidateTag(tag);
    for (final String key in keys) {
      await _adapter.delete(key);
    }
    return keys;
  }

  /// The keys currently tagged [tag].
  Set<String> keysForTag(String tag) => _tags.keysForTag(tag);

  /// Every tag that currently has keys under it.
  Set<String> get tags => _tags.tags;

  /// Removes entries whose TTL has elapsed, reclaiming storage. Reads already
  /// ignore expired entries, so this is housekeeping rather than correctness.
  Future<int> purgeExpired() => _adapter.purgeExpired();

  // --- lock ------------------------------------------------------------------

  /// Runs [body] while holding the lock named [key], and releases it
  /// afterwards whether [body] returns or throws.
  ///
  /// Returns what [body] returns, or null when another holder has the lock.
  /// With [wait], a caller that finds the lock held keeps trying for that
  /// long before giving up with null.
  ///
  /// [ttl] bounds how long a holder that died can wedge the lock; a body
  /// that runs longer than it can find a second holder beside it. Across
  /// processes the lock is only as atomic as the store: Redis and Memcached
  /// take it with a compare-and-set, memory and a database serve one process.
  Future<T?> lock<T>(
    String key,
    FutureOr<T> Function() body, {
    Duration ttl = const Duration(seconds: 30),
    Duration? wait,
  }) async {
    final String lockKey = _scoped('dv:lock:$key');
    final DateTime? deadline = wait == null ? null : DateTime.now().add(wait);
    Duration backoff = const Duration(milliseconds: 10);
    String? token;
    while ((token = await _acquire(lockKey, ttl)) == null) {
      final DateTime now = DateTime.now();
      if (deadline == null || !now.isBefore(deadline)) return null;
      final Duration left = deadline.difference(now);
      await Future<void>.delayed(left < backoff ? left : backoff);
      if (backoff < const Duration(milliseconds: 250)) backoff *= 2;
    }
    final DVCacheAdapter adapter = _adapter;
    try {
      return await body();
    } finally {
      // Only if this holder still owns it: a lock that expired and was taken
      // by someone else must not be torn down by the previous owner.
      if (await adapter.read(lockKey) == token) await adapter.delete(lockKey);
    }
  }

  Future<String?> _acquire(String lockKey, Duration ttl) async {
    final String token =
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${_lockSerial++}-${_random.nextInt(0x7fffffff)}';
    final DVCacheAdapter adapter = _adapter;
    if (adapter is DVAtomicCacheAdapter) {
      // The store offers real compare-and-set (Redis SET NX); use it.
      final bool acquired = await (adapter as DVAtomicCacheAdapter)
          .writeIfAbsent(lockKey, token, ttl);
      return acquired ? token : null;
    }
    if (await adapter.read(lockKey) != null) return null;
    await adapter.write(lockKey, token, ttl);
    // Read back: if two acquirers raced, exactly one token survived the
    // second write and only its owner proceeds.
    return await adapter.read(lockKey) == token ? token : null;
  }

  // --- global (backend/shared) cache -----------------------------------------

  Future<T?> globalGet<T>(String key) async =>
      _typed<T>(await _global.read(_scoped(key)));

  Future<void> globalSet(String key, Object? value, {Duration? ttl}) =>
      _global.write(_scoped(key), value, ttl);

  Future<void> globalDelete(String key) => _global.delete(_scoped(key));

  void globalTag(String key, Iterable<String> tags) {
    _globalTags.tag(_scoped(key), tags);
  }

  Future<Set<String>> globalRevalidateTag(String tag) async {
    final Set<String> keys = _globalTags.revalidateTag(tag);
    for (final String key in keys) {
      await _global.delete(key);
    }
    return keys;
  }
}
