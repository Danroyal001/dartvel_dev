/// `DV.Cache`: the cache an application reads and writes.
///
/// Four calls cover it -- [DVCacheView.get], [DVCacheView.set],
/// [DVCacheView.has] and [DVCacheView.delete] -- and everything else is a
/// named option on them: `get` with `compute:` reads through, sharing one
/// compute per key and serving a stale value inside `staleFor:`; `set` takes
/// `tags:`; `delete` drops a key, every key under a [DVCacheTag], or
/// [DVCache.all].
///
/// It lives here rather than in the Flutter layer so a backend function, a
/// job and a page all reach the same cache through the same spelling. The
/// store `DV.Cache` uses is configuration (`dartvel.cache` in pubspec.yaml);
/// [DVCache.withAdapter] switches to another store in code, with the same
/// four calls.
///
/// The machinery -- installing the configured store, the lock, housekeeping
/// and tag inspection -- is [DVCacheRuntime], which the framework imports
/// from `package:dartvel_core/framework.dart` and an application never names.
library dartvel_core.cache.dv_cache;

import 'dart:async';
import 'dart:math' as math;

import '../../dartvel.dart' show DVCacheTags, DVTenants;
import 'adapters.dart';

/// Which keys each tag covers, for one store.
abstract interface class _DVTagRegistry {
  void tag(String key, Iterable<String> tags);

  /// Removes [tag] and returns the keys it covered.
  Set<String> revalidateTag(String tag);

  void clear();
}

/// The configured store's tags: [DVCacheTags], which the CLI, the Studio and
/// the test harness read too.
final class _DVDefaultTags implements _DVTagRegistry {
  const _DVDefaultTags();

  static const DVCacheTags _tags = DVCacheTags();

  @override
  void tag(String key, Iterable<String> tags) => _tags.tag(key, tags);

  @override
  Set<String> revalidateTag(String tag) => _tags.revalidateTag(tag);

  @override
  void clear() => _tags.clear();
}

/// The tags of a store switched to in code, kept apart from every other
/// store's: dropping a tag on one store must not forget keys on another.
final class _DVStoreTags implements _DVTagRegistry {
  final Map<String, Set<String>> _tags = <String, Set<String>>{};

  @override
  void tag(String key, Iterable<String> tags) {
    for (final String tag in tags) {
      (_tags[tag] ??= <String>{}).add(key);
    }
  }

  @override
  Set<String> revalidateTag(String tag) =>
      Set<String>.unmodifiable(_tags.remove(tag) ?? const <String>{});

  @override
  void clear() => _tags.clear();
}

/// Per store rather than per view, so two views of one adapter are one cache.
final Expando<_DVStoreTags> _storeTags = Expando<_DVStoreTags>();

/// In-flight computations per store, so concurrent callers of the same key
/// share one compute instead of stampeding it -- and callers on two stores
/// each get their own.
final Expando<Map<String, Future<Object?>>> _inFlight =
    Expando<Map<String, Future<Object?>>>();

/// What [DVCacheView.delete] drops besides a `String` key: a [DVCacheTag],
/// or [DVCache.all].
///
/// Sealed so a `switch` over `String` and [DVCacheTarget] covers every
/// target, and so nothing outside the cache can add a target `delete` would
/// not know how to drop.
sealed class const DVCacheTarget();

/// Every key tagged [name]: `DV.Cache.delete(const DVCacheTag('products'))`.
///
/// A value, so two tags with the same name are equal.
final class const DVCacheTag(final String name) extends DVCacheTarget {
  @override
  bool operator ==(Object other) => other is DVCacheTag && other.name == name;

  @override
  int get hashCode => Object.hash(DVCacheTag, name);

  @override
  String toString() => "DVCacheTag('$name')";
}

/// [DVCache.all]: every key and every tag.
final class const _DVCacheAll() extends DVCacheTarget {
  @override
  String toString() => 'DVCache.all';
}

/// The four calls, on one store: `DV.Cache`, or the store
/// [DVCache.withAdapter] switched to.
class DVCacheView {
  const DVCacheView._();

  DVCacheAdapter get _store => DVCache._adapter;

  _DVTagRegistry get _tags => const _DVDefaultTags();

  static final math.Random _random = math.Random();
  static int _lockSerial = 0;

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
  /// plain `is List<String>` rejects. Treated as a miss, that made a
  /// read-through [get] compute on every call against every store but
  /// memory: a cache that never caches, with nothing to say so. Lists of the
  /// JSON scalars and maps with string keys are converted when every element
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

  // --- the four calls --------------------------------------------------------

