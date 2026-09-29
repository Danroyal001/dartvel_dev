// Run: ~/heavy.sh dart run benchmark/compare.dart
// Each engine/scenario runs in a fresh process. RSS includes the Dart client,
// VM/JIT and (for Dartvel) the native runtime, not just the server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:dartvel_shelf/web_socket.dart' as native_ws;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart' as shelf_ws;

const size = 50 * 1024 * 1024;
Stream<List<int>> payload() async* {
  final chunk = Uint8List(64 * 1024);
  for (var i = 0; i < size; i += chunk.length) {
    yield chunk;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    for (var trial = 1; trial <= 3; trial++) {
      for (final scenario in ['hello', 'upload', 'download', 'websocket']) {
        for (final engine in ['shelf', 'dartvel']) {
          final result = await Process.run(Platform.resolvedExecutable, [
            if (['dart', 'dartvm', 'dart.exe'].contains(
              Platform.resolvedExecutable.split(Platform.pathSeparator).last,
            ))
              Platform.script.toFilePath(),
            engine,
            scenario,
          ]);
          if (result.exitCode != 0) {
            stderr.write(result.stderr);
            exitCode = result.exitCode;
            return;
          }
          final data = jsonDecode(
            (result.stdout as String).trim(),
          ) as Map<String, dynamic>;
          stdout.writeln(jsonEncode({'trial': trial, ...data}));
        }
      }
    }
    return;
  }
  final engine = args[0];
  final scenario = args[1];
  late int port;
  late Future<void> Function() stop;
  if (engine == 'dartvel') {
    dv.embedNativeServerLibrary(
      await File('lib/native/linux-x64/libdartvel_shelf.so').readAsBytes(),
    );
    final ws = native_ws.webSocketHandler((channel, _) {
      channel.sink.addStream(channel.stream).then((_) => channel.sink.close());
    });
    final server = await dv.serve(
      (req) async {
        if (req.url.path == '/ws') return ws(req);
        if (req.url.path == '/upload') {
          final bytes = await req.body.stream.fold<int>(
            0,
            (n, chunk) => n + chunk.length,
          );
          return dv.Response.text('$bytes');
        }
        if (req.url.path == '/download') {
          return dv.Response(
            200,
            body: payload(),
            headers: dv.Headers({'content-length': '$size'}),
          );
        }
        return dv.Response.text('hello');
      },
      port: 0,
      compression: false,
      maxBodyBytes: size + 1,
    );
    port = server.port;
    stop = server.stop;
  } else {
    final ws = shelf_ws.webSocketHandler((channel, _) {
      channel.sink.addStream(channel.stream).then((_) => channel.sink.close());
    });
    final server = await shelf_io.serve(
      (req) async {
        if (req.url.path == 'ws') return ws(req);
        if (req.url.path == 'upload') {
          final bytes = await req.read().fold<int>(
            0,
            (n, chunk) => n + chunk.length,
          );
          return shelf.Response.ok('$bytes');
        }
        if (req.url.path == 'download') {
          return shelf.Response.ok(
            payload(),
            headers: {'content-length': '$size'},
          );
        }
        return shelf.Response.ok('hello');
      },
      '127.0.0.1',
      0,
    );
    port = server.port;
    stop = () async {
      await server.close(force: true);
    };
  }
  final client = HttpClient()..maxConnectionsPerHost = 16;
  final root = Uri.parse('http://127.0.0.1:$port/');
  Future<int> hello() async {
    final watch = Stopwatch()..start();
    final response = await (await client.getUrl(root)).close();
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    await response.drain<void>();
    return watch.elapsedMicroseconds;
  }

  // Equal warm-up before the measured scenario.
  for (var i = 0; i < 100; i++) {
    await hello();
  }
  final watch = Stopwatch()..start();
  final metrics = <String, Object>{};
  switch (scenario) {
    case 'hello':
      final latencies = <int>[];
      await Future.wait(
        List.generate(16, (_) async {
          for (var i = 0; i < 125; i++) {
            latencies.add(await hello());
          }
        }),
      );
      watch.stop();
      latencies.sort();
      metrics.addAll({
        'requests': latencies.length,
        'rps': latencies.length * 1000000 / watch.elapsedMicroseconds,
        'p50_ms': latencies[latencies.length ~/ 2] / 1000,
        'p95_ms': latencies[(latencies.length * .95).floor()] / 1000,
      });
    case 'upload':
      final req = await client.postUrl(root.resolve('upload'));
      req.contentLength = size;
      await req.addStream(payload());
      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();
      if (text != '$size') {
        throw StateError('Upload received $text bytes');
      }
      watch.stop();
      metrics['mib_per_second'] = 50 * 1000000 / watch.elapsedMicroseconds;
    case 'download':
      final response = await (await client.getUrl(root.resolve('download')))
          .close();
      final bytes = await response.fold<int>(0, (n, chunk) => n + chunk.length);
      if (bytes != size) {
        throw StateError('Download received $bytes bytes');
      }
      watch.stop();
      metrics['mib_per_second'] = 50 * 1000000 / watch.elapsedMicroseconds;
    case 'websocket':
      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final messages = StreamIterator<Object?>(ws);
      final message = 'x' * 64;
      for (var i = 0; i < 500; i++) {
        ws.add(message);
        if (!await messages.moveNext() || messages.current != message) {
          throw StateError('Echo mismatch');
        }
      }
      watch.stop();
      metrics['messages_per_second'] =
          500 * 1000000 / watch.elapsedMicroseconds;
      await ws.close();
      await messages.cancel();
  }
  metrics['elapsed_ms'] = watch.elapsedMicroseconds / 1000;
  metrics['peak_rss_mib'] = ProcessInfo.maxRss / (1024 * 1024);
  client.close(force: true);
  await stop();
  stdout.writeln(
    jsonEncode({'engine': engine, 'scenario': scenario, ...metrics}),
  );
}
