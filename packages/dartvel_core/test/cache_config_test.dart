// `dartvel.cache` in pubspec.yaml: where DV.Cache keeps its entries.
//
// The block is read twice -- by the build, which refuses one it cannot
// honour, and by the server at startup, which opens the store it names --
// through one reader, so the two cannot disagree about what a key means.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A Redis that answers every command, and remembers what it was sent.
class _FakeRedis implements DVRedisConnection {
  final StreamController<List<int>> _input = StreamController<List<int>>();
  final List<List<String>> commands = <List<String>>[];

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void write(List<int> bytes) {
    final List<String> lines = utf8.decode(bytes).split('\r\n');
    final List<String> parts = <String>[
      for (int i = 2; i < lines.length; i += 2) lines[i],
    ]..removeWhere((String p) => p.isEmpty);
    commands.add(parts);
    final String verb = parts.first.toUpperCase();
    _input.add(
      utf8.encode(switch (verb) {
        'GET' => '\$-1\r\n',
        'PING' => '+PONG\r\n',
        _ => '+OK\r\n',
      }),
    );
  }

  @override
  Future<void> close() => _input.close();
}

/// A Memcached that has nothing stored.
class _FakeMemcached implements DVMemcachedConnection {
  final StreamController<List<int>> _input = StreamController<List<int>>();

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void write(List<int> bytes) => _input.add(utf8.encode('END\r\n'));

  @override
  Future<void> close() => _input.close();
}

TypeMatcher<DVCacheConfigException> _code(String code) =>
    isA<DVCacheConfigException>().having(
      (DVCacheConfigException e) => e.code,
      'code',
      code,
    );

TypeMatcher<DVProcessConfigurationError> _startup(String code) =>
    isA<DVProcessConfigurationError>().having(
      (DVProcessConfigurationError e) => e.message,
      'message',
      contains(code),
    );

