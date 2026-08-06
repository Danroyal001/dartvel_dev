/// Memcached support: the text protocol plus the cache adapter on it.
library dartvel_core.cache.memcached;

import 'dart:async';
import 'dart:convert';

import 'adapters.dart';
import 'memcached_socket_unsupported.dart'
    if (dart.library.io) 'memcached_socket_io.dart';

/// One Memcached connection.
abstract class DVMemcachedConnection {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

typedef DVMemcachedConnect = Future<DVMemcachedConnection> Function(
  String host,
  int port,
);

/// Thrown when Memcached reports a protocol error.
class DVMemcachedException implements Exception {
  final String message;

  const DVMemcachedException(this.message);

  @override
  String toString() => 'DVMemcachedException: $message';
}

/// `DV.Cache` on Memcached.
///
/// Values are JSON-wrapped exactly as the database and Redis adapters wrap
/// them, so the three are interchangeable. Memcached expires keys itself, so
/// [purgeExpired] has nothing to reclaim and reports zero.
class DVMemcachedCacheAdapter implements DVCacheAdapter, DVAtomicCacheAdapter {
  final String host;
  final int port;

  /// Prefix isolating this application's keys on a shared server.
  final String keyPrefix;

  final DVMemcachedConnect? _connector;

  DVMemcachedConnection? _connection;
  final List<int> _buffer = [];
  final List<Completer<List<String>>> _pending = [];
  Future<void>? _connecting;

  DVMemcachedCacheAdapter({
    this.host = '127.0.0.1',
    this.port = 11211,
    this.keyPrefix = 'dartvel:',
    DVMemcachedConnect? connector,
  }) : _connector = connector;

  /// Memcached keys may not contain spaces or control characters and cap at
  /// 250 bytes, so a key that would be rejected is hashed rather than sent
  /// and silently failing.
  String _k(String key) {
    final full = '$keyPrefix$key';
    final safe = full.replaceAll(RegExp(r'[\x00-\x20\x7f]'), '_');
    if (safe.length <= 250) return safe;
    return '$keyPrefix${safe.hashCode.toRadixString(16)}'
        '${safe.substring(safe.length - 32)}';
  }

  Future<void> _ensureConnected() {
    if (_connection != null) return Future<void>.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final connection = await (_connector ?? dvConnectMemcached)(host, port);
    _connection = connection;
    connection.input.listen(
      (List<int> chunk) {
        _buffer.addAll(chunk);
        _drain();
      },
      onError: (Object error) => _failAll('connection error: $error'),
      onDone: () {
        _connection = null;
        _failAll('connection closed');
      },
    );
  }

  void _failAll(String reason) {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(DVMemcachedException(reason));
      }
    }
    _pending.clear();
  }

  /// Sends a command and collects lines until a terminator.
  Future<List<String>> _command(List<int> payload) async {
    await _ensureConnected();
    final completer = Completer<List<String>>();
    _pending.add(completer);
    _connection!.write(payload);
    return completer.future;
  }

  static const Set<String> _terminators = <String>{
    'STORED', 'NOT_STORED', 'EXISTS', 'NOT_FOUND', 'DELETED', 'END', 'OK',
    'TOUCHED', 'ERROR',
  };

  void _drain() {
    while (_pending.isNotEmpty) {
      final lines = _tryReadReply();
      if (lines == null) return;
      final completer = _pending.removeAt(0);
      if (lines.isNotEmpty &&
          (lines.last.startsWith('CLIENT_ERROR') ||
              lines.last.startsWith('SERVER_ERROR'))) {
        completer.completeError(DVMemcachedException(lines.last));
        continue;
      }
      completer.complete(lines);
    }
  }

  List<String>? _tryReadReply() {
    final text = utf8.decode(_buffer, allowMalformed: true);
    final lines = <String>[];
    var consumed = 0;
    var index = 0;
    while (true) {
      final end = text.indexOf('\r\n', index);
      if (end == -1) return null;
      final line = text.substring(index, end);
      lines.add(line);
      index = end + 2;
      final head = line.split(' ').first;
      if (_terminators.contains(head) ||
          line.startsWith('CLIENT_ERROR') ||
          line.startsWith('SERVER_ERROR')) {
        consumed = index;
        break;
      }
    }
    // Byte length, not string length: a multi-byte value would otherwise
    // leave a fragment in the buffer and desynchronise every later reply.
    _buffer.removeRange(0, utf8.encode(text.substring(0, consumed)).length);
    return lines;
  }

  @override
  Future<Object?> read(String key) async {
    final lines = await _command(utf8.encode('get ${_k(key)}\r\n'));
    // VALUE <key> <flags> <bytes> / <data> / END
    if (lines.length < 3 || !lines.first.startsWith('VALUE')) return null;
    final decoded = jsonDecode(lines[1]);
    return decoded is Map<String, Object?> ? decoded['v'] : null;
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    await _store('set', key, value, ttl);
  }

  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async {
    // `add` stores only when the key is absent — Memcached's own
    // compare-and-set for absence, which is what a lock needs.
    final lines = await _store('add', key, value, ttl);
    return lines.isNotEmpty && lines.first == 'STORED';
  }

  Future<List<String>> _store(
    String verb,
    String key,
    Object? value,
    Duration? ttl,
  ) {
    final payload = utf8.encode(jsonEncode(<String, Object?>{'v': value}));
    // Memcached treats an expiry above 30 days as an absolute unix time, so
    // a long TTL has to be sent that way or it expires immediately.
    final seconds = ttl == null ? 0 : ttl.inSeconds;
    final expiry = seconds > 2592000
        ? DateTime.now().add(ttl!).millisecondsSinceEpoch ~/ 1000
        : seconds;
    return _command(<int>[
      ...utf8.encode('$verb ${_k(key)} 0 $expiry ${payload.length}\r\n'),
      ...payload,
      ...utf8.encode('\r\n'),
    ]);
  }

  @override
  Future<void> remove(String key) async {
    await _command(utf8.encode('delete ${_k(key)}\r\n'));
  }

  @override
  Future<void> clear() async {
    // Memcached has no key enumeration, so a prefix-scoped clear is not
    // possible; flush_all takes the whole server. Saying so is better than
    // quietly clearing a neighbour's keys.
    await _command(utf8.encode('flush_all\r\n'));
  }

  @override
  Future<int> purgeExpired() async => 0;

  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }
}
