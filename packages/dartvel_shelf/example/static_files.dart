// Files from a directory, served by the native side under /static/.
//
//   dart run example/static_files.dart     (from the package root)
//
//   curl http://127.0.0.1:8080/static/hello.txt   # example/public/hello.txt
//   curl http://127.0.0.1:8080/                   # the router
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final router = Router()
    ..get('/', (req) async => Response.text('Try /static/hello.txt\n'));

  final server = await serve(
    router.call,
    host: '127.0.0.1',
    port: 8080,
    // Resolved against the working directory. An absolute path avoids
    // depending on where the process was started.
    staticDir: 'example/public',
  );
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
