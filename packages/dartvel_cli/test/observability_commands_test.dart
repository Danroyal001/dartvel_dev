// `dartvel logs`, `dartvel traces` and `dartvel metrics` used to print
// hardcoded sample output -- a fixed trace id, "CPU Usage: 1.2%", "Backend
// server started successfully" -- regardless of whether anything was
// running. A developer running any of them saw numbers that looked like
// their application's and were fiction.
//
// `metrics` now reads the real `/metrics` endpoint a Dartvel server exposes
// (packages/dartvel_core/lib/src/http/router.dart) and reports truthfully
// when it cannot: no server, no data, or something that is not a Dartvel
// server. `logs` and `traces` have no real source to read at all -- there is
// no log sink anywhere in the runtime, and spans are exported only into an
// in-process list nothing serves -- so both say that plainly and exit
// non-zero instead of inventing anything.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/observability_commands.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

Future<String> runObservability(List<String> args) async {
  final StringBuffer out = StringBuffer();
  await runZoned(
    () async {
      final CommandRunner<void> runner =
          CommandRunner<void>('dartvel', 'Test runner')
            ..addCommand(LogsCommand())
            ..addCommand(TracesCommand())
            ..addCommand(MetricsCommand());
      await runner.run(args);
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone _, ZoneDelegate __, Zone ___, String line) =>
          out.writeln(line),
    ),
  );
  return out.toString();
}

void main() {
  setUp(() => exitCode = 0);
  tearDown(() => exitCode = 0);

  group('LogsCommand', () {
    test(
      'says plainly that there is nowhere to read logs from, instead of inventing lines',
      () async {
        final String output = await runObservability(<String>['logs']);

        expect(output, isNot(contains('Backend server started successfully')));
        expect(output, isNot(contains('Database connection established')));
        expect(output.toLowerCase(), contains('no'));
        expect(exitCode, isNot(0));
      },
    );
  });

  group('TracesCommand', () {
    test(
      'says plainly that nothing exports spans, instead of inventing a trace',
      () async {
        final String output = await runObservability(<String>['traces']);

        expect(output, isNot(contains('4bf92f3577b34da6a3ce929d0e0e4736')));
        expect(output, isNot(contains('Spans captured: 12')));
        expect(exitCode, isNot(0));
      },
    );
  });

  group('MetricsCommand', () {
    late HttpServer server;
    late String base;

    tearDown(() async {
      await server.close(force: true);
    });

    test(
      'prints the real Prometheus text a running server exposes at /metrics',
      () async {
        const String body =
            '# HELP dartvel_uptime_seconds Seconds since this process started.\n'
            '# TYPE dartvel_uptime_seconds gauge\n'
            'dartvel_uptime_seconds 42\n';
        server = await shelf_io.serve(
          (shelf.Request request) => shelf.Response.ok(
            body,
            headers: <String, String>{'content-type': 'text/plain'},
          ),
          InternetAddress.loopbackIPv4,
          0,
        );
        base = 'http://${server.address.host}:${server.port}';

        final String output = await runObservability(<String>[
          'metrics',
          '--url',
          base,
        ]);

        expect(output, contains('dartvel_uptime_seconds 42'));
        expect(output, isNot(contains('CPU Usage: 1.2%')));
        expect(output, isNot(contains('Active WebSocket connections: 0')));
        expect(exitCode, 0);
      },
    );

    test(
      'reports truthfully when the server has recorded nothing, rather than inventing a value',
      () async {
        server = await shelf_io.serve(
          (shelf.Request request) => shelf.Response.ok(''),
          InternetAddress.loopbackIPv4,
          0,
        );
        base = 'http://${server.address.host}:${server.port}';

        final String output = await runObservability(<String>[
          'metrics',
          '--url',
          base,
        ]);

        expect(output.toLowerCase(), contains('no'));
        expect(output, isNot(contains('CPU Usage')));
      },
    );

    test(
      'fails honestly instead of printing anything when no server is listening',
      () async {
        server = await shelf_io.serve(
          (shelf.Request request) => shelf.Response.ok(''),
          InternetAddress.loopbackIPv4,
          0,
        );
        base = 'http://${server.address.host}:${server.port}';
        await server.close(force: true);

        final String output = await runObservability(<String>[
          'metrics',
          '--url',
          base,
        ]);

        expect(output, isNot(contains('CPU Usage')));
        expect(output, isNot(contains('Memory Allocation')));
        expect(exitCode, isNot(0));
      },
    );
  });
}
