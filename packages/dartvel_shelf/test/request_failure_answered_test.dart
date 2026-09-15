// Every request is answered, including one that cannot be read.
//
// serve() built each request -- its URL from the request target, its headers,
// its body -- inside the native request callback and outside every handler's
// try. A request that made any of that throw was never answered, and a target
// Uri.parse refuses did worse than hang: the FormatException was unhandled in
// the root zone and ended the process. One `GET http://x:1/ HTTP/1.1` took
// the whole server down.
//
// These speak raw TCP to the real server, because the failures are in bytes a
// well-behaved HTTP client never sends. Each asserts an answer arrives within
// a bound, that the answer repeats nothing the request carried, and that the
// server still answers the next request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVLogRecord, DVObservability;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// A marker no answer or log line may contain: it is only ever in a request.
const String marker = 'SECRET-7f3a';

/// Well past anything a local answer takes, and far short of a hang.
const Duration bound = Duration(seconds: 5);

final class Exchange {
  Exchange(this.bytes, this.closed, this.elapsed);

  final List<int> bytes;
  final bool closed;
  final Duration elapsed;

  String get text => latin1.decode(bytes);

  /// The status of the first response, or null when none arrived.
  int? get status {
    final RegExpMatch? match =
        RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  @override
  String toString() =>
      'after ${elapsed.inMilliseconds}ms, closed: $closed, received: '
      '${text.length > 200 ? '${text.substring(0, 200)}...' : text}';
}

/// Writes [request] and reads until the server closes or [within] passes.
Future<Exchange> exchange(int port, List<int> request,
    {Duration within = bound}) async {
  final Stopwatch clock = Stopwatch()..start();
  final Socket socket = await Socket.connect('127.0.0.1', port);
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
  socket.add(request);
  final bool wasClosed = await closed.future
      .timeout(within, onTimeout: () => false);
  clock.stop();
  socket.destroy();
  return Exchange(received, wasClosed, clock.elapsed);
}

List<int> get(String target, {List<String> headers = const <String>[]}) =>
    ascii.encode('GET $target HTTP/1.1\r\nHost: localhost\r\n'
        '${headers.map((String h) => '$h\r\n').join()}'
        'Connection: close\r\n\r\n');

void main() {
  late ServerHandle server;

  setUp(() async {
    final Router router = Router()
      ..get('/ok', (Request req) async => Response.text('ok'))
      ..get('/throws', (Request req) => throw StateError('handler $marker'))
      ..get('/throws-later', (Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        throw StateError('handler $marker');
      })
      ..get('/segments', (Request req) async =>
          Response.text(req.url.pathSegments.join('|')));
    server = await serve(router.call, host: '127.0.0.1', port: 0);
  });

  tearDown(() => server.stop());

  Future<void> stillServes() async {
    final Exchange next = await exchange(server.port, get('/ok'));
    expect(next.status, 200, reason: 'the server answers the next request: $next');
  }

  void answered(Exchange result, int status) {
    expect(result.status, status, reason: '$result');
    expect(result.elapsed, lessThan(bound), reason: '$result');
    expect(result.text, isNot(contains(marker)),
        reason: 'an error answer repeats nothing the request carried');
  }

  List<DVLogRecord> logsSince(int count) =>
      DVObservability.recentLogs.skip(count).toList();

  group('a request that cannot be read', () {
    test('a garbled request line is answered 400', () async {
      answered(await exchange(server.port, ascii.encode('GARBAGE $marker\r\n\r\n')), 400);
      await stillServes();
    });

    test('an absolute-form target is served as its path, not a crash',
        () async {
      // RFC 9112 3.2.2: a server accepts the absolute form. Its port is not
      // this server's, and pasting it after the authority made a URL
      // Uri.parse refused -- unhandled, in the callback, ending the process.
      final Exchange result =
          await exchange(server.port, get('http://elsewhere.example:99/ok'));
      answered(result, 200);
      expect(result.text, endsWith('ok\r\n0\r\n\r\n'));
      await stillServes();
    });

    test('an asterisk-form target is answered 400 and the server lives',
        () async {
      final int before = DVObservability.recentLogs.length;
      final Exchange result = await exchange(
          server.port,
          ascii.encode('OPTIONS * HTTP/1.1\r\nHost: localhost\r\n'
              'Connection: close\r\n\r\n'));
      answered(result, 400);
      final List<DVLogRecord> logged = logsSince(before);
      expect(logged, isNotEmpty, reason: 'a refused request is logged');
      await stillServes();
    });

    test('invalid percent-encoding is answered 400, not handed to a route',
        () async {
      // Handed on, it throws in whichever handler first decodes the path --
      // a 500 for the client's mistake, or a 404 that hides it.
      final int before = DVObservability.recentLogs.length;
      final Exchange result =
          await exchange(server.port, get('/segments/$marker%zz'));
      answered(result, 400);
      for (final DVLogRecord record in logsSince(before)) {
        expect(jsonEncode(record.toJson()), isNot(contains(marker)),
            reason: 'the log names the failure, not the request');
      }
      expect(logsSince(before), isNotEmpty);
      await stillServes();
    });

    test('a truncated percent escape is answered 400', () async {
      answered(await exchange(server.port, get('/segments/a%4')), 400);
      await stillServes();
    });

    test('a path that percent-decodes to something other than UTF-8 is '
        'answered 400', () async {
      // Well-formed escapes, but Dart's Uri decodes as UTF-8 and throws, so
      // every route reading pathSegments or queryParameters would answer 500.
      answered(await exchange(server.port, get('/segments/%ff%fe')), 400);
      answered(await exchange(server.port, get('/segments/x?q=%ff')), 400);
      await stillServes();
    });

    test('a header line with no colon is answered 400', () async {
      answered(
          await exchange(server.port,
              get('/ok', headers: <String>['nocolon$marker'])),
          400);
      await stillServes();
    });

    test('a header value that is not UTF-8 is still answered', () async {
      final List<int> request = <int>[
        ...ascii.encode('GET /ok HTTP/1.1\r\nHost: localhost\r\nX-Garbled: '),
        0xff, 0xfe, 0xc3,
        ...ascii.encode('\r\nConnection: close\r\n\r\n'),
      ];
      answered(await exchange(server.port, request), 200);
    });

    test('oversized headers close the connection within the bound', () async {
      // hyper refuses them with 431 and closes while the client is still
      // writing, so the reset can discard the 431 before it is read. What
      // must hold is that the connection does not stay open.
      final Exchange result = await exchange(server.port,
          get('/ok', headers: <String>['X-Big: $marker${'a' * 1000000}']));
      expect(result.closed, isTrue, reason: '$result');
      expect(result.status, anyOf(isNull, 431), reason: '$result');
      expect(result.text, isNot(contains(marker)));
      await stillServes();
    });

    test('too many headers are answered 431', () async {
      answered(
          await exchange(server.port,
              get('/ok', headers: <String>[
                for (int i = 0; i < 500; i++) 'X-$i: $marker',
              ])),
          431);
      await stillServes();
    });
  });

  // A handler serve() is given directly, not a Router: the Router catches its
  // routes' errors itself, so only this reaches serve()'s own failure path.
  // The error message names nothing of the request, because it is the
  // application's text; the request's query and headers carry the marker.
  // The native side's half: what it does with a request Dart never answers,
  // a client that never finishes sending one, and a response it cannot
  // encode. Each used to leave the connection open or drop it unanswered.
  group('the native side', () {
    late ServerHandle slow;
    final Completer<void> never = Completer<void>();

    setUp(() async {
      slow = await serve((Request req) async {
        switch (req.url.path) {
          case '/never':
            await never.future;
          case '/bad-header':
            return Response(200,
                headers: Headers()..set('x-broken', 'line\r\nsplit: $marker'));
          case '/bad-status':
            return Response(42);
        }
        return Response.text('ok');
      }, host: '127.0.0.1', port: 0, requestTimeout: const Duration(seconds: 1));
    });

    tearDown(() => slow.stop());

    test('a request Dart never answers is answered 504 and closed at the '
        'request timeout', () async {
      final Exchange result = await exchange(slow.port, get('/never'));
      answered(result, 504);
      expect(result.closed, isTrue, reason: '$result');
    });

    test('headers that never finish are closed at the request timeout',
        () async {
      final Exchange result = await exchange(
          slow.port, ascii.encode('GET /ok HTTP/1.1\r\nHost: localhost\r\n'));
      expect(result.closed, isTrue,
          reason: 'one stalled connection per slot is the whole attack: '
              '$result');
      expect(result.elapsed, lessThan(bound));
    });

    test('a body that never arrives is answered 408 and closed', () async {
      final Exchange result = await exchange(
          slow.port,
          ascii.encode('POST /ok HTTP/1.1\r\nHost: localhost\r\n'
              'Content-Length: 100\r\n\r\npartial'));
      answered(result, 408);
      expect(result.closed, isTrue, reason: '$result');
    });

    test('a response header the native side cannot send is answered 500',
        () async {
      // It panicked on unwrap: the connection dropped with no answer.
      final Exchange result = await exchange(slow.port, get('/bad-header'));
      answered(result, 500);
      final Exchange next = await exchange(slow.port, get('/ok'));
      expect(next.status, 200, reason: '$next');
    });

    test('a status that is not an HTTP status is answered 500, not 200',
        () async {
      answered(await exchange(slow.port, get('/bad-status')), 500);
    });

    test('a request timeout that is not positive is refused', () async {
      await expectLater(
          serve((Request req) async => Response.text('ok'),
              host: '127.0.0.1', port: 0, requestTimeout: Duration.zero),
          throwsArgumentError);
    });
  });

  group('a handler that fails', () {
    late ServerHandle bare;

    setUp(() async {
      bare = await serve((Request req) {
        if (req.url.path == '/throws') throw StateError('handler failed');
        return Future<Response>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('handler failed later');
        });
      }, host: '127.0.0.1', port: 0);
    });

    tearDown(() => bare.stop());

    test('throwing synchronously is answered 500, and logged without the '
        'request', () async {
      final int before = DVObservability.recentLogs.length;
      answered(
          await exchange(bare.port,
              get('/throws?q=$marker', headers: <String>['X-Token: $marker'])),
          500);
      final List<DVLogRecord> logged = logsSince(before);
      expect(logged, isNotEmpty, reason: 'a failed request is logged');
      for (final DVLogRecord record in logged) {
        expect(jsonEncode(record.toJson()), isNot(contains(marker)),
            reason: 'neither the target, a header nor the error message -- '
                'which quoted the request -- is logged');
      }
      await stillServes();
    });

    test('throwing asynchronously is answered 500', () async {
      final int before = DVObservability.recentLogs.length;
      answered(await exchange(bare.port, get('/throws-later?q=$marker')), 500);
      expect(logsSince(before), isNotEmpty);
      for (final DVLogRecord record in logsSince(before)) {
        expect(jsonEncode(record.toJson()), isNot(contains(marker)));
      }
      await stillServes();
    });
  });
}
