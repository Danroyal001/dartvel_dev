// A request that carries no body -- a GET, most of all -- is handed to Dart
// marked as having none, and gets no body stream: no pull object, no
// generator, no entry in the table of bodies being read. A request with a
// body still streams it. What a handler reads is the same either way.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/src/request_body.dart' show RequestBodyStream;
import 'package:test/test.dart';

void main() {
  late ServerHandle server;
  late HttpClient client;

  setUp(() async {
    final router = Router()
      ..get('/read', (Request req) async =>
          Response.text('[${await req.body.text()}]'))
      ..post('/read', (Request req) async =>
          Response.text('[${await req.body.text()}]'));
    server = await serve(router.call,
        host: '127.0.0.1', port: 0, routeBodyLimits: router.bodyLimits);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<String> send(String method, [String? body]) async {
    final request = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${server.port}/read'));
    if (body != null) request.write(body);
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  test('a request without a body gets no body stream, and reads empty',
      () async {
    final before = RequestBodyStream.created;
    for (var i = 0; i < 5; i++) {
      expect(await send('GET'), '[]');
    }
    expect(RequestBodyStream.created - before, 0);
  });

  test('a request with a body still streams it', () async {
    final before = RequestBodyStream.created;
    expect(await send('POST', 'hello'), '[hello]');
    expect(RequestBodyStream.created - before, 1);
  });
}
