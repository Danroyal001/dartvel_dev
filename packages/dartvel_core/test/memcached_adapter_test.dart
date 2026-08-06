// Runs against a real memcached at localhost:11211 — no scripted server.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<bool> _reachable() async {
  try {
    final socket = await Socket.connect('127.0.0.1', 11211,
        timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() async {
  if (!await _reachable()) {
    test(
      'memcached adapter (skipped: nothing at localhost:11211)',
      () {},
      skip: 'Start memcached to run these.',
    );
    return;
  }

  late DVMemcachedCacheAdapter adapter;

  setUp(() async {
    adapter = DVMemcachedCacheAdapter(keyPrefix: 'dvtest:');
    await adapter.clear();
  });

  tearDown(() => adapter.close());

  test('write and read round-trip structured values', () async {
    await adapter.write('user', <String, Object?>{'name': 'Ada', 'age': 36},
        null);

    expect(await adapter.read('user'),
        <String, Object?>{'name': 'Ada', 'age': 36});
    expect(await adapter.read('absent'), isNull);
  });

  test('TTL expiry is memcached\'s own', () async {
    await adapter.write('gone', 'x', const Duration(seconds: 1));

    expect(await adapter.read('gone'), 'x');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(await adapter.read('gone'), isNull);
  });

  test('remove deletes a key', () async {
    await adapter.write('a', 1, null);
    await adapter.remove('a');

    expect(await adapter.read('a'), isNull);
  });

  test('writeIfAbsent admits exactly one winner under contention', () async {
    final results = await Future.wait(<Future<bool>>[
      for (var i = 0; i < 8; i++)
        adapter.writeIfAbsent('lock', 'holder-$i', const Duration(seconds: 5)),
    ]);

    // `add` is memcached's compare-and-set for absence, which is what a
    // distributed lock needs.
    expect(results.where((bool won) => won), hasLength(1));
  });

  test('multi-byte values survive the byte-counted protocol', () async {
    // The protocol counts bytes, not characters; a length mistake here
    // desynchronises every later reply on the connection.
    await adapter.write('unicode', 'naïve — 😀 café', null);

    expect(await adapter.read('unicode'), 'naïve — 😀 café');
    // The connection is still coherent afterwards.
    await adapter.write('after', 'ok', null);
    expect(await adapter.read('after'), 'ok');
  });

  test('a key too long for memcached is still usable', () async {
    // Keys cap at 250 bytes and reject control characters; sending one
    // verbatim would fail silently.
    final long = 'x' * 400;
    await adapter.write(long, 'value', null);

    expect(await adapter.read(long), 'value');
  });

  test('a key containing spaces does not corrupt the command', () async {
    await adapter.write('with spaces and\ttabs', 'value', null);

    expect(await adapter.read('with spaces and\ttabs'), 'value');
  });

  test('many operations stay in sequence on one connection', () async {
    for (var i = 0; i < 20; i++) {
      await adapter.write('k$i', i, null);
    }
    for (var i = 0; i < 20; i++) {
      expect(await adapter.read('k$i'), i);
    }
  });

  test('purgeExpired reports zero because memcached expires its own keys',
      () async {
    expect(await adapter.purgeExpired(), 0);
  });
}
