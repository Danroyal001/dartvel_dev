/// Cache adapters behind `DV.Cache`.
library dartvel_core.cache.adapters;

import 'dart:async';
import 'dart:convert';

import '../database/adapter.dart';

/// Storage behind `DV.Cache`. Expiry is the adapter's responsibility: a read
/// of an expired key must behave exactly like a read of a missing key.
abstract class DVCacheAdapter {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value, Duration? ttl);
  Future<void> remove(String key);
  Future<void> clear();

  /// Removes expired entries. Reads already ignore them; this reclaims space.
  Future<int> purgeExpired();
}

/// Process-local cache. The default, and what `DV.Cache` used exclusively
/// before adapters existed.
class DVMemoryCacheAdapter implements DVCacheAdapter {
  final Map<String, ({Object? value, DateTime? expiresAt})> _entries = {};

  @override
  Future<Object?> read(String key) async {
    final entry = _entries[key];
    if (entry == null) return null;
    final expiresAt = entry.expiresAt;
    if (expiresAt != null && !DateTime.now().isBefore(expiresAt)) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    _entries[key] = (
      value: value,
      expiresAt: ttl == null ? null : DateTime.now().add(ttl),
    );
  }

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<int> purgeExpired() async {
    final now = DateTime.now();
    final expired = <String>[
      for (final entry in _entries.entries)
        if (entry.value.expiresAt case final expiresAt?)
          if (!now.isBefore(expiresAt)) entry.key,
    ];
    for (final key in expired) {
      _entries.remove(key);
    }
    return expired.length;
  }
}

/// Cache backed by a [DVDatabaseAdapter], so cache entries survive process
/// restarts and can share the application's database.
///
/// With [SqliteDVDatabaseAdapter] this is the zero-config persistent cache the
/// spec calls for; the same adapter works over any future SQL adapter.
///
/// Values are stored as JSON, so only JSON-encodable values can be cached.
/// A value that cannot be encoded raises [ArgumentError] on [write] rather
/// than being silently dropped. Note the round trip is JSON's, not Dart's:
/// a `List<String>` returns as `List<dynamic>`, so read it back as
/// `List<Object?>` and convert.
class DVDatabaseCacheAdapter implements DVCacheAdapter {
  final DVDatabaseAdapter database;
  final String tableName;

  bool _initialized = false;

  DVDatabaseCacheAdapter(
    this.database, {
    this.tableName = 'dartvel_cache',
  }) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Cache table names must be plain SQL identifiers.',
      );
    }
  }

  /// Creates the backing table when it does not exist. Called automatically on
  /// first use; call it eagerly at boot to surface schema errors early.
  Future<void> initialize() async {
    if (_initialized) return;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        expires_at INTEGER
      )
    ''');
    _initialized = true;
  }

  @override
  Future<Object?> read(String key) async {
    await initialize();
    final rows = await database.query(
      'SELECT value, expires_at FROM $tableName WHERE key = ?',
      <Object?>[key],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final expiresAt = row['expires_at'];
    if (expiresAt is int &&
        DateTime.now().millisecondsSinceEpoch >= expiresAt) {
      await remove(key);
      return null;
    }

    final encoded = row['value'];
    if (encoded is! String) return null;
    return _decode(encoded);
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    await initialize();
    final encoded = _encode(key, value);
    final expiresAt =
        ttl == null ? null : DateTime.now().add(ttl).millisecondsSinceEpoch;

    await database.execute(
      'INSERT INTO $tableName (key, value, expires_at) VALUES (?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value, '
      'expires_at = excluded.expires_at',
      <Object?>[key, encoded, expiresAt],
    );
  }

  @override
  Future<void> remove(String key) async {
    await initialize();
    await database.execute(
      'DELETE FROM $tableName WHERE key = ?',
      <Object?>[key],
    );
  }

  @override
  Future<void> clear() async {
    await initialize();
    await database.execute('DELETE FROM $tableName');
  }

  @override
  Future<int> purgeExpired() async {
    await initialize();
    return database.execute(
      'DELETE FROM $tableName WHERE expires_at IS NOT NULL AND expires_at <= ?',
      <Object?>[DateTime.now().millisecondsSinceEpoch],
    );
  }

  static String _encode(String key, Object? value) {
    try {
      return jsonEncode(<String, Object?>{'v': value});
    } on JsonUnsupportedObjectError catch (error) {
      throw ArgumentError.value(
        value,
        'value',
        'Cache entry "$key" is not JSON-encodable and cannot be persisted '
            '(${error.unsupportedObject.runtimeType}). Cache a serialisable '
            'representation, or use DVMemoryCacheAdapter.',
      );
    }
  }

  static Object? _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    return decoded is Map<String, Object?> ? decoded['v'] : null;
  }
}
