// The benchmark routes of ../compare.dart on Relic 2, for its `relic_io`,
// `relic_native` and `relic_native4` engines.
//
//   dart run bin/serve.dart <io|native> <isolates> <static dir>
//
// Prints `ready <port>` once listening and serves until SIGTERM. The
// routes are the ones ../serve.dart gives shelf and dartvel_shelf.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:relic/relic.dart';
import 'package:relic_native/relic_native.dart';
import 'package:web_socket/web_socket.dart'
    show BinaryDataReceived, CloseReceived, TextDataReceived;

const downloadBytes = 50 * 1024 * 1024;

Stream<Uint8List> payload() async* {
  final chunk = Uint8List(64 * 1024);
  for (var sent = 0; sent < downloadBytes; sent += chunk.length) {
    yield chunk;
  }
}

RelicApp benchmarkApp(String staticDir) => RelicApp()
  ..get('/plaintext', (req) => Response.ok(body: Body.fromString('Hello, World!')))
  ..get(
    '/json',
    (req) => Response.ok(
      body: Body.fromString(
        jsonEncode({'message': 'Hello, World!'}),
        mimeType: MimeType.json,
      ),
    ),
  )
  ..anyOf({Method.get, Method.head}, '/static/**',
      StaticHandler.directory(
        Directory(staticDir),
        cacheControl: (_, _) => CacheControlHeader(maxAge: 3600),
      ).asHandler)
  ..post('/upload', (req) async {
    var received = 0;
    await for (final chunk in req.read()) {
      received += chunk.length;
    }
    return Response.ok(body: Body.fromString('$received'));
  })
  ..get(
    '/download',
    (req) => Response.ok(
      body: Body.fromDataStream(
        payload(),
        contentLength: downloadBytes,
        mimeType: MimeType.octetStream,
      ),
    ),
  )
  ..get(
    '/ws',
    (req) => WebSocketUpgrade((ws) {
      ws.events.listen((event) {
        switch (event) {
          case TextDataReceived(:final text):
            ws.trySendText(text);
          case BinaryDataReceived(:final data):
            ws.trySendBytes(data);
          case CloseReceived():
            break;
        }
      });
    }),
  );

Future<void> main(List<String> args) async {
  final kind = args[0];
  final isolates = int.parse(args[1]);
  final staticDir = args[2];
  final app = benchmarkApp(staticDir);
  final RelicServer server;
  switch (kind) {
    case 'io':
      server = await app.run(
        () => IOAdapter.bind(
          InternetAddress.loopbackIPv4,
          port: 0,
          shared: isolates > 1,
        ),
        noOfIsolates: isolates,
      );
    case 'native':
      // The group ties the isolates to one native server, as serveNative
      // does, so port 0 works with several of them.
      server = await app.run(
        () => NativeAdapter.bind(
          InternetAddress.loopbackIPv4,
          port: 0,
          group: 'compare/$pid',
        ),
        noOfIsolates: isolates,
      );
    default:
      throw ArgumentError.value(kind, 'kind', 'io or native');
  }
  stdout.writeln('ready ${server.port}');
  await ProcessSignal.sigterm.watch().first;
  await server.close();
  exit(0);
}
