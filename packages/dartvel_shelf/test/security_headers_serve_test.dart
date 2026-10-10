// The headers every response leaves a Dartvel server with.
//
// Started on a real socket, because the point is what reaches the client: a
// test of the helper alone would pass against a serve() that never called it.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  Router app() => Router()
    ..get('/page', (Request req) async => Response.text('<p>hi</p>',
        headers: Headers(<String, String>{'content-type': 'text/html'})))
    ..get('/framed', (Request req) async => Response.text('ok',
        headers: Headers(<String, String>{'x-frame-options': 'DENY'})));

  Future<HttpHeaders> headersOf(int port, String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path')))
              .close();
      await response.drain<void>();
      return response.headers;
    } finally {
      client.close(force: true);
    }
  }

  test('a page goes out with the default security headers', () async {
    final ServerHandle server = await serve(app().call, port: 0);
    addTearDown(server.stop);
    final HttpHeaders headers = await headersOf(server.port, '/page');
    expect(headers.value('x-content-type-options'), 'nosniff');
    expect(headers.value('x-frame-options'), 'SAMEORIGIN');
    expect(headers.value('referrer-policy'), 'strict-origin-when-cross-origin');
    expect(headers.value('strict-transport-security'), isNull,
        reason: 'HSTS only means something on a response sent over TLS');
  });

  test('a route that set a header keeps its own value', () async {
    final ServerHandle server = await serve(app().call, port: 0);
    addTearDown(server.stop);
    final HttpHeaders headers = await headersOf(server.port, '/framed');
    expect(headers['x-frame-options'], <String>['DENY']);
    expect(headers.value('x-content-type-options'), 'nosniff');
  });

  test('a 404 is covered as well as a route', () async {
    final ServerHandle server = await serve(app().call, port: 0);
    addTearDown(server.stop);
    final HttpHeaders headers = await headersOf(server.port, '/missing');
    expect(headers.value('x-content-type-options'), 'nosniff');
  });

  test('an empty map turns the defaults off', () async {
    final ServerHandle server = await serve(app().call,
        port: 0, securityHeaders: const <String, String>{});
    addTearDown(server.stop);
    final HttpHeaders headers = await headersOf(server.port, '/page');
    expect(headers.value('x-frame-options'), isNull);
    expect(headers.value('x-content-type-options'), isNull);
  });
}
