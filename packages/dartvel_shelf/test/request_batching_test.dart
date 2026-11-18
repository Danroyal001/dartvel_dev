// Requests are taken from the native side in batches on one wakeup.
//
// Under load many requests arrive between two turns of the isolate's event
// loop, and the whole batch is taken at once. These check what must not
// change because of it: every request reaches its own handler call with its
// own method, path, headers and body, more requests than one batch holds are
// all answered, and a steady stream of requests does not starve the event
// loop of its timers.
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
      ..get('/echo/:n', (Request req) async {
        return Response.text(
            '${req.method} ${req.params['n']} ${req.headers.get('x-n')}');
      })
      ..post('/sum', (Request req) async {
        final text = await req.body.text();
        return Response.text('${text.length}');
      });
    server = await serve(router.call,
        host: '127.0.0.1', port: 0, routeBodyLimits: router.bodyLimits);
    client = HttpClient()..maxConnectionsPerHost = 64;
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('1,000 concurrent requests each get their own answer', () async {
    final answers = await Future.wait(List.generate(1000, (n) async {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/echo/$n'));
      request.headers.set('x-n', 'h$n');
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    }));
    for (var n = 0; n < 1000; n++) {
      expect(answers[n], 'GET $n h$n');
    }
  });

  test('bodies stay with their requests', () async {
    final answers = await Future.wait(List.generate(300, (n) async {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:${server.port}/sum'));
      request.write('x' * n);
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    }));
    for (var n = 0; n < 300; n++) {
      expect(answers[n], '$n');
    }
  });

  test('timers still fire while requests keep arriving', () async {
    // Warmed up first, on the same connections: the first requests of a
    // process are compiled as they run, and a compiling isolate runs no
    // timers either, whatever the server does.
    for (var round = 0; round < 10; round++) {
      await Future.wait(List.generate(32, (n) async {
        final response = await (await client.getUrl(Uri.parse(
                'http://127.0.0.1:${server.port}/echo/$n')))
            .close();
        await response.drain<void>();
      }));
    }
    var ticks = 0;
    final timer = Timer.periodic(
        const Duration(milliseconds: 10), (_) => ticks++);
    final stopwatch = Stopwatch()..start();
    var sent = 0;
    await Future.wait(List.generate(32, (_) async {
      while (stopwatch.elapsedMilliseconds < 500) {
        final response = await (await client.getUrl(Uri.parse(
                'http://127.0.0.1:${server.port}/echo/${sent++}')))
            .close();
        await response.drain<void>();
      }
    }));
    timer.cancel();
    expect(ticks, greaterThan(10),
        reason: 'a 10 ms timer must keep running under a stream of requests');
  });
}
