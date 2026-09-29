// A response body reaches the client as it is produced, whether or not the
// handler asked for that.
//
// Only a body the handler marked as a stream was sent as one. Everything else
// was read to the end in Dart and handed over in one piece, so the client saw
// nothing at all until the handler had finished producing: a report that
// builds its body as it goes, a generated file, a page assembled from a
// generator, anything whose first bytes were ready long before its last. A
// fixed body that is already whole still goes as one copy -- buffering it
// costs the same as producing it -- but nothing is buffered waiting to find
// out how big it is.
//
// Raw TCP rather than HttpClient, because what is checked is when each byte
// arrives relative to the handler producing it, and a client library hides
// exactly that.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// Past the point where a body is still worth holding to see whether it is
/// small. The implementation may pick a different number; what matters is
/// that a body this size is not held whole.
const int large = 512 * 1024;

/// Far more than producing this takes, and far short of a hang.
const Duration bound = Duration(seconds: 10);

/// When the handler produced each piece, in microseconds on one stopwatch
/// shared with the client. The handler runs in this isolate, so this orders
/// the two sides without either guessing.
final Stopwatch clock = Stopwatch();

void main() {
  late ServerHandle server;

  setUp(() {
    clock
      ..reset()
      ..start();
  });

  tearDown(() => server.stop);

  /// A body of [total] bytes, produced [piece] at a time, the first piece
  /// immediately and the rest as the client reads. Returns the response; the
  /// handler records the times into [producedAt].
  Response _producing(List<int> producedAt,
      {required int total, required int piece, Duration between = const Duration(milliseconds: 20)}) {
    final StreamController<List<int>> controller = StreamController<List<int>>();
    (() async {
      for (int sent = 0; sent < total; sent += piece) {
        if (controller.isClosed) return;
        producedAt.add(clock.elapsedMicroseconds);
        controller.add(
            List<int>.generate(piece, (int i) => (sent + i) % 251));
        if (sent + piece < total) await Future<void>.delayed(between);
      }
      await controller.close();
    })();
    // Not Response.stream: the whole point is a body a handler did not mark
    // as a stream, which is what every page, report and file in the framework
    // actually returns.
    return Response(200,
        headers: Headers()..set('content-type', 'application/octet-stream'),
        body: controller.stream);
  }

  Future<Socket> _connect() async {
    final socket = await Socket.connect('127.0.0.1', server.port);
    addTearDown(socket.destroy);
    return socket;
  }

  List<int> _head(String target) => ascii.encode(
      'GET $target HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');

  test('a body nobody marked as a stream reaches the client while it is '
      'still being produced', () async {
    final List<int> producedAt = <int>[];
    final Router router = Router()
      ..get('/report', (Request req) async =>
          _producing(producedAt, total: large, piece: 64 * 1024));
    server = await serve(router.call, host: '127.0.0.1', port: 0);
    addTearDown(() => server.stop());

    final Socket socket = await _connect();
    final List<int> received = <int>[];
    final Completer<void> closed = Completer<void>();
    socket.listen(received.addAll,
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        });

    socket.add(_head('/report'));
    await socket.flush();

    // Wait for the first body byte. A server that buffered the whole body
    // answers only after the handler has produced all of it, so this wait is
    // the assertion: it must return long before the last piece.
    final Stopwatch waited = Stopwatch()..start();
    while (_bodyBytes(received) == 0 && waited.elapsed < bound) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final int firstByteUs = clock.elapsedMicroseconds;
    expect(_bodyBytes(received), greaterThan(0),
        reason: 'the client was sent the first body byte while the handler '
            'was still producing');

    await closed.future.timeout(bound, onTimeout: () {});
    final int lastProducedUs = producedAt.last;

    expect(firstByteUs, lessThan(lastProducedUs),
        reason: 'the first body byte arrived at ${firstByteUs}us and the last '
            'piece was not produced until ${lastProducedUs}us. A body held '
            'whole cannot be sent before it is finished.');
    expect(_bodyBytes(received), greaterThanOrEqualTo(large),
        reason: 'the whole body arrived');
  });

  test('a body produced slowly in small pieces reaches the client as each '
      'piece is produced, not once 64 KiB has piled up', () async {
    final List<int> producedAt = <int>[];
    final Router router = Router()
      ..get('/ticker', (Request req) async => _producing(producedAt,
          total: 8 * 1024,
          piece: 1024,
          between: const Duration(milliseconds: 100)));
    server = await serve(router.call, host: '127.0.0.1', port: 0);
    addTearDown(() => server.stop());

    final Socket socket = await _connect();
    final List<int> received = <int>[];
    final Completer<void> closed = Completer<void>();
    socket.listen(received.addAll,
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        });

    socket.add(_head('/ticker'));
    await socket.flush();

    final Stopwatch waited = Stopwatch()..start();
    while (_bodyBytes(received) == 0 && waited.elapsed < bound) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final int firstByteUs = clock.elapsedMicroseconds;
    await closed.future.timeout(bound, onTimeout: () {});

    expect(firstByteUs, lessThan(producedAt[2]),
        reason: 'the first 1 KiB piece was produced at ${producedAt.first}us '
            'but reached the client only at ${firstByteUs}us, after the third '
            'piece (${producedAt[2]}us): a slow body was held back to see '
            'whether it was small.');
    expect(_bodyBytes(received), greaterThanOrEqualTo(8 * 1024));
  });

  test('a small fixed body is sent in one piece, whole, with its length',
      () async {
    // The counterpart: a body that is already whole must not become a stream
    // of many small pieces. Buffering it costs the same as producing it, and
    // a client gets a length instead of a framing it has to reassemble.
    final List<int> producedAt = <int>[];
    final Router router = Router()
      ..get('/small', (Request req) async =>
          _producing(producedAt, total: 4 * 1024, piece: 4 * 1024))
      ..get('/text', (Request req) async => Response.text('ok'));
    server = await serve(router.call,
        host: '127.0.0.1', port: 0, compression: false);
    addTearDown(() => server.stop());

    for (final String target in <String>['/small', '/text']) {
      final Socket socket = await _connect();
      final List<int> received = <int>[];
      final Completer<void> closed = Completer<void>();
      socket.listen(received.addAll,
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
          onError: (Object _) {
            if (!closed.isCompleted) closed.complete();
          });
      socket.add(_head(target));
      await socket.flush();
      await closed.future.timeout(bound, onTimeout: () {});

      final String text = latin1.decode(received);
      expect(text, startsWith('HTTP/1.1 200'), reason: '$target: $text');
      // A known length rather than chunked framing: there was nothing to
      // wait for.
      expect(RegExp(r'\r\ncontent-length: (\d+)\r\n').hasMatch(text), isTrue,
          reason: '$target was sent with a length: $text');
      expect(text, isNot(contains('transfer-encoding')),
          reason: '$target was not framed as a stream: $text');
    }
  });
}

/// The body bytes in [received], which is a whole HTTP response: the head
/// ends at the first blank line.
int _bodyBytes(List<int> received) {
  for (int i = 0; i + 3 < received.length; i++) {
    if (received[i] == 13 &&
        received[i + 1] == 10 &&
        received[i + 2] == 13 &&
        received[i + 3] == 10) {
      return received.length - (i + 4);
    }
  }
  return 0;
}
