// No request body is read past a limit.
//
// The native side read every request body into memory before Dart saw any of
// it, with no cap, so one client could send a body as large as it liked -- or
// a chunked body that never ended -- and the server buffered all of it. The
// route checks in Dart (bodyLimit, uploadLimit, the crash endpoint's
// maxBytes) all ran after that read, which is too late to be a limit.
//
// These speak raw TCP to the real server, because the failures are in what a
// client sends and when: a Content-Length over the limit, a chunked body that
// passes it, one that trickles in forever, and a Content-Length that
// understates what follows. Each asserts an answer within a bound far short
// of the request timeout -- so an answer that only came at the timeout fails
// -- that the answer repeats nothing the request carried, and that the route
// handler never saw more than its limit.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show dvDefaultMaxBodyBytes, dvTooLargeMessage;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// A marker no answer may contain: it is only ever in a request.
const String marker = 'SECRET-b0d7';

/// Well past anything a local answer takes, and far short of [timeout].
const Duration bound = Duration(seconds: 5);

/// The request timeout. Long, so a body held until the timeout fails the
/// bound instead of passing as an answer.
const Duration timeout = Duration(seconds: 30);

/// The server's limit in these tests, and the upload routes' own.
const int limit = 64 * 1024;
const int uploadLimit = 256 * 1024;

final class Exchange {
  Exchange(this.bytes, this.closed, this.elapsed, this.sent);

  final List<int> bytes;
  final bool closed;
  final Duration elapsed;

  /// Body bytes the client wrote before it stopped.
  final int sent;

  String get text => latin1.decode(bytes);

