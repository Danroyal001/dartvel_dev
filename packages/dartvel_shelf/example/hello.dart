// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' as io;

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  print('[dartvel_shelf] Bootstrapping example server...');

  final router = Router()
    ..get('/hello', (req) async {
      print('[dartvel_shelf] → GET /hello');
      return Response.text('Hello from dartvel_shelf!\n',
          headers: Headers()..set('content-type', 'text/plain; charset=utf-8'));
    })
    ..get('/json', (req) async {
      print('[dartvel_shelf] → GET /json');
      return Response.json({'ok': true});
    });

  const host = '0.0.0.0';
  const port = 8080;
  print('[dartvel_shelf] Starting Actix-web server on http://$host:$port');
  final handle =
      await serve(router.call, host: host, port: port, tls: null, h2c: true);
  print('[dartvel_shelf] - Try: curl http://$host:$port/hello');
  print('[dartvel_shelf] - Try: curl http://$host:$port/json');
  print('[dartvel_shelf] Press Ctrl+C to stop.');

  final shutdownComplete = Completer<void>();
  var shuttingDown = false;

  Future<void> triggerShutdown(String reason) async {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    print('[dartvel_shelf] $reason — stopping server...');
    try {
      await handle.stop();
      print('[dartvel_shelf] Server stopped.');
    } finally {
      if (!shutdownComplete.isCompleted) {
        shutdownComplete.complete();
      }
    }
  }

  final signalSubscriptions = <StreamSubscription<io.ProcessSignal>>[];
  for (final signal in [io.ProcessSignal.sigint, io.ProcessSignal.sigterm]) {
    signalSubscriptions.add(signal.watch().listen((sig) {
      print('[dartvel_shelf] Received $sig');
      unawaited(triggerShutdown('Received $sig'));
    }));
  }

  // Keep the isolate alive while the native server runs.
  await shutdownComplete.future;

  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
  print('[dartvel_shelf] Shutdown complete. Goodbye!');
}
