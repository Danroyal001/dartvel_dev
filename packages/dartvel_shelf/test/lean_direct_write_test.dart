// Whole answers on the lean HTTP/1 path are written to the socket from the
// call that hands them over, not by waking the connection's task. These pin
// down what that must keep: answers in request order on a pipelined
// connection, every byte of an answer the socket cannot take in one write,
// and a handler's `Connection: close` ending the connection.
//
// Raw TCP, because pipelining and a client that stops reading are things a
// well-behaved HTTP client does not do on request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// Reads [socket] until [enough] says the bytes so far are complete, or the
/// server closes, or [within] passes.
Future<(List<int>, bool)> _read(
  Socket socket,
  bool Function(List<int>) enough, {
  Duration within = const Duration(seconds: 10),
}) async {
  final List<int> received = <int>[];
  final Completer<bool> done = Completer<bool>();
  socket.listen(
    (List<int> bytes) {
      received.addAll(bytes);
      if (!done.isCompleted && enough(received)) done.complete(false);
    },
    onDone: () {
      if (!done.isCompleted) done.complete(true);
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(true);
    },
  );
  final bool closed = await done.future.timeout(within, onTimeout: () => false);
  return (received, closed);
}

/// The responses at the start of [bytes], each as (status, headers, body);
/// stops at the first one not complete yet.
List<(int, Map<String, String>, List<int>)> _responses(List<int> bytes) {
  final List<(int, Map<String, String>, List<int>)> out =
      <(int, Map<String, String>, List<int>)>[];
  var at = 0;
  while (true) {
    var headEnd = -1;
    for (var i = at; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        headEnd = i;
        break;
      }
    }
    if (headEnd < 0) return out;
    final List<String> lines = latin1
        .decode(bytes.sublist(at, headEnd))
        .split('\r\n');
    final int status = int.parse(lines.first.split(' ')[1]);
    final Map<String, String> headers = <String, String>{
      for (final String line in lines.skip(1))
        line.substring(0, line.indexOf(':')).toLowerCase(): line
            .substring(line.indexOf(':') + 1)
            .trim(),
    };
    final int length = int.parse(headers['content-length'] ?? '0');
    final int bodyStart = headEnd + 4;
    if (bytes.length < bodyStart + length) return out;
    out.add((status, headers, bytes.sublist(bodyStart, bodyStart + length)));
    at = bodyStart + length;
  }
}

String _get(String path) => 'GET $path HTTP/1.1\r\nHost: localhost\r\n\r\n';

void main() {
  late ServerHandle server;

  setUp(() async {
    server = await serve(
      (Request req) async {
        final String path = req.url.path;
        if (path.startsWith('/wait/')) {
          await Future<void>.delayed(
            Duration(milliseconds: int.parse(path.substring(6))),
          );
          return Response.text(path);
        }
        if (path.startsWith('/big/')) {
          // Each byte says which answer it belongs to, so a byte lost, doubled
          // or out of place shows.
          final int index = int.parse(path.substring(5));
          return Response.bytes(
            200,
            Uint8List(60 * 1024)..fillRange(0, 60 * 1024, index % 251),
            headers: Headers()..set('content-type', 'application/octet-stream'),
          );
        }
        if (path == '/close') {
          return Response.text(
            'bye',
            headers: Headers()..set('connection', 'close'),
          );
        }
        return Response.text(path);
      },
      host: '127.0.0.1',
      port: 0,
      compression: false,
    );
  });

  tearDown(() => server.stop());

  test('pipelined requests are answered in the order they were sent, '
      'whichever handler finishes first', () async {
    final Socket socket = await Socket.connect('127.0.0.1', server.port);
    addTearDown(socket.destroy);
    socket.write(_get('/wait/80') + _get('/wait/40') + _get('/wait/0'));
    final (List<int> bytes, _) = await _read(
      socket,
      (List<int> got) => _responses(got).length == 3,
    );
    final List<String> bodies = <String>[
      for (final (_, _, List<int> body) in _responses(bytes)) utf8.decode(body),
    ];
    expect(bodies, <String>['/wait/80', '/wait/40', '/wait/0']);
  });

  test('answers larger than the socket takes at once arrive whole and in '
      'order to a client that reads late', () async {
    const int count = 40; // 2.4 MB: more than loopback buffers hold
    final Socket socket = await Socket.connect('127.0.0.1', server.port);
    addTearDown(socket.destroy);
    socket.write(
      <String>[for (var i = 0; i < count; i++) _get('/big/$i')].join(),
    );
    await socket.flush();
    // The server's writes fill the buffers and wait.
    // Not listened to yet, the socket is not read.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final (List<int> bytes, _) = await _read(
      socket,
      (List<int> got) => _responses(got).length == count,
    );
    final List<(int, Map<String, String>, List<int>)> answers = _responses(
      bytes,
    );
    expect(answers, hasLength(count));
    for (var i = 0; i < count; i++) {
      final (int status, _, List<int> body) = answers[i];
      expect(status, 200, reason: 'answer $i');
      expect(body, hasLength(60 * 1024), reason: 'answer $i');
      expect(
        body.every((int b) => b == i % 251),
        isTrue,
        reason: 'answer $i has bytes of another',
      );
    }
  });

  test(
    "a handler's Connection: close ends the connection after its answer",
    () async {
      final Socket socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      socket.write(_get('/close') + _get('/after'));
      final (List<int> bytes, bool closed) = await _read(
        socket,
        (List<int> _) => false,
        within: const Duration(seconds: 5),
      );
      final List<(int, Map<String, String>, List<int>)> answers = _responses(
        bytes,
      );
      expect(closed, isTrue, reason: latin1.decode(bytes));
      expect(answers, hasLength(1), reason: latin1.decode(bytes));
      expect(utf8.decode(answers.single.$3), 'bye');
    },
  );
}