  /// The value under [key], or null when there is none, it expired, or it is
  /// not a [T].
  ///
  /// With [compute] the read goes through: a miss runs [compute], stores what
  /// it returns for [ttl] under [tags], and returns it. Concurrent callers of
  /// the same key share one [compute] -- the stampede a cold cache otherwise
  /// sends at an expensive query -- and a compute that throws stores nothing.
  /// [tags] are applied on every call, so a key keeps its tags after the
  /// process that set them restarted.
  ///
  /// With [staleFor], a value older than [ttl] but inside the stale window
  /// is returned at once while one background [compute] refreshes it; past
  /// both, the caller waits for a real value. The key still holds the plain
  /// value, so a `get` without [compute] reads it.
  ///
  /// [ttl], [tags] and [staleFor] only mean something to a [compute], and
  /// [staleFor] only after a [ttl]; given without them they are an
  /// [ArgumentError] rather than silently ignored.
  Future<T?> get<T>(
    String key, {
    FutureOr<T> Function()? compute,
    Duration? ttl,
    List<String>? tags,
    Duration? staleFor,
  }) async {
    if (compute == null) {
      final String? orphan = ttl != null
          ? 'ttl'
          : tags != null
          ? 'tags'
          : staleFor != null
          ? 'staleFor'
          : null;
      if (orphan != null) {
        throw ArgumentError.value(
          orphan,
          orphan,
          '$orphan: applies to what compute: stores, and no compute: was '
          'given. Store a value with set(key, value, $orphan: ...).',
        );
      }
      return _typed<T>(await _store.read(_scoped(key)));
    }
    if (staleFor != null && ttl == null) {
      throw ArgumentError.value(
        staleFor,
        'staleFor',
        'staleFor: needs a ttl:, the age after which a value is stale.',
      );
    }

    final DVCacheAdapter store = _store;
    final String scoped = _scoped(key);
    if (tags != null && tags.isNotEmpty) _tags.tag(scoped, tags);

    final Object? raw = await store.read(scoped);
    final T? cached = raw == null ? null : _typed<T>(raw);
    if (cached != null) {
      if (staleFor != null && ttl != null) {
        final Object? fresh = await store.read(_freshKey(scoped));
        if (fresh == null) {
          // Serve the stale value now; exactly one refresh runs behind it.
          unawaited(
            _compute<T>(
              store,
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
    return _compute<T>(store, scoped, compute, ttl, staleFor);
  }

  /// Stores [value] under [key].
  ///
  /// With a [ttl] the entry expires after it; without one it stays until it
  /// is deleted or evicted. [tags] name groups that deleting a [DVCacheTag]
  /// drops.
  Future<void> set(
    String key,
    Object? value, {
    Duration? ttl,
    List<String> tags = const <String>[],
  }) async {
    final String scoped = _scoped(key);
    await _store.write(scoped, value, ttl);
    if (tags.isNotEmpty) _tags.tag(scoped, tags);
  }

  /// Whether [key] holds a value that has not expired.
  Future<bool> has(String key) async => await _store.read(_scoped(key)) != null;

  /// Removes what [target] names: a `String` key drops that entry, a
  /// [DVCacheTag] drops every entry tagged with it, and [DVCache.all] drops
  /// every entry and every tag.
  ///
  /// ```dart
  /// await DV.Cache.delete('greeting');                   // a key
  /// await DV.Cache.delete(const DVCacheTag('products')); // every key tagged products
  /// await DV.Cache.delete(DVCache.all);                  // every key
  /// ```
  ///
  /// The parameter is an [Object] because Dart has no union type: a `String`
  /// cannot implement the sealed [DVCacheTarget], and an extension type over
  /// `String` is a `String` at runtime, so a tag spelled that way could not
  /// be told from a key. Anything that is not a `String` or a
  /// [DVCacheTarget] is an [ArgumentError] naming its type, and removes
  /// nothing.
  Future<void> delete(Object target) async {
    switch (target) {
      case final String key:
        await _store.delete(_scoped(key));
      case DVCacheTag(:final String name):
        final DVCacheAdapter store = _store;
        // Tags record the scoped key: this removes exactly the entries the
        // tenant that tagged them can see.
        for (final String scoped in _tags.revalidateTag(name)) {
          await store.delete(scoped);
        }
      case _DVCacheAll():
        await _store.clear();
        _tags.clear();
      default:
        throw ArgumentError.value(
          target,
          'target',
          'delete takes a String key, a DVCacheTag or DVCache.all, not a '
              '${target.runtimeType}',
        );
    }
  }

  // --- read-through ------------------------------------------------------------

  static String _freshKey(String scoped) => 'dv:fresh:$scoped';

  Future<T> _compute<T>(
    DVCacheAdapter store,
    String scoped,
    FutureOr<T> Function() compute,
    Duration? ttl,
    Duration? staleFor,
  ) async {
    final Map<String, Future<Object?>> inFlight = _inFlight[store] ??=
        <String, Future<Object?>>{};
    final Future<Object?>? pending = inFlight[scoped];
    if (pending != null) return await pending as T;

    final Future<Object?> future = () async {
      try {
        final T value = await compute();
        if (staleFor != null && ttl != null) {
          // The value outlives its freshness by the stale window; a marker
          // that expires at the ttl says whether it is still fresh, since a
          // store treats expiry as absence and cannot say "old but here".
          await store.write(scoped, value, ttl + staleFor);
          await store.write(_freshKey(scoped), true, ttl);
        } else {
          await store.write(scoped, value, ttl);
        }
        return value as Object?;
      } finally {
        // The removed value is this very future; nothing awaits it here.
        inFlight.remove(scoped)?.ignore();
      }
    }();
    inFlight[scoped] = future;
    return await future as T;
  }

  // --- lock, for DVCacheRuntime ------------------------------------------------

  Future<T?> _lock<T>(
    String key,
    FutureOr<T> Function() body, {
    required Duration ttl,
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
    final DVCacheAdapter adapter = _store;
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
    final DVCacheAdapter adapter = _store;
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
}

/// The cache behind `DV.Cache`, on the store `dartvel.cache` names.
class DVCache extends DVCacheView {
  const DVCache() : super._();

  /// What `delete` drops to empty a store: every key and every tag.
  ///
  /// `DV.Cache.delete(DVCache.all)`, and the same on a view from
  /// [withAdapter], where it empties that store and no other.
  static const DVCacheTarget all = _DVCacheAll();

  static DVCacheAdapter _adapter = DVMemoryCacheAdapter();
  static DVCacheAdapter? _globalAdapter;

  /// The same four calls on [adapter] instead of the configured store.
  ///
  /// `dartvel.cache` sets the store `DV.Cache` uses; this switches store in
  /// code, for one part of an application that needs another:
  ///
  /// ```dart
  /// final DVCacheView sessions = DV.Cache.withAdapter(
  ///   DVMemcachedCacheAdapter(host: 'cache.internal'),
  /// );
  /// await sessions.set('k', 'v', ttl: const Duration(minutes: 5));
  /// ```
  ///
  /// Every call goes to [adapter] and never to the configured store. Tags
  /// and the shared compute are kept per adapter, so deleting a [DVCacheTag] on
  /// one store leaves another's entries alone, and two views of one adapter
  /// are one cache.
  DVCacheView withAdapter(DVCacheAdapter adapter) => _DVAdapterCache(adapter);
}

/// [DVCache.withAdapter]'s view.
final class _DVAdapterCache extends DVCacheView {
  const _DVAdapterCache(this._adapter) : super._();

  final DVCacheAdapter _adapter;

  @override
  DVCacheAdapter get _store => _adapter;

  @override
  _DVTagRegistry get _tags => _tagsOf(_adapter);
}

/// The tags of [store]: the configured store keeps [DVCacheTags], which the
/// CLI and the Studio read, and any other store keeps its own.
_DVTagRegistry _tagsOf(DVCacheAdapter store) =>
    identical(store, DVCache._adapter)
    ? const _DVDefaultTags()
    : _storeTags[store] ??= _DVStoreTags();

/// [DVCacheRuntime.global]'s view: the store resolved on every call, so it
/// follows [DVCacheRuntime.configureGlobal].
final class _DVGlobalCache extends DVCacheView {
  const _DVGlobalCache() : super._();

  @override
  DVCacheAdapter get _store {
    final DVCacheAdapter? adapter = DVCache._globalAdapter;
    if (adapter == null) {
      throw StateError(
        'No global cache is configured. The framework configures it through '
        'DVCacheRuntime.configureGlobal before anything uses it.',
      );
    }
    return adapter;
  }

  @override
  _DVTagRegistry get _tags => _tagsOf(_store);
}

/// The cache's machinery, for the framework and its tests.
///
/// Exported from `package:dartvel_core/framework.dart` and not from the
/// barrel an application imports. An application reads and writes
/// `DV.Cache`, names its store in `dartvel.cache` and switches store with
/// [DVCache.withAdapter]; the generated server calls [configure], the
/// scheduler and the CLI reach the store, and the Studio's cache explorer
/// reads [tags] and [keysForTag].
abstract final class DVCacheRuntime {
  /// Swaps the store behind `DV.Cache`. The generated server calls this at
  /// startup with the store `dartvel.cache` names.
  static void configure(DVCacheAdapter adapter) {
    DVCache._adapter = adapter;
  }

  /// The store currently behind `DV.Cache`.
  static DVCacheAdapter get adapter => DVCache._adapter;

  /// Sets, or with null removes, the backend/shared cache [global] uses.
  static void configureGlobal(DVCacheAdapter? adapter) {
    DVCache._globalAdapter = adapter;
  }

  /// The backend/shared cache, with the same four calls as `DV.Cache`. Each
  /// call throws a [StateError] until [configureGlobal] has given it a store.
  static DVCacheView get global => const _DVGlobalCache();

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
  static Future<T?> lock<T>(
    String key,
    FutureOr<T> Function() body, {
    Duration ttl = const Duration(seconds: 30),
    Duration? wait,
  }) => const DVCache()._lock<T>(key, body, ttl: ttl, wait: wait);

  /// Removes entries whose TTL has elapsed, reclaiming storage. Reads already
  /// ignore expired entries, so this is housekeeping rather than correctness.
  static Future<int> purgeExpired() => DVCache._adapter.purgeExpired();

  /// The keys currently tagged [tag], as stored: tenant-scoped.
  static Set<String> keysForTag(String tag) =>
      const DVCacheTags().keysForTag(tag);

  /// Every tag that currently has keys under it.
  static Set<String> get tags => const DVCacheTags().tags;
}
