// shelf, Relic 2 and dartvel_shelf, each server in a fresh process of its
// own, measured from outside it.
//
// Build the servers AOT first (from packages/dartvel_shelf):
//   dart compile exe benchmark/serve.dart -o build/benchmark/serve
//   (cd benchmark/relic && dart pub get && dart build cli -t bin/serve.dart)
// then:
//   ~/heavy.sh dart run benchmark/compare.dart [options]
//
// Options (all optional):
//   --engines=shelf,relic_io,relic_native,relic_native4,dartvel,dartvel4
//            (and dartvel_before: --serve-before's binary on
//            --before-library, an older dartvel_shelf to compare with)
//   --scenarios=plaintext,json,headers,static,many,startup,websocket,
//               websocket_pipelined,upload,download
//   --trials=3 --seconds=5 --connections=64 --many=1024
//   --serve=build/benchmark/serve
//   --relic=benchmark/relic/build/cli/linux_x64/bundle/bin/serve
//   --serve-before=<serve built from an older checkout>
//   --before-library=<that checkout's lib/native/linux-x64/libdartvel_shelf.so>
//
// The HTTP scenarios are driven by oha (https://github.com/hatoo/oha), the
// load tool Relic's own http_load.dart uses, in a closed loop: `connections`
// requests always in flight on keep-alive connections, after a 2 s warm-up
// of the same request. `many` is plaintext at `--many` connections.
// `headers` is plaintext with the 18 browser headers of Relic's headers
// workload. `static` is a 4 KiB file through each engine's own static
// handler (shelf_static, Relic's StaticHandler, dartvel_shelf's staticDir).
// WebSocket, upload and download use the Dart clients below, in a process of
// their own. `startup` is the time from spawning the server to its first 200.
//
// Every row is printed as one JSON line with the server's peak RSS
// (VmHWM, the server process alone), the CPU seconds it used, and the
// one-minute load average when the row started, because this machine is
// shared.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const allEngines = [
  'shelf',
  'relic_io',
  'relic_native',
  'relic_native4',
  'dartvel',
  'dartvel4',
];
const allScenarios = [
  'plaintext',
  'json',
  'headers',
  'static',
  'many',
  'startup',
  'websocket',
  'websocket_pipelined',
  'upload',
  'download',
];
const transferBytes = 50 * 1024 * 1024;

/// What a browser sends, Cookie included: Relic's `headers` workload.
const browserHeaders = [
  'Host: localhost',
  'Connection: keep-alive',
  'Cache-Control: max-age=0',
  'sec-ch-ua: "Chromium";v="130", "Google Chrome";v="130"',
  'sec-ch-ua-mobile: ?0',
  'sec-ch-ua-platform: "macOS"',
  'Upgrade-Insecure-Requests: 1',
  'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,image/apng,*/*;q=0.8',
  'Sec-Fetch-Site: same-origin',
  'Sec-Fetch-Mode: navigate',
  'Sec-Fetch-User: ?1',
  'Sec-Fetch-Dest: document',
  'Referer: http://localhost/',
  'Accept-Encoding: gzip, deflate, br, zstd',
  'Accept-Language: en-US,en;q=0.9,da;q=0.8',
  'Cookie: session=0123456789abcdef0123456789abcdef0123456789abcdef; '
      '_ga=GA1.1.1234567890.1700000000; _gid=GA1.1.0987654321.1700000000; '
      'theme=dark; consent=analytics,marketing; '
      'tracker=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
];

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'client') {
    stdout.writeln(jsonEncode(await _client(int.parse(args[1]), args[2])));
    return;
  }
  final options = {
    for (final arg in args)
      if (arg.startsWith('--') && arg.contains('='))
        arg.substring(2, arg.indexOf('=')): arg.substring(arg.indexOf('=') + 1),
  };
  List<String> list(String name, List<String> all) =>
      options[name]?.split(',') ?? all;
  final engines = list('engines', allEngines);
  final scenarios = list('scenarios', allScenarios);
  final trials = int.parse(options['trials'] ?? '3');
  final seconds = int.parse(options['seconds'] ?? '5');
  final connections = int.parse(options['connections'] ?? '64');
  final many = int.parse(options['many'] ?? '1024');
  final serveBin = options['serve'] ?? 'build/benchmark/serve';
  final relicBin = options['relic'] ??
      'benchmark/relic/build/cli/linux_x64/bundle/bin/serve';
  final beforeBin = options['serve-before'];
  final beforeLibrary = options['before-library'];

  final staticDir = Directory.systemTemp.createTempSync('compare_static');
  File('${staticDir.path}/file-4k.txt')
      .writeAsBytesSync(List<int>.generate(4096, (i) => 0x61 + i % 26));
  try {
    for (var trial = 1; trial <= trials; trial++) {
      for (final scenario in scenarios) {
        for (final engine in engines) {
          final row = await _measure(
            engine: engine,
            scenario: scenario,
            command: engine == 'dartvel_before'
                ? [beforeBin!, 'dartvel', staticDir.path]
                : _command(engine, serveBin, relicBin, staticDir.path),
            environment: {
              if (engine == 'dartvel_before' && beforeLibrary != null)
                'DARTVEL_SHELF_LIBRARY': beforeLibrary,
            },
            seconds: seconds,
            connections: scenario == 'many' ? many : connections,
          );
          stdout.writeln(jsonEncode({'trial': trial, ...row}));
        }
      }
    }
  } finally {
    staticDir.deleteSync(recursive: true);
  }
}

