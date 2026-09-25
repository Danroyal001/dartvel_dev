/// `dartvel.cache` in pubspec.yaml: where `DV.Cache` keeps its entries.
///
/// ```yaml
/// dartvel:
///   cache:
///     store: redis          # memory | database | redis | memcached
///     url: ${REDIS_URL}     # redis and memcached; an environment variable
///     prefix: "shop:"       # redis and memcached; default "dartvel:"
/// ```
///
/// Read twice through [DVCacheConfig.read]: by the build, which refuses a
/// block it cannot honour (`DV-CACHE-001` to `003`), and by the generated
/// server at startup, which opens the store and refuses to start when it
/// cannot (`DV-CACHE-004`, `005`). One reader means the build and the running
/// process cannot disagree about what a key means.
///
/// Choosing the store is configuration rather than code on purpose: the
/// adapters, the Redis client and the connection are how the framework
/// delivers a cache, not things an application should have to construct.
library dartvel_core.cache.cache_config;

import 'dart:async';

import '../database/adapter.dart' show DVDatabaseAdapter;
import '../middleware/middleware_runtime.dart' show DVMiddlewareSettings;
import '../process/process_configuration.dart' show DVProcessConfigurationError;
import '../secrets/secrets.dart' show DVSecrets;
import 'adapters.dart';
import 'dv_cache.dart';
import 'memcached.dart';
import 'redis.dart';

/// The stores `dartvel.cache.store` can name.
enum DVCacheStore {
  /// This process's memory. The default, and right for one process.
  memory,

  /// A table in the database this deployment's processes share.
  database,

  /// Redis, or Valkey.
  redis,

  /// Memcached.
  memcached,
}

/// A `dartvel.cache` block Dartvel cannot honour, found by the build.
final class DVCacheConfigException implements Exception {
  const DVCacheConfigException(this.code, this.message);

  /// `DV-CACHE-001`, `002` or `003`.
  final String code;

  final String message;

  @override
  String toString() => '$code: $message';
}

/// A read `dartvel.cache` block.
final class DVCacheConfig {
  const DVCacheConfig._({
    required this.store,
    this.url,
    this.prefix,
    this.table,
  });

  /// Where entries are kept.
  final DVCacheStore store;

  /// The url as written: a literal without credentials, or `${NAME}`.
  final String? url;

  /// What this application's keys start with on a shared server.
  final String? prefix;

  /// The table a database store keeps entries in.
  final String? table;