  int? get status {
    final RegExpMatch? match =
        RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  @override
  String toString() =>
      'after ${elapsed.inMilliseconds}ms, sent $sent body bytes, closed: '
      '$closed, received: '
      '${text.length > 300 ? '${text.substring(0, 300)}...' : text}';
}

/// Writes [head], then each of [chunks] with [every] between them until the
/// server answers or closes, then reads until it closes or [within] passes.
Future<Exchange> exchange(
  int port,
  List<int> head, {
  Iterable<List<int>> chunks = const <List<int>>[],
  Duration every = Duration.zero,
  Duration within = bound,
}) async {
  final Stopwatch clock = Stopwatch()..start();
  final Socket socket = await Socket.connect('127.0.0.1', port);
  unawaited(socket.done.then((_) {}, onError: (Object _) {}));
  final List<int> received = <int>[];
  final Completer<bool> closed = Completer<bool>();
  socket.listen(
    received.addAll,
    onDone: () {
      if (!closed.isCompleted) closed.complete(true);
    },
    onError: (Object _) {
      if (!closed.isCompleted) closed.complete(true);
    },
  );
  int sent = 0;
  try {
    socket.add(head);
    await socket.flush();
    for (final List<int> chunk in chunks) {
      if (received.isNotEmpty || closed.isCompleted) break;
      if (clock.elapsed >= within) break;
      socket.add(chunk);
      await socket.flush();
      sent += chunk.length;
      if (every > Duration.zero) await Future<void>.delayed(every);
    }
  } on SocketException {
    // The server closed while this was still writing, which is an answer.
  }
  final Duration left = within - clock.elapsed;
  final bool wasClosed = await closed.future.timeout(
      left.isNegative ? Duration.zero : left,
      onTimeout: () => false);
  clock.stop();
  socket.destroy();
  return Exchange(received, wasClosed, clock.elapsed, sent);
}

/// A request head. [close] asks the server to close after answering; a
/// refused request leaves it out, so a connection the server kept open
/// after refusing shows up as one that never closed.
List<int> head(String target,
        {int? contentLength,
        bool chunked = false,
        String method = 'POST',
        bool close = true}) =>
    ascii.encode('$method $target HTTP/1.1\r\nHost: localhost\r\n'
        'X-Token: $marker\r\n'
        '${contentLength == null ? '' : 'Content-Length: $contentLength\r\n'}'
        '${chunked ? 'Transfer-Encoding: chunked\r\n' : ''}'
        '${close ? 'Connection: close\r\n' : ''}\r\n');

/// The head of a request that is going to be refused.
List<int> refusedHead(String target, {int? contentLength, bool chunked = false}) =>
    head(target, contentLength: contentLength, chunked: chunked, close: false);

/// One chunk of chunked transfer coding, [size] bytes of the marker repeated.
List<int> chunk(int size) {
  final List<int> data = List<int>.generate(
      size, (int i) => marker.codeUnitAt(i % marker.length));
  return <int>[
    ...ascii.encode('${size.toRadixString(16)}\r\n'),
    ...data,
    ...ascii.encode('\r\n'),
  ];
}

List<int> bodyOf(int size) => List<int>.generate(
    size, (int i) => marker.codeUnitAt(i % marker.length));

/// An endless chunked body.
Iterable<List<int>> endless(int size) sync* {
  while (true) {
    yield chunk(size);
  }
}

void main() {
  // The length of every body a route handler was given.
  final List<int> seen = <int>[];

  Future<Response> echo(Request req) async {
    final int length = await req.body.stream
        .fold<int>(0, (int n, List<int> c) => n + c.length);
    seen.add(length);
    return Response.text('$length');
  }

  late ServerHandle server;

  setUp(() async {
    seen.clear();
    final Router router = Router()
      ..post('/note', echo)
      ..post('/upload', echo, maxBodyBytes: uploadLimit)
      ..post('/files/:id', echo, maxBodyBytes: uploadLimit)
      ..any('/shadow/:name', echo)
      ..post('/shadow/upload', echo, maxBodyBytes: uploadLimit);
    server = await serve(router.call,
        host: '127.0.0.1',
        port: 0,
        requestTimeout: timeout,
        maxBodyBytes: limit,
        routeBodyLimits: router.bodyLimits);
  });

  tearDown(() => server.stop());

  void refused(Exchange result, int by) {
    expect(result.status, 413, reason: '$result');
    expect(result.elapsed, lessThan(bound), reason: '$result');
    expect(result.closed, isTrue,
        reason: 'the rest of a refused body is not read: $result');
    expect(result.text, contains(dvTooLargeMessage(by)), reason: '$result');
    expect(result.text, isNot(contains(marker)),
        reason: 'an error answer repeats nothing the request carried');
  }

  Future<void> stillServes() async {
    final Exchange next = await exchange(
        server.port, <int>[...head('/note', contentLength: 2), ...'ok'.codeUnits]);
    expect(next.status, 200, reason: 'the server answers the next request: $next');
  }

  group('a body over the server limit', () {
    test('a declared Content-Length over the limit is answered 413 without '
        'reading the body', () async {
      // Nothing of the body is sent at all: an answer can only come from the
      // header. Waiting for the body, the server answered 408 at the timeout.
      final Exchange result = await exchange(
          server.port, refusedHead('/note?q=$marker', contentLength: limit + 1));
      refused(result, limit);
      expect(seen, isEmpty);
      await stillServes();
    });

    test('a chunked body is cut off with 413 as soon as it passes the limit',
        () async {
      // Past the limit and then silent, with the body unfinished: an answer
      // that waited for the end would come at the timeout.
      final Exchange result = await exchange(
          server.port, refusedHead('/note', chunked: true),
          chunks: List<List<int>>.generate(3, (_) => chunk(32 * 1024)),
          every: const Duration(milliseconds: 10));
      refused(result, limit);
      expect(seen, isEmpty);
      await stillServes();
    });

    test('a slow endless chunked body is refused at the limit, not held until '
        'the request timeout', () async {
      final Exchange result = await exchange(
          server.port, refusedHead('/note', chunked: true),
          chunks: endless(8 * 1024), every: const Duration(milliseconds: 20));
      refused(result, limit);
      expect(seen, isEmpty, reason: 'no handler was given any of it');
      await stillServes();
    });

    test('a Content-Length that understates the body passes no more than it '
        'declared', () async {
      // What follows the declared 16 bytes is not this request's body. Read
      // as one, it would be buffered past every limit.
      //
      // The 200 may not reach the client: the request asks the server to
      // close after answering, and it closes with the rest unread, which
      // resets the connection and can discard the answer before it is read
      // (2 runs in 5 did). What must hold is what the handler was given.
      // Asked to stay open instead, the server would read the rest as the
      // start of a request line with no end, bounded by the header timeout.
      final Exchange result = await exchange(server.port, <int>[
        ...head('/note', contentLength: 16),
        ...bodyOf(16),
        ...bodyOf(4 * limit),
      ]);
      expect(result.status, anyOf(isNull, 200), reason: '$result');
      expect(result.closed, isTrue, reason: '$result');
      expect(result.text, isNot(contains(marker)));
      final Stopwatch waited = Stopwatch()..start();
      while (seen.isEmpty && waited.elapsed < bound) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(seen, <int>[16],
          reason: 'the handler was given the declared body and nothing else');
      await stillServes();
      expect(seen.every((int n) => n <= 16 || n == 2), isTrue, reason: '$seen');
    });

    test('a body exactly at the limit is read whole', () async {
      final Exchange declared = await exchange(server.port,
          <int>[...head('/note', contentLength: limit), ...bodyOf(limit)]);
      expect(declared.status, 200, reason: '$declared');
      expect(declared.text, contains('\r\n$limit\r\n'));

      final Exchange chunked = await exchange(server.port, <int>[
        ...head('/note', chunked: true),
        ...chunk(limit ~/ 2),
        ...chunk(limit ~/ 2),
        ...ascii.encode('0\r\n\r\n'),
      ]);
      expect(chunked.status, 200, reason: '$chunked');
      expect(seen, <int>[limit, limit]);
    });

    test('a route nothing registered keeps the server limit', () async {
      // Answered 404 only after the whole body had been read.
      refused(
          await exchange(
              server.port, refusedHead('/nowhere', contentLength: 4 * limit)),
          limit);
    });
  });

  group("a route's own limit", () {
    test('an upload route reads past the server limit, up to its own',
        () async {
      for (final String target in <String>['/upload', '/files/42']) {
        final Exchange result = await exchange(server.port, <int>[
          ...head(target, contentLength: 3 * limit),
          ...bodyOf(3 * limit),
        ]);
        expect(result.status, 200,
            reason: 'an upload route is not capped at the server limit: '
                '$target $result');
      }
      expect(seen, <int>[3 * limit, 3 * limit]);
    });

    test('past its own limit it is refused, naming its own number', () async {
      refused(
          await exchange(
              server.port, refusedHead('/upload', contentLength: uploadLimit + 1)),
          uploadLimit);
      refused(
          await exchange(server.port, refusedHead('/files/42', chunked: true),
              chunks: endless(32 * 1024),
              every: const Duration(milliseconds: 5)),
          uploadLimit);
      expect(seen, isEmpty);
    });

    test('a route with no limit of its own keeps the server limit, even with '
        'a larger route after it', () async {
      refused(
          await exchange(
              server.port, refusedHead('/note', contentLength: 2 * limit)),
          limit);
      // /shadow/:name comes first and takes the request, so /shadow/upload's
      // number is not this request's.
      refused(
          await exchange(server.port,
              refusedHead('/shadow/upload', contentLength: 2 * limit)),
          limit);
    });

    test("a dot segment does not reach a larger route's limit", () async {
      // Dart resolves /files/.. to another path, so the request is not
      // /files/:id's and must not be given its number.
      for (final String target in <String>['/files/..', '/files/%2e%2E']) {
        refused(
            await exchange(
                server.port, refusedHead(target, contentLength: 2 * limit)),
            limit);
      }
    });
  });

  group('configuration', () {
    test('a server that configures nothing is still bounded', () async {
      final ServerHandle bare = await serve(echo, host: '127.0.0.1', port: 0);
      try {
        refused(
            await exchange(bare.port,
                refusedHead('/any', contentLength: dvDefaultMaxBodyBytes + 1)),
            dvDefaultMaxBodyBytes);
      } finally {
        await bare.stop();
      }
    });

    test('a server limit that is not positive is refused', () async {
      for (final int bytes in <int>[0, -1]) {
        await expectLater(
            serve(echo, host: '127.0.0.1', port: 0, maxBodyBytes: bytes),
            throwsArgumentError);
      }
    });

  });
}
