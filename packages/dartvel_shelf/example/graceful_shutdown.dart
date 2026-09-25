// Letting requests that are already running finish before stopping.
//
// ServerHandle.stop() stops accepting connections and returns once the
// server has closed, allowing in-flight connections up to five seconds. It
// is a blocking call into the native side, so while it runs this isolate
// cannot finish a handler that is still awaiting something. Wait for those
// first, then stop.
//
//   dart run example/graceful_shutdown.dart
//   curl http://127.0.0.1:8080/slow &  sleep 0.5; kill -INT <pid>
import 'dart:async';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

typedef Handler = Future<Response> Function(Request request);

var _inFlight = 0;
var _draining = false;

/// Counts running requests, and reports the instance as out of rotation
/// while draining so a load balancer stops sending new ones.
Handler drainable(Handler inner) => (req) async {
  if (_draining && req.url.path == '/health') {
    return Response.json({'status': 'draining'}, status: 503);
  }
  _inFlight++;
  try {
    return await inner(req);
  } finally {
    _inFlight--;
  }
};

Future<void> main() async {
  final router = Router()
    ..get('/slow', (req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return Response.text('finished\n');
    });

  final server = await serve(
    drainable(router.call),
    host: '127.0.0.1',
    port: 8080,
    routeBodyLimits: router.bodyLimits,
  );
  stdout.writeln(
    'Listening on http://${server.host}:${server.port} (pid $pid)',
  );

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);

  _draining = true;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (_inFlight > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await server.stop();
  stdout.writeln('Stopped with $_inFlight request(s) unfinished');
  exit(0);
}
