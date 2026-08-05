/// Redis support: the RESP protocol client plus the cache adapter built on it.
library dartvel_core.cache.redis;

import 'dart:async';
import 'dart:convert';

import 'adapters.dart';
import 'redis_socket_unsupported.dart'
    if (dart.library.io) 'redis_socket_io.dart';

/// One Redis connection. The transport is abstracted the way SMTP's is, so
/// the protocol layer stays testable and web builds get a stub.
abstract class DVRedisConnection {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

typedef DVRedisConnect = Future<DVRedisConnection> Function(
  String host,
  int port,
);

/// Thrown when Redis answers with an error reply.
class DVRedisException implements Exception {
  final String message;

  const DVRedisException(this.message);

  @override
  String toString() => 'DVRedisException: $message';
}

/// A minimal RESP2 client: commands out as arrays of bulk strings, replies
/// parsed into Dart values. Covers what the cache adapter needs; not a
/// general Redis library.
class DVRedisClient {
  final DVRedisConnection _connection;
  final List<Completer<Object?>> _pending = [];
  final List<int> _buffer = [];

  DVRedisClient._(this._connection) {
    _connection.input.listen(
      (List<int> chunk) {
        _buffer.addAll(chunk);
        _drain();
      },
      onError: (Object error) => _failAll('connection error: $error'),
      onDone: () => _failAll('connection closed'),
    );
  }

  /// Connects and authenticates when a password is supplied.
  static Future<DVRedisClient> connect({
    String host = '127.0.0.1',
    int port = 6379,
    String? password,
    DVRedisConnect? connector,
  }) async {
    final connection = await (connector ?? dvConnectRedis)(host, port);
    final client = DVRedisClient._(connection);
    if (password != null) {
      await client.command(<String>['AUTH', password]);
    }
    return client;
  }

  void _failAll(String reason) {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(DVRedisException(reason));
      }
    }
    _pending.clear();
  }

  /// Sends one command and returns its reply.
  Future<Object?> command(List<String> parts) {
    // Encoded as bytes throughout: a value's UTF-8 length and its string
    // length differ, and RESP counts bytes.
    final bytes = <int>[];
    bytes.addAll(utf8.encode('*${parts.length}\r\n'));
    for (final part in parts) {
      final encoded = utf8.encode(part);
      bytes.addAll(utf8.encode('\$${encoded.length}\r\n'));
      bytes.addAll(encoded);
      bytes.addAll(const <int>[13, 10]);
    }
    final completer = Completer<Object?>();
    _pending.add(completer);
    _connection.write(bytes);
    return completer.future;
  }

  void _drain() {
    while (_pending.isNotEmpty) {
      final parsed = _tryParse(0);
      if (parsed == null) return;
      _buffer.removeRange(0, parsed.consumed);
      final completer = _pending.removeAt(0);
      final value = parsed.value;
      if (value is DVRedisException) {
        completer.completeError(value);
      } else {
        completer.complete(value);
      }
    }
  }

  /// Parses one reply starting at [start], or null when incomplete.
  ({Object? value, int consumed})? _tryParse(int start) {
    if (start >= _buffer.length) return null;
    final lineEnd = _findCrlf(start + 1);
    if (lineEnd == null) return null;
    final line = utf8.decode(_buffer.sublist(start + 1, lineEnd));
    final afterLine = lineEnd + 2;

    switch (_buffer[start]) {
      case 0x2B: // + simple string
        return (value: line, consumed: afterLine - start);
      case 0x2D: // - error
        return (value: DVRedisException(line), consumed: afterLine - start);
      case 0x3A: // : integer
        return (value: int.parse(line), consumed: afterLine - start);
      case 0x24: // $ bulk string
        final length = int.parse(line);
        if (length == -1) return (value: null, consumed: afterLine - start);
        if (_buffer.length < afterLine + length + 2) return null;
        final value =
            utf8.decode(_buffer.sublist(afterLine, afterLine + length));
        return (value: value, consumed: afterLine + length + 2 - start);
      case 0x2A: // * array
        final count = int.parse(line);
        if (count == -1) return (value: null, consumed: afterLine - start);
        final items = <Object?>[];
        var cursor = afterLine;
        for (var i = 0; i < count; i++) {
          final item = _tryParse(cursor);
          if (item == null) return null;
          items.add(item.value);
          cursor += item.consumed;
        }
        return (value: items, consumed: cursor - start);
      default:
        throw DVRedisException(
          'Unsupported RESP type byte ${_buffer[start]}.',
        );
    }
  }

  int? _findCrlf(int from) {
    for (var i = from; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 13 && _buffer[i + 1] == 10) return i;
    }
    return null;
  }

  Future<void> close() => _connection.close();
}

/// `DV.Cache` on Redis (or Valkey).
///
/// Values are JSON-wrapped the way [DVDatabaseCacheAdapter] wraps them, so
/// the two adapters are interchangeable. Redis expires keys natively:
/// [purgeExpired] therefore has nothing to reclaim and reports zero.
class DVRedisCacheAdapter implements DVCacheAdapter, DVAtomicCacheAdapter {
  final DVRedisClient client;

  /// Prefix isolating this application's keys in a shared Redis.
  final String keyPrefix;

  DVRedisCacheAdapter(this.client, {this.keyPrefix = 'dartvel:'});

  String _k(String key) => '$keyPrefix$key';

  @override
  Future<Object?> read(String key) async {
    final raw = await client.command(<String>['GET', _k(key)]);
    if (raw is! String) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded['v'] : null;
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    await client.command(<String>[
      'SET',
      _k(key),
      jsonEncode(<String, Object?>{'v': value}),
      if (ttl != null) ...<String>['PX', '${ttl.inMilliseconds}'],
    ]);
  }

  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async {
    // SET NX is Redis's compare-and-set for absence — the atomic primitive
    // the spec requires from a distributed provider before locks count.
    final reply = await client.command(<String>[
      'SET',
      _k(key),
      jsonEncode(<String, Object?>{'v': value}),
      'NX',
      if (ttl != null) ...<String>['PX', '${ttl.inMilliseconds}'],
    ]);
    return reply == 'OK';
  }

  @override
  Future<void> remove(String key) async {
    await client.command(<String>['DEL', _k(key)]);
  }

  @override
  Future<void> clear() async {
    // Only this application's keys — FLUSHDB would take the whole database,
    // including whatever else shares the server.
    var cursor = '0';
    do {
      final reply = await client.command(
        <String>['SCAN', cursor, 'MATCH', '$keyPrefix*', 'COUNT', '500'],
      ) as List<Object?>;
      cursor = reply[0]! as String;
      final keys = (reply[1]! as List<Object?>).cast<String>();
      if (keys.isNotEmpty) {
        await client.command(<String>['DEL', ...keys]);
      }
    } while (cursor != '0');
  }

  @override
  Future<int> purgeExpired() async => 0;
}
