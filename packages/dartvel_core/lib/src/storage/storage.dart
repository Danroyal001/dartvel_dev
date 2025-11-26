// Storage abstraction layer - works across all platforms
import 'dart:async';
import 'dart:convert';

/// Storage provider interface
abstract class StorageProvider {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();
  Future<List<String>> keys();
  Future<bool> has(String key);
}

/// Storage with type-safe operations
class Storage {
  final StorageProvider provider;

  Storage(this.provider);

  /// Write string
  Future<void> setString(String key, String value) =>
      provider.write(key, value);

  /// Read string
  Future<String?> getString(String key) => provider.read(key);

  /// Write int
  Future<void> setInt(String key, int value) =>
      provider.write(key, value.toString());

  /// Read int
  Future<int?> getInt(String key) async {
    final value = await provider.read(key);
    return value != null ? int.tryParse(value) : null;
  }

  /// Write double
  Future<void> setDouble(String key, double value) =>
      provider.write(key, value.toString());

  /// Read double
  Future<double?> getDouble(String key) async {
    final value = await provider.read(key);
    return value != null ? double.tryParse(value) : null;
  }

  /// Write bool
  Future<void> setBool(String key, bool value) =>
      provider.write(key, value.toString());

  /// Read bool
  Future<bool?> getBool(String key) async {
    final value = await provider.read(key);
    return value?.toLowerCase() == 'true';
  }

  /// Write JSON
  Future<void> setJson(String key, Map<String, dynamic> value) =>
      provider.write(key, jsonEncode(value));

  /// Read JSON
  Future<Map<String, dynamic>?> getJson(String key) async {
    final value = await provider.read(key);
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Write list
  Future<void> setStringList(String key, List<String> value) =>
      provider.write(key, jsonEncode(value));

  /// Read list
  Future<List<String>?> getStringList(String key) async {
    final value = await provider.read(key);
    if (value == null) return null;
    try {
      final list = jsonDecode(value) as List;
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  /// Delete key
  Future<void> remove(String key) => provider.delete(key);

  /// Clear all
  Future<void> clear() => provider.clear();

  /// Get all keys
  Future<List<String>> keys() => provider.keys();

  /// Check if key exists
  Future<bool> has(String key) => provider.has(key);
}

/// In-memory storage provider (for testing/debugging)
class InMemoryStorageProvider implements StorageProvider {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }

  @override
  Future<List<String>> keys() async {
    return _data.keys.toList();
  }

  @override
  Future<bool> has(String key) async {
    return _data.containsKey(key);
  }
}

/// Secure storage (for sensitive data)
abstract class SecureStorageProvider {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class SecureStorage {
  final SecureStorageProvider provider;

  SecureStorage(this.provider);

  Future<void> write(String key, String value) => provider.write(key, value);
  Future<String?> read(String key) => provider.read(key);
  Future<void> delete(String key) => provider.delete(key);
  Future<void> deleteAll() => provider.deleteAll();

  /// Store token
  Future<void> setToken(String token) => write('auth_token', token);
  Future<String?> getToken() => read('auth_token');
  Future<void> deleteToken() => delete('auth_token');
}
