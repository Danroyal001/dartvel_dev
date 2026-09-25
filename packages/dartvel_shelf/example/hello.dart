// The quick start from the README.
//
//   dart run example/hello.dart
//   curl http://127.0.0.1:8080/hello
//
// Ctrl+C stops it.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final router = Router()
    ..get('/hello', (req) async => Response.text('Hello from dartvel_shelf!\n'))
    ..get('/json', (req) async => Response.json({'ok': true}));

  final server = await serve(router.call, host: '127.0.0.1', port: 8080);
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
