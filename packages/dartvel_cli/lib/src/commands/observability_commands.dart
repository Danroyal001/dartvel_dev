// `dartvel logs`, `dartvel traces` and `dartvel metrics`.
//
// These used to print hardcoded sample output -- a fixed trace id, "CPU
// Usage: 1.2%", "Backend server started successfully" -- whether or not
// anything was running. A number that looks like a real measurement and
// isn't is worse than the command not existing, because nothing about it
// looks fake.
//
// `metrics` reads the real thing: every Dartvel server answers GET /metrics
// with its actual Prometheus registry (see
// packages/dartvel_core/lib/src/http/router.dart and
// packages/dartvel_core/lib/src/observability/metrics.dart). This command
// fetches it and prints exactly what came back, and says plainly when it
// could not -- no server listening, a non-metrics response, or a reachable
// server with nothing recorded yet.
//
// `logs` and `traces` have no real source to read. Nothing in the runtime
// writes application logs anywhere -- there is no sink, no file, no
// endpoint. Spans are captured (DVTracer, DVMemoryTraceExporter in
// packages/dartvel_core/lib/src/observability/tracing.dart) but only into an
// in-process list that nothing exports or serves, so a separate CLI process
// has no way to read them either. Both commands say that outright and exit
// non-zero rather than print anything that looks like data.
//
// Output goes to stdout unprefixed: a scrape target's Prometheus text has to
// stay parseable, and the other two commands should read the same way.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

class LogsCommand extends Command<void> {
  @override
  final String name = 'logs';
  @override
  final String description = 'Stream local or remote deployment runtime logs.';

  @override
  Future<void> run() async {
    _emit(
      'logs: not implemented. Nothing in the Dartvel runtime writes '
      'application or request logs anywhere this command could read them -- '
      'there is no log sink, no file, and no endpoint. This command needs a '
      'real log sink added to the runtime (alongside the metrics registry '
      'and health checks in packages/dartvel_core/lib/src/observability/) '
      'before it can show anything true.',
    );
    exitCode = 1;
  }
}

class TracesCommand extends Command<void> {
  @override
  final String name = 'traces';
  @override
  final String description =
      'Examine OpenTelemetry trace spans and operations.';

  @override
  Future<void> run() async {
    _emit(
      'traces: not implemented. Dartvel records spans in-process (DVTracer, '
      'DVMemoryTraceExporter in '
      'packages/dartvel_core/lib/src/observability/tracing.dart), but '
      'nothing exports or serves them -- there is no endpoint this command '
      'can query and no file the spans are written to. It needs a trace '
      'export path added to the runtime before it can show a real span.',
    );
    exitCode = 1;
  }
}

class MetricsCommand extends Command<void> {
  @override
  final String name = 'metrics';
  @override
  final String description =
      'Fetch the /metrics endpoint of a running Dartvel server.';

  MetricsCommand() {
    argParser.addOption(
      'url',
      defaultsTo: 'http://localhost:8080',
      help: 'Base URL of the running Dartvel server to read /metrics from.',
    );
  }

  @override
  Future<void> run() async {
    final String base = (argResults!['url'] as String).trim();
    final Uri target = Uri.parse(base).resolve('/metrics');
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .getUrl(target)
          .timeout(const Duration(seconds: 3));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        _emit(
          '$target responded with HTTP ${response.statusCode}, not the '
          'Prometheus text a Dartvel server serves at /metrics.',
        );
        exitCode = 1;
        return;
      }

      if (body.trim().isEmpty) {
        _emit('No metrics recorded at $target.');
        return;
      }

      _emit(body.trimRight());
    } on Object catch (error) {
      _emit(
        'Could not reach a Dartvel server at $target: $error. Start one '
        'with `dartvel dev`, or pass --url to point at a running instance.',
      );
      exitCode = 1;
    } finally {
      client.close(force: true);
    }
  }
}

// ignore: avoid_print
void _emit(String line) => print(line);
