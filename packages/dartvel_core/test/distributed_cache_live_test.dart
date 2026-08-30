// The distributed cache over real Redis nodes.
//
// The unit tests prove the placement maths with fake nodes. This proves the
// thing they cannot: that keys really land on separate servers, that a key
// written through the distributed adapter is readable from the node that
// should hold it and absent from the one that should not, and that the lock is
// atomic against a server rather than against a Dart map.
@Tags(<String>['live'])
library;

import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// `host:port,host:port` — two or more Redis servers.
List<({String host, int port})> parseNodes(String value) => value
    .split(',')
    .map((String entry) => entry.trim())
    .where((String entry) => entry.isNotEmpty)
    .map((String entry) {
      final List<String> parts = entry.split(':');
      return (host: parts.first, port: int.parse(parts.last));
    })
    .toList();

void main() {
  final String? configured = io.Platform.environment['DARTVEL_REDIS_NODES'];
  if (configured == null || configured.isEmpty) {
    test('skipped: DARTVEL_REDIS_NODES is not set', () {}, skip: true);
    return;
  }

  final List<({String host, int port})> endpoints = parseNodes(configured);
  late Map<String, DVRedisCacheAdapter> adapters;
  late DVDistributedCacheAdapter cache;

  setUpAll(() async {
    adapters = <String, DVRedisCacheAdapter>{};
    for (final ({String host, int port}) endpoint in endpoints) {
      final DVRedisClient client = await DVRedisClient.connect(
        host: endpoint.host,
        port: endpoint.port,
      );
      adapters['${endpoint.host}:${endpoint.port}'] =
          DVRedisCacheAdapter(client, keyPrefix: 'dvtest:');
    }
    cache = DVDistributedCacheAdapter(nodes: adapters);
  });

  setUp(() async {
    await cache.clear();
  });

  test('there really is more than one server', () {
    // A "distributed" cache over one node would pass everything below while
    // proving nothing about distribution.
    expect(endpoints.length, greaterThan(1));
  });

  test('a value written comes back through the cache', () async {
    await cache.write('greeting', 'hello', null);

    expect(await cache.read('greeting'), 'hello');
  });

  test('it lives on the owning server and nowhere else', () async {
    await cache.write('greeting', 'hello', null);

    final String owner = cache.nodesFor('greeting').first;
    for (final MapEntry<String, DVRedisCacheAdapter> node in adapters.entries) {
      final Object? direct = await node.value.read('greeting');
      if (node.key == owner) {
        expect(direct, 'hello', reason: '${node.key} should hold it');
      } else {
        expect(direct, isNull, reason: '${node.key} should not');
      }
    }
  });

  test('keys spread across the servers rather than piling on one', () async {
    for (int i = 0; i < 60; i += 1) {
      await cache.write('spread:$i', i, null);
    }

    final Map<String, int> held = <String, int>{};
    for (final MapEntry<String, DVRedisCacheAdapter> node in adapters.entries) {
      int count = 0;
      for (int i = 0; i < 60; i += 1) {
        if (await node.value.read('spread:$i') != null) count += 1;
      }
      held[node.key] = count;
    }

    expect(held.values.reduce((int a, int b) => a + b), 60);
    for (final int count in held.values) {
      expect(count, greaterThan(0), reason: 'every server should hold some');
    }
  });

  test('the lock is atomic against the server', () async {
    // The unit test proves this against a Dart map. Against Redis it is SET NX
    // that has to be doing the work.
    expect(await cache.writeIfAbsent('lock:job', 'first', null), isTrue);
    expect(await cache.writeIfAbsent('lock:job', 'second', null), isFalse);
    expect(await cache.read('lock:job'), 'first');
  });

  test('a ttl expires the entry', () async {
    await cache.write('brief', 'value', const Duration(seconds: 1));
    expect(await cache.read('brief'), 'value');

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(await cache.read('brief'), isNull);
  });

  test('clear empties every server, not only the one a key mapped to',
      () async {
    for (int i = 0; i < 20; i += 1) {
      await cache.write('bulk:$i', i, null);
    }
    await cache.clear();

    for (int i = 0; i < 20; i += 1) {
      expect(await cache.read('bulk:$i'), isNull);
    }
  });
}