  static final RegExp _reference = RegExp(r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$');

  static const Map<DVCacheStore, Set<String>> _keys =
      <DVCacheStore, Set<String>>{
        DVCacheStore.memory: <String>{'store'},
        DVCacheStore.database: <String>{'store', 'table'},
        DVCacheStore.redis: <String>{'store', 'url', 'prefix'},
        DVCacheStore.memcached: <String>{'store', 'url', 'prefix'},
      };

  static const Map<DVCacheStore, String> _schemes = <DVCacheStore, String>{
    DVCacheStore.redis: 'redis',
    DVCacheStore.memcached: 'memcached',
  };

  /// The environment variable [url] names, or null when it is a literal.
  String? get urlVariable =>
      url == null ? null : _reference.firstMatch(url!)?.group(1);

  /// Reads [block], the value of `dartvel.cache`. Null when there is none,
  /// which leaves `DV.Cache` in memory.
  ///
  /// Throws [DVCacheConfigException] for anything it cannot honour: a store
  /// or key Dartvel does not have (`DV-CACHE-001`), a missing or unusable url
  /// (`DV-CACHE-002`), and a password written out in pubspec.yaml rather than
  /// read from the environment (`DV-CACHE-003`).
  static DVCacheConfig? read(Object? block) {
    if (block == null) return null;
    if (block is! Map) {
      throw DVCacheConfigException(
        'DV-CACHE-001',
        'dartvel.cache must be a map with a store, not "$block".',
      );
    }
    final Object? written = block['store'];
    final String accepted = DVCacheStore.values.map((s) => s.name).join(', ');
    if (written == null) {
      throw DVCacheConfigException(
        'DV-CACHE-001',
        'dartvel.cache names no store. Accepted: $accepted.',
      );
    }
    final DVCacheStore? store = DVCacheStore.values
        .where((DVCacheStore s) => s.name == '$written'.trim())
        .firstOrNull;
    if (store == null) {
      throw DVCacheConfigException(
        'DV-CACHE-001',
        'dartvel.cache.store: "$written" is not a store Dartvel has. '
            'Accepted: $accepted.',
      );
    }
    final Set<String> allowed = _keys[store]!;
    for (final Object? key in block.keys) {
      if (!allowed.contains('$key')) {
        throw DVCacheConfigException(
          'DV-CACHE-001',
          'dartvel.cache.$key is not something the ${store.name} store '
              'takes. It takes: ${allowed.join(', ')}.',
        );
      }
    }

    String? text(String key) {
      final Object? value = block[key];
      if (value == null) return null;
      final String trimmed = '$value'.trim();
      if (trimmed.isEmpty) {
        throw DVCacheConfigException(
          key == 'url' ? 'DV-CACHE-002' : 'DV-CACHE-001',
          'dartvel.cache.$key is empty.',
        );
      }
      return trimmed;
    }

    final String? url = text('url');
    final String? prefix = text('prefix');
    final String? table = text('table');

    final String? scheme = _schemes[store];
    if (scheme != null) {
      if (url == null) {
        throw DVCacheConfigException(
          'DV-CACHE-002',
          'dartvel.cache.store: ${store.name} needs a url, such as '
              'url: \${${store == DVCacheStore.redis ? 'REDIS_URL' : 'MEMCACHED_URL'}}. '
              'Without one each server would use a cache of its own on '
              'localhost and a lock would lock nothing.',
        );
      }
      if (url.startsWith(r'${')) {
        if (!_reference.hasMatch(url)) {
          throw DVCacheConfigException(
            'DV-CACHE-002',
            'dartvel.cache.url: "$url" is not an environment reference. '
                r'Write ${NAME}, with NAME the variable holding the url.',
          );
        }
      } else {
        _checkUrl(store, url, atBuild: true);
      }
    }
    if (prefix != null &&
        store == DVCacheStore.memcached &&
        RegExp(r'[\x00-\x20\x7f]').hasMatch(prefix)) {
      throw const DVCacheConfigException(
        'DV-CACHE-001',
        'dartvel.cache.prefix may not hold spaces or control characters on '
            'Memcached, which refuses such keys.',
      );
    }
    if (table != null && !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table)) {
      throw DVCacheConfigException(
        'DV-CACHE-001',
        'dartvel.cache.table: "$table" is not a plain table name.',
      );
    }
    return DVCacheConfig._(
      store: store,
      url: url,
      prefix: prefix,
      table: table,
    );
  }

