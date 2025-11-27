import 'dart:async';

/// Cache interface
abstract class Cache {
  Future<void> set(String key, dynamic value, {Duration? ttl});
  Future<dynamic> get(String key);
  Future<bool> has(String key);
  Future<void> delete(String key);
  Future<void> clear();
}

/// In-memory cache implementation
class InMemoryCache implements Cache {
  final Map<String, _CacheEntry> _store = {};

  @override
  Future<void> set(String key, dynamic value, {Duration? ttl}) async {
    final expiry = ttl != null ? DateTime.now().add(ttl) : null;
    _store[key] = _CacheEntry(value, expiry);
  }

  @override
  Future<dynamic> get(String key) async {
    final entry = _store[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }

    return entry.value;
  }

  @override
  Future<bool> has(String key) async {
    final entry = _store[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

class _CacheEntry {
  final dynamic value;
  final DateTime? expiry;

  _CacheEntry(this.value, this.expiry);

  bool get isExpired => expiry != null && DateTime.now().isAfter(expiry!);
}
