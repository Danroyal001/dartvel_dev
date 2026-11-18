// The isolate drives its server's runtime while it has requests to take and
// hands it to a helper thread when it has none (AW_FLAG_DRIVEN). What must
// hold across every hand-off: a request that arrives while the helper drives
// wakes the isolate and is answered; an answer given after the isolate has
// parked is still written; and slow and fast handlers on one server do not
// hold each other up.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late ServerHandle server;
  late HttpClient client;

  setUp(() async {
    final router = Router()
      ..get('/fast', (Request req) async => Response.text('fast'))
      ..get('/slow/:ms', (Request req) async {
        await Future<void>.delayed(
            Duration(milliseconds: int.parse(req.params['ms']!)));
        return Response.text('slow ${req.params['ms']}');
      });
    server = await serve(router.call, host: '127.0.0.1', port: 0);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<String> get(String path) async {
    final response = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}$path')))
        .close();
    return response.transform(utf8.decoder).join();
  }

  test('requests after idle gaps are each answered', () async {
    for (var i = 0; i < 20; i++) {
      expect(await get('/fast'), 'fast');
      // Longer than the isolate waits before it parks, so the next request
      // reaches it through the helper.
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  test('an answer given after the isolate parked is written', () async {
    expect(await get('/slow/60'), 'slow 60');
    final answers = await Future.wait(
        <Future<String>>[for (var i = 0; i < 10; i++) get('/slow/${20 + i * 5}')]);
    for (var i = 0; i < 10; i++) {
      expect(answers[i], 'slow ${20 + i * 5}');
    }
  });

  test('a slow handler does not hold up fast ones', () async {
    final slow = get('/slow/2000');
    final clock = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      expect(await get('/fast'), 'fast');
    }
    expect(clock.elapsedMilliseconds, lessThan(1500),
        reason: 'fifty fast requests finish while one slow one is waited on');
    expect(await slow, 'slow 2000');
  });

  test('a server stops cleanly with an answer still pending', () async {
    final pending = get('/slow/2000').then<Object?>((s) => s, onError: (Object e) => e);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final clock = Stopwatch()..start();
    await server.stop();
    expect(clock.elapsedMilliseconds, lessThan(8000));
    await pending;
    server = await serve((Request req) async => Response.text('again'),
        host: '127.0.0.1', port: 0);
    expect(await get('/'), 'again');
  });
}