  /// Parses [url] for [store], throwing `DV-CACHE-002` or `003`.
  ///
  /// Never repeats a url that carries a password: it would land in a build
  /// log or a crash report.
  static Uri _checkUrl(
    DVCacheStore store,
    String url, {
    required bool atBuild,
  }) {
    final String scheme = _schemes[store]!;
    final String where = atBuild
        ? 'dartvel.cache.url'
        : 'The url dartvel.cache.url reads';
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw DVCacheConfigException(
        'DV-CACHE-002',
        '$where is not a $scheme:// url with a host.',
      );
    }
    if (uri.scheme == 'rediss' && store == DVCacheStore.redis) {
      throw const DVCacheConfigException(
        'DV-CACHE-002',
        'dartvel.cache.url uses rediss://, and Dartvel\'s Redis client has '
            'no TLS. It is refused rather than sent in the clear; reach Redis '
            'over a private network or a TLS tunnel with redis://.',
      );
    }
    if (uri.scheme != scheme) {
      throw DVCacheConfigException(
        'DV-CACHE-002',
        '$where must be a $scheme:// url for the ${store.name} store, not '
            '${uri.scheme}://.',
      );
    }
    final String userInfo = uri.userInfo;
    if (store == DVCacheStore.memcached && userInfo.isNotEmpty) {
      throw const DVCacheConfigException(
        'DV-CACHE-002',
        'dartvel.cache.url carries credentials, and Memcached\'s protocol '
            'has no way to present them.',
      );
    }
    if (atBuild &&
        userInfo.contains(':') &&
        userInfo.substring(userInfo.indexOf(':') + 1).isNotEmpty) {
      throw const DVCacheConfigException(
        'DV-CACHE-003',
        'dartvel.cache.url has a password written into pubspec.yaml, which '
            'is committed and shipped. Put the url in an environment '
            r'variable and write url: ${REDIS_URL}.',
      );
    }
    if (store == DVCacheStore.redis) {
      final String path = uri.path.replaceFirst('/', '');
      if (path.isNotEmpty && int.tryParse(path) == null) {
        throw DVCacheConfigException(
          'DV-CACHE-002',
          '$where names database "$path"; a Redis database is a number.',
        );
      }
    }
    return uri;
  }

  /// This block as the map it was read from, for the generated server to
  /// carry and read again at startup.
  Map<String, Object?> toMap() => <String, Object?>{
    'store': store.name,
    if (url != null) 'url': url,
    if (prefix != null) 'prefix': prefix,
    if (table != null) 'table': table,
  };

  /// Opens the store and puts `DV.Cache` on it.
  ///
  /// Called by the generated server before it serves, works or ticks
  /// anything. [database] is the database this process shares with the rest
  /// of its deployment, which a database store needs; [read] looks up the
  /// variable a `${NAME}` url names, `DV.Secrets` by default.
  ///
  /// A shared store that can count also carries the rate limit, so a
  /// deployment of several instances has one budget per caller rather than
  /// one per instance.
  ///
  /// Throws [DVProcessConfigurationError] with `DV-CACHE-004` when the url
  /// is unset, unusable or unreachable, and `DV-CACHE-005` for a database
  /// store with no database. A process believing it has a shared cache
  /// while each instance keeps its own would take locks that lock nothing,
  /// so it does not start.
  Future<void> install({
    required DVDatabaseAdapter? database,
    String? Function(String key)? read,
    DVRedisConnect? redisConnector,
    DVMemcachedConnect? memcachedConnector,
  }) async {
    final DVCacheAdapter adapter = await _open(
      database: database,
      read: read ?? const DVSecrets().maybeGet,
      redisConnector: redisConnector,
      memcachedConnector: memcachedConnector,
    );
    DVCacheRuntime.configure(adapter);
    if (store != DVCacheStore.memory && adapter is DVCountingCacheAdapter) {
      DVMiddlewareSettings.rateLimitStore ??= adapter;
    }
  }

  Future<DVCacheAdapter> _open({
    required DVDatabaseAdapter? database,
    required String? Function(String key) read,
    DVRedisConnect? redisConnector,
    DVMemcachedConnect? memcachedConnector,
  }) async {
    switch (store) {
      case DVCacheStore.memory:
        return DVMemoryCacheAdapter();
      case DVCacheStore.database:
        if (database == null) {
          throw const DVProcessConfigurationError(
            'DV-CACHE-005: dartvel.cache.store is database and this process '
            'shares no database: DATABASE_URL is not set. Set it, or choose '
            'another store.',
          );
        }
        final DVDatabaseCacheAdapter adapter = DVDatabaseCacheAdapter(
          database,
          tableName: table ?? 'dartvel_cache',
        );
        await adapter.initialize();
        return adapter;
      case DVCacheStore.redis:
      case DVCacheStore.memcached:
        final Uri uri = _resolve(read);
        final String host = uri.host;
        final int port = uri.hasPort
            ? uri.port
            : (store == DVCacheStore.redis ? 6379 : 11211);
        final String keyPrefix = prefix ?? 'dartvel:';
        try {
          if (store == DVCacheStore.memcached) {
            final DVMemcachedCacheAdapter adapter = DVMemcachedCacheAdapter(
              host: host,
              port: port,
              keyPrefix: keyPrefix,
              connector: memcachedConnector,
            );
            // Connects now rather than on the first request that reads.
            await adapter.read('dv:ping').timeout(const Duration(seconds: 10));
            return adapter;
          }
          // The same connect an application switching in code uses, so the
          // configured store and a switched one authenticate alike.
          return await DVRedisCacheAdapter.connect(
            uri.toString(),
            keyPrefix: keyPrefix,
            connector: redisConnector,
          ).timeout(const Duration(seconds: 10));
        } on Object catch (error) {
          throw DVProcessConfigurationError(
            'DV-CACHE-004: dartvel.cache could not open ${store.name} at '
            '$host:$port (${error.runtimeType}${error is DVRedisException ? ': ${error.message}' : ''}). '
            'The server does not start on a cache of its own instead.',
          );
        }
    }
  }

  Uri _resolve(String? Function(String key) read) {
    final String? variable = urlVariable;
    String? value = url;
    if (variable != null) {
      value = read(variable)?.trim();
      if (value == null || value.isEmpty) {
        throw DVProcessConfigurationError(
          'DV-CACHE-004: dartvel.cache.url reads $variable, which is not set. '
          'Set it to the ${store.name} url, in the environment or in .env.',
        );
      }
    }
    try {
      return _checkUrl(store, value!, atBuild: false);
    } on DVCacheConfigException catch (error) {
      throw DVProcessConfigurationError(
        'DV-CACHE-004: ${variable ?? 'dartvel.cache.url'}: ${error.message}',
      );
    }
  }
}
