// Streaming responses and server-sent events.
//
//   dart run example/streaming.dart
//
//   curl -N http://127.0.0.1:8080/count
//   curl -N http://127.0.0.1:8080/events
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final router = Router()
    // Response.stream hands you a sink. Each add() is sent as it happens;
    // close() ends the response.
    ..get(
      '/count',
      (req) async => Response.stream((sink) async {
        for (var i = 1; i <= 5; i++) {
          sink.add(utf8.encode('$i\n'));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await sink.close();
      }),
    )
    // Server-sent events. Any response whose content-type is
    // text/event-stream is streamed. A StreamController's onCancel runs when
    // the client goes away, which is where the timer is stopped.
    ..get('/events', (req) async {
      late final Timer timer;
      var n = 0;
      final events = StreamController<List<int>>(
        onCancel: () => timer.cancel(),
      );
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        events.add(utf8.encode('event: tick\ndata: ${n++}\n\n'));
      });
      return Response(
        200,
        headers: Headers()
          ..set('content-type', 'text/event-stream')
          ..set('cache-control', 'no-cache'),
        body: events.stream,
        isStream: true,
      );
    });

  final server = await serve(router.call, host: '127.0.0.1', port: 8080);
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
