// The streaming transport, against a real socket.
//
// Server-sent events cannot go through dvSendHttpRequest: it waits for the
// whole body, so a stream that never ends never returns. What matters here is
// that chunks arrive as they are produced and the client survives until the
// body finishes — neither is observable without a server that actually
// trickles.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((HttpRequest request) async {
      switch (request.uri.path) {
        case '/ticks':
          request.response.headers.contentType =
              ContentType('text', 'event-stream');
          for (var i = 1; i <= 3; i++) {
            request.response.write('data: tick $i\n\n');
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await request.response.close();
        case '/json':
          request.response.write('{"ok":true}');
          await request.response.close();
        case '/notjson':
          request.response.write('not json at all');
          await request.response.close();
        case '/empty':
          await request.response.close();
        default:
          request.response.statusCode = 404;
          await request.response.close();
      }
    });
  });

  tearDown(() => server.close(force: true));

  test('a streamed body arrives in pieces, not all at once', () async {
    final response = await dvStreamHttpRequest(
        DVHttpRequest(url: base.replace(path: '/ticks'), method: 'GET'));

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('event-stream'));

    final chunks = <String>[];
    await for (final chunk in response.body) {
      chunks.add(utf8.decode(chunk));
    }

    // Concatenated, every tick is present and in order.
    expect(chunks.join(), 'data: tick 1\n\ndata: tick 2\n\ndata: tick 3\n\n');
  });

  test('the response is available before the body finishes', () async {
    final started = DateTime.now();
    final response = await dvStreamHttpRequest(
        DVHttpRequest(url: base.replace(path: '/ticks'), method: 'GET'));
    final headersAt = DateTime.now().difference(started);

    // Three 20ms ticks; a buffered read would have waited for all of them.
    expect(headersAt, lessThan(const Duration(milliseconds: 60)));

    final first = await response.body.first;
    expect(utf8.decode(first), startsWith('data: tick 1'));
  });

  test('abandoning the stream does not hang', () async {
    final response = await dvStreamHttpRequest(
        DVHttpRequest(url: base.replace(path: '/ticks'), method: 'GET'));

    // Cancelling has to close the client too, or the process keeps a socket
    // open for a body nobody is reading.
    final subscription = response.body.listen((_) {});
    await subscription.cancel();
  });

  test('a JSON body decodes through data', () async {
    final response = await dvSendHttpRequest(
        DVHttpRequest(url: base.replace(path: '/json'), method: 'GET'));

    expect(response.data, <String, Object?>{'ok': true});
  });

  test('a body that is not JSON comes back as text, not an exception',
      () async {
    // An error page from a proxy is the common case, and throwing there hides
    // the status that explains it.
    final response = await dvSendHttpRequest(
        DVHttpRequest(url: base.replace(path: '/notjson'), method: 'GET'));

    expect(response.data, 'not json at all');
  });

  test('an empty body is null rather than an error', () async {
    final response = await dvSendHttpRequest(
        DVHttpRequest(url: base.replace(path: '/empty'), method: 'GET'));

    expect(response.data, isNull);
  });
}