void main() {
  tearDown(() {
    const DVCache().configure(DVMemoryCacheAdapter());
    DVMiddlewareSettings.rateLimitStore = null;
  });

  group('reading the block', () {
    test('no block is no configuration: DV.Cache stays in memory', () {
      expect(DVCacheConfig.read(null), isNull);
    });

    test('each store Dartvel has is read', () {
      expect(
        DVCacheConfig.read(<String, Object?>{'store': 'memory'})!.store,
        DVCacheStore.memory,
      );
      expect(
        DVCacheConfig.read(<String, Object?>{'store': 'database'})!.store,
        DVCacheStore.database,
      );
      expect(
        DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${REDIS_URL}',
        })!.store,
        DVCacheStore.redis,
      );
      expect(
        DVCacheConfig.read(<String, Object?>{
          'store': 'memcached',
          'url': 'memcached://cache.internal:11211',
        })!.store,
        DVCacheStore.memcached,
      );
    });

    test(
      'a store Dartvel does not have is DV-CACHE-001, naming the choices',
      () {
        expect(
          () => DVCacheConfig.read(<String, Object?>{'store': 'dynamo'}),
          throwsA(
            _code('DV-CACHE-001').having(
              (DVCacheConfigException e) => e.message,
              'message',
              allOf(contains('dynamo'), contains('redis'), contains('memory')),
            ),
          ),
        );
      },
    );

    test('a block with no store is DV-CACHE-001', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{'url': 'redis://x'}),
        throwsA(_code('DV-CACHE-001')),
      );
    });

    test('a block that is not a map is DV-CACHE-001', () {
      expect(() => DVCacheConfig.read('redis'), throwsA(_code('DV-CACHE-001')));
    });

    test('a misspelt key is refused rather than ignored', () {
      // `prefx` left on the floor would put this application's keys beside
      // every other application's on a shared server.
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${REDIS_URL}',
          'prefx': 'shop:',
        }),
        throwsA(
          _code('DV-CACHE-001').having(
            (DVCacheConfigException e) => e.message,
            'message',
            contains('prefx'),
          ),
        ),
      );
    });

    test('a key the store does not take is refused', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'memory',
          'url': 'redis://x',
        }),
        throwsA(_code('DV-CACHE-001')),
      );
    });

    test('redis and memcached need a url: DV-CACHE-002', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{'store': 'redis'}),
        throwsA(_code('DV-CACHE-002')),
      );
      expect(
        () => DVCacheConfig.read(<String, Object?>{'store': 'memcached'}),
        throwsA(_code('DV-CACHE-002')),
      );
    });

    test('a url for the wrong store is DV-CACHE-002', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': 'memcached://cache.internal',
        }),
        throwsA(_code('DV-CACHE-002')),
      );
    });

    test('rediss is refused rather than sent in the clear', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': 'rediss://cache.internal:6380',
        }),
        throwsA(
          _code('DV-CACHE-002').having(
            (DVCacheConfigException e) => e.message,
            'message',
            contains('TLS'),
          ),
        ),
      );
    });

    test('a password written into pubspec.yaml is DV-CACHE-003, and not '
        'repeated', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': 'redis://:hunter2@cache.internal:6379',
        }),
        throwsA(
          _code('DV-CACHE-003').having(
            (DVCacheConfigException e) => e.message,
            'message',
            allOf(isNot(contains('hunter2')), contains(r'${')),
          ),
        ),
      );
    });

    test('an environment reference is read as the variable it names', () {
      final DVCacheConfig config = DVCacheConfig.read(<String, Object?>{
        'store': 'redis',
        'url': r'${REDIS_URL}',
        'prefix': 'shop:',
      })!;
      expect(config.urlVariable, 'REDIS_URL');
      expect(config.prefix, 'shop:');
    });

    test('a reference that is not one is DV-CACHE-002', () {
      expect(
        () => DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${}',
        }),
        throwsA(_code('DV-CACHE-002')),
      );
    });

    test('the block survives being written out and read again', () {
      // The generated server carries the block as a literal and reads it at
      // startup through this same reader.
      final DVCacheConfig config = DVCacheConfig.read(<String, Object?>{
        'store': 'redis',
        'url': r'${REDIS_URL}',
        'prefix': 'shop:',
      })!;
      final DVCacheConfig again = DVCacheConfig.read(config.toMap())!;
      expect(again.store, DVCacheStore.redis);
      expect(again.urlVariable, 'REDIS_URL');
      expect(again.prefix, 'shop:');
    });
  });

  group('opening the store at startup', () {
    test('memory', () async {
      await DVCacheConfig.read(<String, Object?>{
        'store': 'memory',
      })!.install(database: null, read: (_) => null);
      expect(const DVCache().adapter, isA<DVMemoryCacheAdapter>());
    });

    test('database, on the database this process shares', () async {
      final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
      await DVCacheConfig.read(<String, Object?>{
        'store': 'database',
        'table': 'shop_cache',
      })!.install(database: database, read: (_) => null);

      await const DVCache().set('k', 'v');
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT cache_key FROM shop_cache',
      );
      expect(rows.single['cache_key'], 'k');
    });

    test(
      'database with no database is DV-CACHE-005, before anything serves',
      () async {
        await expectLater(
          DVCacheConfig.read(<String, Object?>{
            'store': 'database',
          })!.install(database: null, read: (_) => null),
          throwsA(_startup('DV-CACHE-005')),
        );
      },
    );

    test('a url variable that is not set is DV-CACHE-004, naming it', () async {
      await expectLater(
        DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${REDIS_URL}',
        })!.install(database: null, read: (_) => null),
        throwsA(
          _startup('DV-CACHE-004').having(
            (DVProcessConfigurationError e) => e.message,
            'message',
            contains('REDIS_URL'),
          ),
        ),
      );
    });

    test('redis: the url from the environment decides host, port, password '
        'and database', () async {
      final _FakeRedis redis = _FakeRedis();
      final List<String> dialled = <String>[];
      await DVCacheConfig.read(<String, Object?>{
        'store': 'redis',
        'url': r'${REDIS_URL}',
        'prefix': 'shop:',
      })!.install(
        database: null,
        read: (String key) =>
            key == 'REDIS_URL' ? 'redis://:s3cret@cache.internal:6380/2' : null,
        redisConnector: (String host, int port) async {
          dialled.add('$host:$port');
          return redis;
        },
      );

      await const DVCache().set('greeting', 'hello');

      expect(dialled, <String>['cache.internal:6380']);
      expect(redis.commands, anyElement(equals(<String>['AUTH', 's3cret'])));
      expect(redis.commands, anyElement(equals(<String>['SELECT', '2'])));
      expect(
        redis.commands.where((List<String> c) => c.first == 'SET').single[1],
        'shop:greeting',
      );
    });

    test(
      'redis also backs the rate limit, so every instance counts together',
      () async {
        await DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${REDIS_URL}',
        })!.install(
          database: null,
          read: (_) => 'redis://cache.internal',
          redisConnector: (String host, int port) async => _FakeRedis(),
        );
        expect(DVMiddlewareSettings.rateLimitStore, isA<DVRedisCacheAdapter>());
      },
    );

    test(
      'a redis that cannot be reached is DV-CACHE-004, without the password',
      () async {
        await expectLater(
          DVCacheConfig.read(<String, Object?>{
            'store': 'redis',
            'url': r'${REDIS_URL}',
          })!.install(
            database: null,
            read: (_) => 'redis://:s3cret@nowhere.invalid:6379',
            redisConnector: (String host, int port) async =>
                throw const SocketException('refused'),
          ),
          throwsA(
            _startup('DV-CACHE-004').having(
              (DVProcessConfigurationError e) => e.message,
              'message',
              isNot(contains('s3cret')),
            ),
          ),
        );
      },
    );

    test('memcached: host and port from the url', () async {
      await DVCacheConfig.read(<String, Object?>{
        'store': 'memcached',
        'url': 'memcached://cache.internal:11212',
        'prefix': 'shop:',
      })!.install(
        database: null,
        read: (_) => null,
        memcachedConnector: (String host, int port) async => _FakeMemcached(),
      );
      final DVCacheAdapter adapter = const DVCache().adapter;
      expect(adapter, isA<DVMemcachedCacheAdapter>());
      adapter as DVMemcachedCacheAdapter;
      expect(adapter.host, 'cache.internal');
      expect(adapter.port, 11212);
      expect(adapter.keyPrefix, 'shop:');
    });
  });

  group('against a real Redis at localhost:6379', () {
    late bool reachable;
    setUpAll(() async {
      try {
        final Socket socket = await Socket.connect(
          '127.0.0.1',
          6379,
          timeout: const Duration(seconds: 1),
        );
        await socket.close();
        reachable = true;
      } on SocketException {
        reachable = false;
      }
    });

    test(
      'the url from the environment reaches it, and DV.Cache writes there',
      () async {
        if (!reachable) {
          markTestSkipped('Start a local redis-server to run this.');
          return;
        }
        await DVCacheConfig.read(<String, Object?>{
          'store': 'redis',
          'url': r'${REDIS_URL}',
          'prefix': 'dartvel_config_test:',
        })!.install(
          database: null,
          read: (String key) =>
              key == 'REDIS_URL' ? 'redis://127.0.0.1:6379/0' : null,
        );

        await const DVCache().set('greeting', 'hello');
        final DVRedisClient raw = await DVRedisClient.connect();
        try {
          expect(
            await raw.command(<String>['GET', 'dartvel_config_test:greeting']),
            '{"v":"hello"}',
          );
          expect(await const DVCache().get<String>('greeting'), 'hello');
        } finally {
          await const DVCache().clear();
          await raw.close();
        }
      },
    );
  });
}
