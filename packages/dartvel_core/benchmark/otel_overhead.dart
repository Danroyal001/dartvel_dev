// What OpenTelemetry costs a Dartvel request.
//
//   dart run benchmark/otel_overhead.dart [requests]
//
// Serves the same request through the router -- the place every web-server
// request passes, and where the server span, the semantic metrics and the
// access line are recorded -- in four modes, in process, so the number is the
// instrumentation and not the network:
//
//   off       nothing reads spans; the default for a project that says nothing
//   traces    server and database spans, exported over OTLP
//   all       traces, metrics and logs, exported over OTLP
//   all+json  the same, encoded as OTLP/JSON
//
// The exporter's transport is replaced by one that counts bytes and answers
// 200 at once, so what is measured is recording, batching and encoding --
// everything Dartvel does -- and not a collector's speed. Each request runs a
// database query, so the trace has a child span as a real one would.
import 'dart:async';
import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/http.dart' show Router;
import 'package:dartvel_core/src/observability/observability.dart';

Future<void> main(List<String> arguments) async {
  final int requests = arguments.isEmpty ? 100000 : int.parse(arguments.first);
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  await db.execute('CREATE TABLE orders (id TEXT, total INTEGER)');
  await db.execute(
      'INSERT INTO orders (id, total) VALUES (?, ?)', <Object?>['o-1', 4200]);
  final Router router = Router()
    ..get('/orders/:id', (Request req) async {
      final List<Map<String, Object?>> rows = await db.query(
          'SELECT * FROM orders WHERE id = ?', <Object?>[req.params['id']]);
      return Response.text('${rows.length}');
    });
  // The access line goes to the in-memory buffer only, as it does in a test;
  // a real server also writes it to stdout, which is the same in every mode.
  DVObservability.resetLogging();

  int bytes = 0;
  int posts = 0;
  Future<DVOtlpResponse> send(
      Uri url, Map<String, String> headers, List<int> body) async {
    bytes += body.length;
    posts++;
    return const DVOtlpResponse(200);
  }

  final Map<String, DVOpenTelemetryConfig?> modes = <String, DVOpenTelemetryConfig?>{
    'off': null,
    'traces': const DVOpenTelemetryConfig(
        enabled: true, metrics: false, logs: false, serviceName: 'bench'),
    'all': const DVOpenTelemetryConfig(enabled: true, serviceName: 'bench'),
    'all+json': const DVOpenTelemetryConfig(
        enabled: true, serviceName: 'bench', protocol: DVOtlpProtocol.httpJson),
  };

  final Request request = Request(
    method: 'GET',
    url: Uri.parse('http://localhost/orders/o-1'),
    headers: Headers(),
    bodyStream: const Stream<List<int>>.empty(),
  );

  io.stdout.writeln('Dartvel OpenTelemetry overhead, $requests requests per mode, '
      'Dart ${io.Platform.version.split(' ').first}');
  io.stdout.writeln('');
  io.stdout.writeln('mode       us/request   requests/s   vs off   exported');
  double? baseline;
  for (final MapEntry<String, DVOpenTelemetryConfig?> mode in modes.entries) {
    await DVOpenTelemetry.shutdown();
    DVObservability.resetTracing();
    DVObservability.metrics.reset();
    bytes = 0;
    posts = 0;
    if (mode.value != null) {
      DVOpenTelemetry.install(mode.value!,
          environment: const <String, String>{}, send: send);
    }
    // Warm up: let the JIT see the instrumented path before it is timed.
    for (int i = 0; i < requests ~/ 10; i++) {
      await router(request);
    }
    final Stopwatch clock = Stopwatch()..start();
    for (int i = 0; i < requests; i++) {
      await router(request);
    }
    clock.stop();
    // What is still queued is exported too, and counted: deferring the cost
    // to after the timer would flatter the number.
    final Stopwatch flush = Stopwatch()..start();
    await DVOpenTelemetry.forceFlush();
    flush.stop();
    final double perRequest =
        (clock.elapsedMicroseconds + flush.elapsedMicroseconds) / requests;
    baseline ??= perRequest;
    io.stdout.writeln('${mode.key.padRight(10)} '
        '${perRequest.toStringAsFixed(2).padLeft(10)}   '
        '${(1000000 / perRequest).round().toString().padLeft(10)}   '
        '${(perRequest / baseline).toStringAsFixed(2).padLeft(5)}x   '
        '${mode.value == null ? '-' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB in $posts posts'}');
  }
  await DVOpenTelemetry.shutdown();
  io.exit(0);
}
