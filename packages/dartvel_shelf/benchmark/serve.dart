// The benchmark routes of compare.dart on dartvel_shelf and on shelf, in a
// process of their own so a load generator outside it measures the server
// alone.
//
//   dart run benchmark/serve.dart <dartvel|shelf> <static dir>
//
// Prints `ready <port>` once listening and serves until SIGTERM. Relic 2
// serves the same routes from benchmark/relic/bin/serve.dart:
//   GET  /plaintext   13-byte text
//   GET  /json        {"message":"Hello, World!"}
//   GET  /static/...  files under <static dir>
//   POST /upload      counts the body, answers the count
//   GET  /download    50 MiB stream
//   GET  /ws          WebSocket echo
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:dartvel_shelf/web_socket.dart' as native_ws;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:shelf_web_socket/shelf_web_socket.dart' as shelf_ws;

const downloadBytes = 50 * 1024 * 1024;

Stream<List<int>> payload() async* {
  final chunk = Uint8List(64 * 1024);
  for (var sent = 0; sent < downloadBytes; sent += chunk.length) {
    yield chunk;
  }
}

Future<void> main(List<String> args) async {
  final engine = args[0];
  final staticDir = args[1];
  final int port;
  final Future<void> Function() stop;
  if (engine == 'dartvel' ||
      engine.startsWith('dartvel') &&
          int.tryParse(engine.substring(7)) != null) {
    // `dartvel4` is four isolates on one port with serve(shared: true), as
    // Relic's `native4` is four isolates.
    final isolates = engine == 'dartvel' ? 1 : int.parse(engine.substring(7));
    final nativeLibrary =
        Platform.environment['DARTVEL_SHELF_LIBRARY'] ??
        'lib/native/linux-x64/libdartvel_shelf.so';
    final library = await File(nativeLibrary).readAsBytes();
    final server = await _serveDartvel((library, staticDir, 0, isolates > 1));
    for (var i = 1; i < isolates; i++) {
      final ready = ReceivePort();
      await Isolate.spawn(_serveDartvelIsolate, (
        library,
        staticDir,
        server.port,
        ready.sendPort,
      ));
      await ready.first;
    }
    port = server.port;
    stop = server.stop;
  } else {
    final ws = shelf_ws.webSocketHandler((channel, _) {
      channel.sink.addStream(channel.stream).then((_) => channel.sink.close());
    });
    final files = shelf_static.createStaticHandler(staticDir);
    final server = await shelf_io.serve(
      (req) async {
        final path = req.url.path;
        if (path.startsWith('static/')) {
          return files(req.change(path: 'static'));
        }
        switch (path) {
          case 'plaintext':
            return shelf.Response.ok('Hello, World!');
          case 'json':
            return shelf.Response.ok(
              jsonEncode({'message': 'Hello, World!'}),
              headers: {'content-type': 'application/json'},
            );
          case 'ws':
            return ws(req);
          case 'upload':
            final received = await req.read().fold<int>(
              0,
              (n, chunk) => n + chunk.length,
            );
            return shelf.Response.ok('$received');
          case 'download':
            return shelf.Response.ok(
              payload(),
              headers: {'content-length': '$downloadBytes'},
            );
        }
        return shelf.Response.notFound('Not found');
      },
      InternetAddress.loopbackIPv4,
      0,
    );
    port = server.port;
    stop = () => server.close(force: true);
  }
  stdout.writeln('ready $port');
  await ProcessSignal.sigterm.watch().first;
  await stop();
  exit(0);
}

const _etag = 'relic-browser-1';

final _items = jsonEncode([
  for (var i = 0; i < 20; i++)
    {
      'id': i,
      'name': 'item $i',
      'tags': ['new', 'sale'],
      'price': 100 + i,
    },
]);

String? _cookie(String? header, String name) {
  if (header == null) return null;
  for (final pair in header.split(';')) {
    final at = pair.indexOf('=');
    if (at > 0 && pair.substring(0, at).trim() == name) {
      return pair.substring(at + 1).trim();
    }
  }
  return null;
}

Future<void> _serveDartvelIsolate(
  (List<int>, String, int, SendPort) args,
) async {
  final (library, staticDir, port, ready) = args;
  await _serveDartvel((library, staticDir, port, true));
  ready.send(null);
}

Future<dv.ServerHandle> _serveDartvel((List<int>, String, int, bool) args) {
  final (library, staticDir, port, shared) = args;
  dv.embedNativeServerLibrary(library);
  final random = Random(1);
  final ws = native_ws.webSocketHandler((channel, _) {
    channel.sink.addStream(channel.stream).then((_) => channel.sink.close());
  });
  final router = dv.Router()
    ..get('/plaintext', (req) async {
      return dv.Response.text('Hello, World!');
    })
    ..get('/json', (req) async {
      return dv.Response.json({'message': 'Hello, World!'});
    })
    // Relic's own load workloads (its benchmark/lib/src/load_app.dart),
    // so its http_load.dart can drive this server as a URL target.
    ..get('/headers', (req) async {
      final agent = req.headers.get('user-agent') ?? '';
      final languages = (req.headers.get('accept-language') ?? '')
          .split(',')
          .length;
      final session = _cookie(req.headers.get('cookie'), 'session');
      return dv.Response.text(
        '${agent.length} $languages ${session?.length ?? 0}',
      );
    })
    ..get('/browser', (req) async {
      final host = req.headers.get('host')?.split(':').first;
      final session = _cookie(req.headers.get('cookie'), 'session');
      final matched = (req.headers.get('if-none-match') ?? '')
          .split(',')
          .any((tag) => tag.trim() == '"$_etag"');
      if (matched) {
        return dv.Response(304, headers: dv.Headers({'etag': '"$_etag"'}));
      }
      return dv.Response.text(
        '{"host":${jsonEncode(host)},'
        '"session":${jsonEncode(session)},"items":$_items}',
        headers: dv.Headers({
          'etag': '"$_etag"',
          'cache-control': 'private, max-age=60',
          'content-type': 'application/json',
        }),
      );
    })
    ..get('/alloc', (req) async {
      final parts = List.generate(4000, (i) => 'item-$i-${i * 7}');
      return dv.Response.text(parts.join(',').substring(0, 1024));
    })
    ..get('/mixed', (req) async {
      if (random.nextInt(100) == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return dv.Response.text('Hello, World!');
    })
    ..get('/ws', (req) async {
      return ws(req);
    })
    ..post('/upload', (req) async {
      final received = await req.body.stream.fold<int>(
        0,
        (n, chunk) => n + chunk.length,
      );
      return dv.Response.text('$received');
    })
    ..get('/download', (req) async {
      return dv.Response(
        200,
        body: payload(),
        headers: dv.Headers({'content-length': '$downloadBytes'}),
      );
    });
  return dv.serve(
    router.call,
    port: port,
    shared: shared,
    compression: false,
    staticDir: staticDir,
    maxBodyBytes: downloadBytes + 1,
    routeBodyLimits: router.bodyLimits,
  );
}
