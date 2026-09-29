// A request body reaches the handler while it is still arriving.
//
// The native side read every request body into memory before Dart saw any of
// it, so a handler could not look at the first byte of an upload until the
// client had sent the last one, and one client could name a body as large as
// it liked and have it held. These speak raw TCP to the real server, because
// what is being checked is when each side gets to run: a 50 MiB body has to be
// readable before the client has finished sending it, a handler that stops
// reading has to stop the client, a body that passes the limit mid-stream has
// to be refused without the handler seeing the bytes past it, and a handler
// that never looks at the body must not cost the connection.
//
// These speak raw TCP rather than through an HttpClient for the same reason
// request_body_limit_test.dart does: a client that never finishes sending, and
// a client whose write is throttled, are not something a well-behaved HTTP
// client does for you.
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvTooLargeMessage;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// What the server accepts by default, and what a route without a limit of
/// its own gets.
const int defaultLimit = 1024 * 1024;

/// Large enough for the uploads below, small enough that a body buffered
/// whole is visible: the point of the 50 MiB upload is that it is not held.
const int uploadLimit = 96 * 1024 * 1024;

/// A limit a body passes partway through, so the refusal happens after the
/// handler has already been handed the request.
const int midStreamLimit = 256 * 1024;

/// How long a locally-run answer may take. Far short of the request timeout,
/// so an answer that only came at the timeout fails rather than passes.
const Duration bound = Duration(seconds: 10);

/// A chunked body of [total] bytes, [each] at a time.
List<int> _chunk(int size) {
  final List<int> data =
      List<int>.generate(size, (int i) => (i % 251) + 1);
  return <int>[
    ...ascii.encode('${size.toRadixString(16)}\r\n'),
    ...data,
    ...ascii.encode('\r\n'),
  ];
}

/// Reads a socket into memory, so a test can wait for bytes and count them
/// rather than guess when they arrived.
final class _Wire {
  _Wire(this.socket) {
    _subscription = socket.listen(
      (List<int> data) {
        _buffer.addAll(data);
        if (!_arrived.isCompleted) _arrived.complete();
      },
      onError: (Object _) {
        _closed = true;
        if (!_arrived.isCompleted) _arrived.complete();
      },
      onDone: () {
        _closed = true;
        if (!_arrived.isCompleted) _arrived.complete();
      },
    );
  }

  final Socket socket;
  final List<int> _buffer = <int>[];
  late final StreamSubscription<List<int>> _subscription;
  Completer<void> _arrived = Completer<void>();
  bool _closed = false;

  bool get closed => _closed;
  int get length => _buffer.length;

  /// Completes on the next arrival. The completer is left pending after being
  /// completed -- replacing it with a completed one turns every wait into a
  /// microtask, and a loop of those starves the event loop the socket needs.
  Future<void> _nextArrival() {
    if (_arrived.isCompleted) _arrived = Completer<void>();
    return _arrived.future;
  }

  /// Waits until at least [bytes] are buffered, or the peer closes.
  Future<void> need(int bytes, {Duration? within}) async {
    final Stopwatch clock = Stopwatch()..start();
    while (_buffer.length < bytes && !_closed) {
      final Duration left = (within ?? bound) - clock.elapsed;
      if (left <= Duration.zero) return;
      await _nextArrival().timeout(left, onTimeout: () {});
    }
  }

  /// The first [count] buffered bytes, removed from the buffer.
  List<int> take(int count) {
    final int n = count < _buffer.length ? count : _buffer.length;
    final List<int> out = _buffer.sublist(0, n);
    _buffer.removeRange(0, n);
    return out;
  }

  /// Up to and including the next CRLF, as bytes, without it.
  Future<List<int>> line() async {
    while (true) {
      for (int i = 0; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == 13 && _buffer[i + 1] == 10) {
          final List<int> out = _buffer.sublist(0, i);
          _buffer.removeRange(0, i + 2);
          return out;
        }
      }
      if (_closed) throw StateError('the connection closed inside a line');
      await need(_buffer.length + 1);
      if (_closed && _buffer.isEmpty) {
        throw StateError('the connection closed inside a line');
      }
    }
  }

  Future<void> cancel() => _subscription.cancel();
}

