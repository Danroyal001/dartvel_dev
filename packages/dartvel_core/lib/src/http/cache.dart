// HTTP caching layer
import 'dart:async';
import 'dart:convert';

/// Cache entry
class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration? ttl;

  CacheEntry(this.data, {this.ttl}) : timestamp = DateTime.now();

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(timestamp) > ttl!;
  }
}

/// Cache strategy
enum CacheStrategy {
  /// Cache first, network fallback
  cacheFirst,

  /// Network first, cache fallback
  networkFirst,

  /// Cache only
  cacheOnly,

  /// Network only
  networkOnly,

  /// Stale while revalidate
  staleWhileRevalidate,
}

/// HTTP cache
class HttpCache {
  static final _instance = HttpCache._();
  HttpCache._();

  static HttpCache get instance => _instance;

  final Map<String, CacheEntry> _cache = {};

  void set<T>(String key, T data, {Duration? ttl}) {
    _cache[key] = CacheEntry<T>(data, ttl: ttl);
  }

  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    return entry.data as T?;
  }

  void invalidate(String key) {
    _cache.remove(key);
  }

  void invalidatePattern(String pattern) {
    final regex = RegExp(pattern);
    _cache.removeWhere((key, _) => regex.hasMatch(key));
  }

  void clear() {
    _cache.clear();
  }

  bool has(String key) {
    final entry = _cache[key];
    return entry != null && !entry.isExpired;
  }

  int get size => _cache.length;
}

/// Cached HTTP client
class CachedHttpClient {
  final HttpCache cache;
  final Duration defaultTtl;

  CachedHttpClient({
    HttpCache? cache,
    this.defaultTtl = const Duration(minutes: 5),
  }) : cache = cache ?? HttpCache.instance;

  Future<T> get<T>(
    String url, {
    Map<String, String>? headers,
    T Function(dynamic)? decoder,
    CacheStrategy strategy = CacheStrategy.cacheFirst,
    Duration? ttl,
  }) async {
    final cacheKey = _getCacheKey('GET', url, headers);
    final effectiveTtl = ttl ?? defaultTtl;

    switch (strategy) {
      case CacheStrategy.cacheOnly:
        final cached = cache.get<T>(cacheKey);
        if (cached == null) {
          throw Exception('Cache miss and cacheOnly strategy');
        }
        return cached;

      case CacheStrategy.networkOnly:
        final data = await _fetch<T>(url, headers: headers, decoder: decoder);
        cache.set(cacheKey, data, ttl: effectiveTtl);
        return data;

      case CacheStrategy.cacheFirst:
        final cached = cache.get<T>(cacheKey);
        if (cached != null) return cached;

        final data = await _fetch<T>(url, headers: headers, decoder: decoder);
        cache.set(cacheKey, data, ttl: effectiveTtl);
        return data;

      case CacheStrategy.networkFirst:
        try {
          final data = await _fetch<T>(url, headers: headers, decoder: decoder);
          cache.set(cacheKey, data, ttl: effectiveTtl);
          return data;
        } catch (e) {
          final cached = cache.get<T>(cacheKey);
          if (cached != null) return cached;
          rethrow;
        }

      case CacheStrategy.staleWhileRevalidate:
        final cached = cache.get<T>(cacheKey);

        // Fetch in background
        unawaited(
            _fetch<T>(url, headers: headers, decoder: decoder).then((data) {
          cache.set(cacheKey, data, ttl: effectiveTtl);
        }));

        if (cached != null) return cached;

        // If no cache, wait for network
        return _fetch<T>(url, headers: headers, decoder: decoder);
    }
  }

  Future<T> _fetch<T>(
    String url, {
    Map<String, String>? headers,
    T Function(dynamic)? decoder,
  }) async {
    // TODO: Actual HTTP request
    // This is a placeholder
    await Future.delayed(const Duration(milliseconds: 100));

    if (decoder != null) {
      return decoder({});
    }

    return {} as T;
  }

  String _getCacheKey(String method, String url, Map<String, String>? headers) {
    final parts = [method, url];
    if (headers != null && headers.isNotEmpty) {
      parts.add(jsonEncode(headers));
    }
    return parts.join('::');
  }
}
