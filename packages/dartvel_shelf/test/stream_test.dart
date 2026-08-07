// Exercises streaming responses through the real native server.
//
// Streaming is the one path that cannot be checked by calling the router
// directly: it only works if the compiled library exports the streaming FFI
// symbols and can accept chunks from Dart's thread. A router-level test passes
// against a library that has neither.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late ServerHandle server;
  late int port;
  late HttpClient client;

  setUp(() async {
    final router = Router()
      ..get('/ticks', (Request req) async {
        return Response.stream(
          (StreamSink<List<int>> sink) async {
            for (var i = 1; i <= 3; i++) {
              sink.add(utf8.encode('tick $i\n'));
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            await sink.close();
          },
          headers: Headers()..set('content-type', 'text/event-stream'),
        );
      })
      ..get('/burst', (Request req) async {
        // A burst emitted faster than the socket drains, so the native
        // buffering path is exercised rather than only the steady one.
        return Response.stream((StreamSink<List<int>> sink) {
          for (var i = 0; i < 200; i++) {
            sink.add(utf8.encode('$i,'));
          }
          sink.close();
        });
      });

    port = 8300 + (DateTime.now().microsecondsSinceEpoch % 400);
    server = await serve(router, host: '127.0.0.1', port: port);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<HttpClientResponse> get(String path) async {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    return request.close();
  }

  test('chunks reach the client as they are produced', () async {
    final response = await get('/ticks');

    expect(response.statusCode, 200);
    expect(response.headers.value('content-type'), contains('event-stream'));

    final body = await response.transform(utf8.decoder).join();
    expect(body, 'tick 1\ntick 2\ntick 3\n');
  });

  test('the response arrives before the stream finishes', () async {
    // A buffered implementation would only send headers at the end; the point
    // of streaming is that a client can start reading first.
    final started = DateTime.now();
    final response = await get('/ticks');
    final headersAt = DateTime.now().difference(started);

    final firstChunk =
        await response.transform(utf8.decoder).transform(const LineSplitter()).first;
    expect(firstChunk, 'tick 1');
    // Three 20ms ticks; headers must not have waited for all of them.
    expect(headersAt, lessThan(const Duration(milliseconds: 60)));
  });

  test('a fast burst arrives complete and in order', () async {
    final body = await (await get('/burst')).transform(utf8.decoder).join();

    expect(
      body,
      List<int>.generate(200, (int i) => i).map((int i) => '$i,').join(),
    );
  });
}