/// One response read off [wire], framed by whichever of Content-Length and
/// chunked coding the head names.
final class _Reply {
  _Reply(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
  String get text => latin1.decode(body);
}

Future<_Reply> _readReply(_Wire wire) async {
  final List<int> head = await wire.line();
  final List<String> parts = latin1.decode(head).split(' ');
  final int status = int.parse(parts[1]);
  final Map<String, String> headers = <String, String>{};
  while (true) {
    final List<int> line = await wire.line();
    if (line.isEmpty) break;
    final String text = latin1.decode(line);
    final int colon = text.indexOf(':');
    headers[text.substring(0, colon).trim().toLowerCase()] =
        text.substring(colon + 1).trim();
  }
  final List<int> body = <int>[];
  if (headers['transfer-encoding'] == 'chunked') {
    while (true) {
      final int size =
          int.parse(latin1.decode(await wire.line()).split(';').first, radix: 16);
      if (size == 0) {
        await wire.line();
        break;
      }
      await wire.need(body.length + size + 2);
      body.addAll(wire.take(size));
      wire.take(2);
    }
  } else if (headers.containsKey('content-length')) {
    final int size = int.parse(headers['content-length']!);
    await wire.need(size);
    body.addAll(wire.take(size));
  }
  return _Reply(status, headers, body);
}

List<int> _head(String target,
        {String method = 'POST',
        int? contentLength,
        bool chunked = false,
        bool close = false}) =>
    ascii.encode('$method $target HTTP/1.1\r\nHost: localhost\r\n'
        'X-Token: no-0a1b\r\n'
        '${contentLength == null ? '' : 'Content-Length: $contentLength\r\n'}'
        '${chunked ? 'Transfer-Encoding: chunked\r\n' : ''}'
        '${close ? 'Connection: close\r\n' : ''}\r\n');

void main() {
  // One record per request, filled from both sides: the handler runs in this
  // isolate too, so a stopwatch started before the first write orders what the
  // client and the handler each did without either guessing.
  final Stopwatch clock = Stopwatch();

  final Map<String, int> firstChunkAtMs = <String, int>{};
  final Map<String, int> lastChunkAtMs = <String, int>{};
  final Map<String, int> sentWhenFirstChunkSeen = <String, int>{};
  final Map<String, int> sentAtFirstChunk = <String, int>{};
  final Map<String, int> seenBytes = <String, int>{};
  final Map<String, int> seenChunks = <String, int>{};
  final Map<String, Object?> seenError = <String, Object?>{};
  int sentSoFar = 0;

  /// Records a chunk the handler was given. [size] is the length; every chunk
  /// is recorded as it arrives, so a body refused partway through leaves the
  /// bytes that did arrive and nothing of the rest.
  void saw(String route, int size) {
    firstChunkAtMs.putIfAbsent(route, () => clock.elapsedMilliseconds);
    seenBytes[route] = (seenBytes[route] ?? 0) + size;
    seenChunks[route] = (seenChunks[route] ?? 0) + 1;
  }

  late ServerHandle server;

  setUp(() async {
    for (final Map<String, Object?> map in <Map<String, Object?>>[
      firstChunkAtMs,
      lastChunkAtMs,
      sentWhenFirstChunkSeen,
      sentAtFirstChunk,
      seenBytes,
      seenChunks,
      seenError,
    ]) {
      map.clear();
    }
    sentSoFar = 0;
    clock
      ..reset()
      ..start();

    final router = Router()
      // Reads its body in pieces and says when each arrived.
      ..post('/upload', (Request req) async {
        await for (final List<int> chunk in req.body.stream) {
          saw('/upload', chunk.length);
          if (sentWhenFirstChunkSeen['/upload'] == null &&
              firstChunkAtMs['/upload'] != null) {
            sentWhenFirstChunkSeen['/upload'] = sentSoFar;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        lastChunkAtMs['/upload'] = clock.elapsedMilliseconds;
        return Response.text('${seenBytes['/upload']}');
      }, maxBodyBytes: uploadLimit)
      // Stops reading for a while in the middle, which is what a handler
      // doing real work between chunks looks like to the client.
      ..post('/slow', (Request req) async {
        bool first = true;
        await for (final List<int> chunk in req.body.stream) {
          saw('/slow', chunk.length);
          if (first) {
            first = false;
            await Future<void>.delayed(const Duration(milliseconds: 1500));
          }
        }
        lastChunkAtMs['/slow'] = clock.elapsedMilliseconds;
        return Response.text('${seenBytes['/slow']}');
      }, maxBodyBytes: uploadLimit)
      ..post('/limited', (Request req) async {
        try {
          await for (final List<int> chunk in req.body.stream) {
            saw('/limited', chunk.length);
          }
        } catch (error) {
          seenError['/limited'] = error.runtimeType;
        }
        return Response.text('${seenBytes['/limited']}');
      }, maxBodyBytes: midStreamLimit)
      // Never looks at the body at all, which every GET route and a POST to a
      // route that reads the query instead does.
      ..post('/ignored', (Request req) async => Response.text('ignored'))
      ..get('/ok', (Request req) async => Response.text('ok'));

    server = await serve(router.call,
        host: '127.0.0.1',
        port: 0,
        requestTimeout: const Duration(seconds: 30),
        maxBodyBytes: defaultLimit,
        routeBodyLimits: router.bodyLimits);
  });

  tearDown(() => server.stop());

  group('a body that is still arriving', () {
    test('a 50 MiB upload reaches the handler before the client has sent it',
        () async {
      const int total = 50 * 1024 * 1024;
      const int each = 1024 * 1024;
      final _Wire wire = _Wire(await Socket.connect('127.0.0.1', server.port));
      addTearDown(wire.cancel);

      wire.socket.add(_head('/upload', contentLength: total));
      await wire.socket.flush();

      // Written in 1 MiB writes with a pause between them, so "the client has
      // finished" is a moment well after the first of them.
      final Stopwatch writing = Stopwatch()..start();
      for (int sent = 0; sent < total; sent += each) {
        final List<int> block =
            List<int>.generate(each, (int i) => (i % 251) + 1);
        sentSoFar = sent;
        wire.socket.add(block);
        await wire.socket.flush();
        if (firstChunkAtMs['/upload'] != null &&
            sentAtFirstChunk['/upload'] == null) {
          sentAtFirstChunk['/upload'] = sent;
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final int writeDoneMs = writing.elapsedMilliseconds;
      sentSoFar = total;

      final _Reply reply = await _readReply(wire);
      expect(reply.status, 200, reason: 'a 50 MiB body on a route that allows '
          'it is answered: ${reply.text}');
      expect(int.parse(reply.text), total,
          reason: 'the handler was given all of it');

      // The first chunk arrived while the client was still writing. A server
      // that reads the body whole first cannot do this: its handler is not
      // called until the last byte is in.
      expect(firstChunkAtMs['/upload'], isNotNull,
          reason: 'the handler was given the body in pieces');
      expect(sentWhenFirstChunkSeen['/upload'] ?? sentAtFirstChunk['/upload'],
          lessThan(8 * 1024 * 1024),
          reason: 'the handler saw a chunk after the client had sent ${sentAtFirstChunk['/upload']} '
              'of $total bytes; a body held whole cannot be read before it is '
              'all here');
      expect(seenChunks['/upload'], greaterThan(1),
          reason: 'the body arrived as more than one piece');
      expect(writeDoneMs, greaterThan(firstChunkAtMs['/upload']!),
          reason: 'the client finished writing at ${writeDoneMs}ms and the '
              'first chunk was already in the handler at '
              '${firstChunkAtMs['/upload']}ms');
    });

    test('a handler that stops reading stops the client', () async {
      // /slow reads one chunk and then waits 1.5s without pulling. A server
      // that had already read the body would have taken all 32 MiB by then,
      // and the client would be done long before the handler finished.
      const int total = 32 * 1024 * 1024;
      const int each = 64 * 1024;
      final _Wire wire = _Wire(await Socket.connect('127.0.0.1', server.port));
      addTearDown(wire.cancel);

      wire.socket.add(_head('/slow', chunked: true));
      await wire.socket.flush();
      for (int sent = 0; sent < total; sent += each) {
        sentSoFar = sent;
        wire.socket.add(_chunk(each));
        await wire.socket.flush();
      }
      // A chunked body ends with the empty chunk. Without it a decoder can
      // never call the body ended, so the handler would wait for a chunk
      // past the last of them and the request would time out instead of
      // being answered -- which is 408 rather than the 200 this is about.
      wire.socket.add(ascii.encode('0\r\n\r\n'));
      await wire.socket.flush();
      final int writeDoneMs = clock.elapsedMilliseconds;
      // Now that the client is done, the handler is certainly running. A
      // server that reads the body whole before calling it would have had
      // the whole $total bytes in hand at writeDoneMs and been under no
      // pressure at all.
      final Stopwatch waited = Stopwatch()..start();
      while (firstChunkAtMs['/slow'] == null &&
          waited.elapsed < bound) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(firstChunkAtMs['/slow'], isNotNull,
          reason: 'the handler was given the body in pieces');
      final int stalledMs = writeDoneMs - firstChunkAtMs['/slow']!;
      expect(stalledMs, greaterThan(1000),
          reason: 'the client finished sending all $total bytes ${stalledMs}ms '
              'after the handler got its first chunk, and the handler was not '
              'reading for 1500ms of that -- so the client was never '
              'throttled and the body was not being read as it arrived');

      final _Reply reply = await _readReply(wire);
      expect(reply.status, 200, reason: reply.text);
      expect(int.parse(reply.text), total);
    });
  });

  group('a body that passes the limit', () {
    test('is refused mid-stream, and the handler is given nothing past it',
        () async {
      const int each = 16 * 1024;
      const int sent = 4 * 1024 * 1024;
      final _Wire wire = _Wire(await Socket.connect('127.0.0.1', server.port));
      addTearDown(wire.cancel);

      wire.socket.add(_head('/limited', chunked: true));
      await wire.socket.flush();
      // Paced, and reading whatever arrives rather than stopping at the first
      // byte: the refusal closes the connection, and a reset while this is
      // still writing can discard part of the answer. That the connection is
      // closed and the handler is given nothing past the limit is the
      // guarantee; the 413 itself has to survive the same way it does in
      // request_body_limit_test.dart.
      try {
        for (int written = 0; written < sent; written += each) {
          wire.socket.add(_chunk(each));
          await wire.socket.flush();
          if (wire.length > 0) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      } on SocketException {
        // Closed while still writing, which is the refusal arriving.
      }
      await wire.need(1);
      while (!wire.closed && wire.length > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await wire.need(wire.length + 1, within: const Duration(milliseconds: 50));
      }
      final String text = latin1.decode(wire.take(wire.length));
      final RegExpMatch? status =
          RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(text);

      expect(status?.group(1), '413',
          reason: 'a body past its route limit is refused as it passes it: '
              '$text');
      expect(text, contains(dvTooLargeMessage(midStreamLimit)),
          reason: 'the answer names the limit that refused it');
      expect(text, isNot(contains('no-0a1b')),
          reason: 'an error answer repeats nothing the request carried');
      expect(wire.closed, isTrue,
          reason: 'the rest of a refused body is not read');

      // Nothing past the limit was ever handed over. The refusal happens
      // before the chunk that would pass it, so a handler cannot have seen
      // one byte of it.
      final int seen = seenBytes['/limited'] ?? 0;
      expect(seen, lessThanOrEqualTo(midStreamLimit),
          reason: 'the handler was given $seen bytes of a body limited to '
              '$midStreamLimit');
      expect(seenChunks['/limited'], isNotNull,
          reason: 'the handler was called for a body it was refused');
      expect(seenError['/limited'], isNotNull,
          reason: 'the body stream ended in a failure the handler could see, '
              'not a silent end');
    });
  });

  group('a handler that never reads the body', () {
    test('is answered, and the connection is left usable', () async {
      // The same connection carries a second request. If the body had been
      // left half-read, or the request's slot kept, this is where it shows.
      const int total = 1024 * 1024;
      final _Wire wire = _Wire(await Socket.connect('127.0.0.1', server.port));
      addTearDown(wire.cancel);

      wire.socket.add(_head('/ignored', contentLength: total));
      await wire.socket.flush();
      final List<int> body =
          List<int>.generate(total, (int i) => (i % 251) + 1);
      wire.socket.add(body);
      await wire.socket.flush();

      final Stopwatch clock2 = Stopwatch()..start();
      final _Reply first = await _readReply(wire);
      expect(first.status, 200, reason: first.text);
      expect(first.text, 'ignored');
      expect(clock2.elapsed, lessThan(bound),
          reason: 'a body the handler ignores is not a reason to hold the '
              'answer');

      wire.socket.add(_head('/ok', method: 'GET'));
      await wire.socket.flush();
      final _Reply second = await _readReply(wire);
      expect(second.status, 200,
          reason: 'the connection the unread body arrived on is still '
              'usable: ${second.text}');
      expect(second.text, 'ok');
      expect(seenBytes.containsKey('/ignored'), isFalse,
          reason: 'nothing read a body no handler asked for');
    });
  });
}
