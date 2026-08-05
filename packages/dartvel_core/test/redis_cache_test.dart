// Runs against a real Redis at localhost:6379 — no scripted server, no fake.
// When none is reachable the suite skips visibly rather than passing silently.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<bool> _redisReachable() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      6379,
      timeout: const Duration(seconds: 1),
    );
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _redisReachable()) {
    test(
      'redis cache adapter (skipped: no Redis at localhost:6379)',
      () {},
      skip: 'Start a local redis-server to run the Redis adapter tests.',
    );
    return;
  }

  late DVRedisClient client;
  late DVRedisCacheAdapter adapter;

  setUp(() async {
    client = await DVRedisClient.connect();
    adapter = DVRedisCacheAdapter(client, keyPrefix: 'dartvel_test:');
    await adapter.clear();
  });

  tearDown(() async {
    await adapter.clear();
    await client.close();
  });

  test('write/read round-trips structured values', () async {
    await adapter.write('user', <String, Object?>{'name': 'Ada', 'age': 36}, null);

    expect(
      await adapter.read('user'),
      <String, Object?>{'name': 'Ada', 'age': 36},
    );
    expect(await adapter.read('absent'), isNull);
  });

  test('TTL expiry is Redis\'s own, not bookkeeping', () async {
    await adapter.write('gone', 'x', const Duration(milliseconds: 60));

    expect(await adapter.read('gone'), 'x');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await adapter.read('gone'), isNull);
  });

  test('remove and clear touch only this application\'s keys', () async {
    await adapter.write('a', 1, null);
    await adapter.write('b', 2, null);
    // A neighbour's key outside the prefix must survive clear().
    await client.command(<String>['SET', 'other_app:key', 'keep']);

    await adapter.remove('a');
    expect(await adapter.read('a'), isNull);

    await adapter.clear();
    expect(await adapter.read('b'), isNull);
    expect(
      await client.command(<String>['GET', 'other_app:key']),
      'keep',
    );
    await client.command(<String>['DEL', 'other_app:key']);
  });

  test('writeIfAbsent is atomic: one winner under contention', () async {
    final results = await Future.wait(<Future<bool>>[
      for (var i = 0; i < 8; i++)
        adapter.writeIfAbsent('lock', 'holder-$i', const Duration(seconds: 5)),
    ]);

    expect(results.where((bool won) => won), hasLength(1),
        reason: 'SET NX must admit exactly one of the racing acquirers');
  });

  test('multi-byte values survive: RESP counts bytes, not characters',
      () async {
    // 'naïve—😀' is longer in UTF-8 bytes than in characters; a client that
    // wrote string lengths would corrupt the stream here.
    await adapter.write('unicode', 'naïve—😀', null);

    expect(await adapter.read('unicode'), 'naïve—😀');
    // The connection is still coherent for the next command.
    await adapter.write('after', 'ok', null);
    expect(await adapter.read('after'), 'ok');
  });

  test('an error reply surfaces as DVRedisException, not a hang', () async {
    await expectLater(
      client.command(<String>['NOSUCHCOMMAND']),
      throwsA(isA<DVRedisException>()),
    );
    // And the connection keeps working afterwards.
    expect(await client.command(<String>['PING']), 'PONG');
  });
}