List<String> _command(
  String engine,
  String serveBin,
  String relicBin,
  String staticDir,
) =>
    switch (engine) {
      'shelf' || 'dartvel' => [serveBin, engine, staticDir],
      'relic_io' => [relicBin, 'io', '1', staticDir],
      'relic_native' => [relicBin, 'native', '1', staticDir],
      'relic_native4' => [relicBin, 'native', '4', staticDir],
      'dartvel4' => [serveBin, 'dartvel4', staticDir],
      _ => throw ArgumentError.value(engine, 'engine'),
    };

Future<Map<String, Object?>> _measure({
  required String engine,
  required String scenario,
  required List<String> command,
  Map<String, String> environment = const {},
  required int seconds,
  required int connections,
}) async {
  final load = File('/proc/loadavg').readAsStringSync().split(' ').first;
  final spawned = Stopwatch()..start();
  final server = await Process.start(
    command.first,
    command.skip(1).toList(),
    environment: environment,
  );
  final stderrText = StringBuffer();
  server.stderr.transform(utf8.decoder).listen(stderrText.write);
  final lines = server.stdout.transform(utf8.decoder).transform(
        const LineSplitter(),
      );
  final ready = Completer<int>();
  lines.listen((line) {
    if (!ready.isCompleted && line.startsWith('ready ')) {
      ready.complete(int.parse(line.substring(6)));
    }
  });
  final int port;
  try {
    port = await ready.future.timeout(const Duration(seconds: 60));
  } on TimeoutException {
    server.kill();
    throw StateError('$engine never became ready: $stderrText');
  }
  final base = 'http://127.0.0.1:$port';
  final metrics = <String, Object?>{};
  try {
    // The first 200 ends startup.
    final probe = HttpClient();
    while (true) {
      try {
        final response =
            await (await probe.getUrl(Uri.parse('$base/plaintext'))).close();
        await response.drain<void>();
        if (response.statusCode == 200) break;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    probe.close(force: true);
    final startupMs = spawned.elapsedMicroseconds / 1000;
    final cpuBefore = _cpuSeconds(server.pid);
    switch (scenario) {
      case 'startup':
        metrics['startup_ms'] = startupMs;
      case 'plaintext' || 'json' || 'headers' || 'static' || 'many':
        final url = switch (scenario) {
          'json' => '$base/json',
          'static' => '$base/static/file-4k.txt',
          _ => '$base/plaintext',
        };
        final headers = scenario == 'headers' ? browserHeaders : <String>[];
        await _oha(url, connections, 2, headers);
        final run = await _oha(url, connections, seconds, headers);
        metrics.addAll(run);
        final cpu = _cpuSeconds(server.pid) - cpuBefore;
        final requests = run['requests'] as int;
        if (requests > 0) metrics['cpu_us_per_req'] = cpu * 1e6 / requests;
      case 'websocket' || 'websocket_pipelined' || 'upload' || 'download':
        final kind = scenario == 'websocket' ? 'pingpong' : scenario;
        final result = await Process.run(Platform.resolvedExecutable, [
          if (_underDartVm) Platform.script.toFilePath(),
          'client',
          '$port',
          kind == 'websocket_pipelined' ? 'pipelined' : kind,
        ]);
        if (result.exitCode != 0) {
          throw StateError('client failed: ${result.stderr}');
        }
        metrics.addAll(
          (jsonDecode((result.stdout as String).trim()) as Map)
              .cast<String, Object?>(),
        );
      default:
        throw ArgumentError.value(scenario, 'scenario');
    }
    metrics['server_cpu_s'] = _cpuSeconds(server.pid) - cpuBefore;
    metrics['peak_rss_mib'] = _peakRssMib(server.pid);
  } finally {
    server.kill(ProcessSignal.sigterm);
    final exited = await server.exitCode
        .timeout(const Duration(seconds: 10), onTimeout: () {
      server.kill(ProcessSignal.sigkill);
      return -9;
    });
    if (exited == -9) metrics['killed'] = true;
  }
  return {
    'engine': engine,
    'scenario': scenario,
    'load1': double.parse(load),
    ...metrics,
  };
}

bool get _underDartVm => ['dart', 'dartvm', 'dart.exe']
    .contains(Platform.resolvedExecutable.split(Platform.pathSeparator).last);

/// User plus system CPU seconds of [pid] and its threads.
double _cpuSeconds(int pid) {
  final stat = File('/proc/$pid/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  // utime and stime are fields 14 and 15; the slice starts at field 3.
  return (int.parse(fields[11]) + int.parse(fields[12])) / 100;
}

/// Peak resident set of [pid], the server alone.
double _peakRssMib(int pid) {
  final line = File('/proc/$pid/status')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('VmHWM:'));
  return int.parse(line.split(RegExp(r'\s+'))[1]) / 1024;
}

Future<Map<String, Object?>> _oha(
  String url,
  int connections,
  int seconds,
  List<String> headers,
) async {
  final result = await Process.run('oha', [
    '--no-tui',
    '--output-format',
    'json',
    '-c',
    '$connections',
    '-z',
    '${seconds}s',
    for (final header in headers) ...['-H', header],
    url,
  ]);
  if (result.exitCode != 0) throw StateError('oha: ${result.stderr}');
  final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final summary = json['summary'] as Map<String, dynamic>;
  final percentiles = json['latencyPercentiles'] as Map<String, dynamic>;
  final statuses = (json['statusCodeDistribution'] as Map<String, dynamic>)
      .cast<String, int>();
  final errors = (json['errorDistribution'] as Map<String, dynamic>)
      .cast<String, int>();
  double? ms(String key) =>
      percentiles[key] == null ? null : (percentiles[key] as num) * 1000;
  final ok = statuses['200'] ?? 0;
  final all = statuses.values.fold<int>(0, (a, b) => a + b);
  return {
    'requests': all,
    'rps': summary['requestsPerSec'],
    'p50_ms': ms('p50'),
    'p99_ms': ms('p99'),
    'p99_9_ms': ms('p99.9'),
    if (all != ok) 'non_200': all - ok,
    // oha cuts the requests in flight at the deadline; those are not
    // the server's errors.
    if (errors.keys.any((k) => !k.contains('deadline')))
      'errors': {
        for (final entry in errors.entries)
          if (!entry.key.contains('deadline')) entry.key: entry.value,
      },
  };
}

/// A peer in its own process.
///
/// `pingpong` sends one 64-byte text message and waits for its echo before
/// the next, through dart:io's client. `pipelined` writes pre-encoded frames
/// from a raw socket without waiting and counts the echoes, so the server is
/// measured rather than a client that encodes each frame in Dart. `upload`
/// and `download` move 50 MiB through dart:io's HttpClient.
Future<Map<String, Object>> _client(int port, String kind) async {
  if (kind == 'upload' || kind == 'download') {
    final client = HttpClient();
    final watch = Stopwatch()..start();
    if (kind == 'upload') {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/upload'));
      request.contentLength = transferBytes;
      final chunk = Uint8List(64 * 1024);
      for (var sent = 0; sent < transferBytes; sent += chunk.length) {
        request.add(chunk);
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (text != '$transferBytes') {
        throw StateError('Upload received $text bytes');
      }
    } else {
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/download')))
          .close();
      final bytes = await response.fold<int>(0, (n, c) => n + c.length);
      if (bytes != transferBytes) {
        throw StateError('Download received $bytes bytes');
      }
    }
    watch.stop();
    client.close(force: true);
    return {'mib_per_second': 50 * 1e6 / watch.elapsedMicroseconds};
  }
  if (kind == 'pingpong') {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final messages = StreamIterator<Object?>(ws);
    final message = 'x' * 64;
    Future<int> echo(Stopwatch clock) async {
      final sent = clock.elapsedMicroseconds;
      ws.add(message);
      if (!await messages.moveNext() || messages.current != message) {
        throw StateError('Echo mismatch');
      }
      return clock.elapsedMicroseconds - sent;
    }

    final clock = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await echo(clock);
    }
    const count = 2000;
    final latencies = <int>[];
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      latencies.add(await echo(clock));
    }
    watch.stop();
    latencies.sort();
    await ws.close();
    await messages.cancel();
    return {
      'messages_per_second': count * 1000000 / watch.elapsedMicroseconds,
      'p50_us': latencies[count ~/ 2],
      'p99_us': latencies[count * 99 ~/ 100],
    };
  }
  const count = 200000;
  const frameBytes = 6 + 64; // masked client frame
  const echoBytes = 2 + 64; // unmasked server frame
  final socket = await Socket.connect('127.0.0.1', port);
  socket.setOption(SocketOption.tcpNoDelay, true);
  socket.write(
    'GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\n'
    'Upgrade: websocket\r\nConnection: Upgrade\r\n'
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
    'Sec-WebSocket-Version: 13\r\n\r\n',
  );
  // FIN + text, MASK + length 64, an all-zero masking key, then the payload.
  final frame = [0x81, 0x80 | 64, 0, 0, 0, 0, ...List.filled(64, 0x78)];
  const perWrite = 1000;
  final chunk = Uint8List(frame.length * perWrite);
  for (var i = 0; i < perWrite; i++) {
    chunk.setRange(i * frameBytes, (i + 1) * frameBytes, frame);
  }
  final header = <int>[];
  var upgraded = false;
  var received = 0;
  final done = Completer<void>();
  final watch = Stopwatch();
  final subscription = socket.listen(
    (data) {
      if (!upgraded) {
        header.addAll(data);
        final text = latin1.decode(header);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        if (!text.startsWith('HTTP/1.1 101')) {
          done.completeError(StateError('Upgrade refused: $text'));
          return;
        }
        upgraded = true;
        received = header.length - (end + 4);
        watch.start();
        for (var i = 0; i < count ~/ perWrite; i++) {
          socket.add(chunk);
        }
      } else {
        received += data.length;
      }
      if (received >= count * echoBytes && !done.isCompleted) done.complete();
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(StateError('Closed early'));
    },
  );
  await done.future.timeout(const Duration(seconds: 120));
  watch.stop();
  await subscription.cancel();
  socket.destroy();
  return {'messages_per_second': count * 1000000 / watch.elapsedMicroseconds};
}
