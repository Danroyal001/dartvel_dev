// `dartvel logs`, `dartvel traces` and `dartvel metrics` used to print
// hardcoded sample output -- a fixed trace id, "CPU Usage: 1.2%", "Backend
// server started successfully" -- regardless of whether anything was
// running. A developer running any of them saw numbers that looked like
// their application's and were fiction.
//
// All three now read a running server. `metrics` fetches GET /metrics;
// `logs` and `traces` fetch GET /_dartvel/logs and GET /_dartvel/traces,
// which serve the runtime's recent records and finished spans as NDJSON
// (packages/dartvel_core/lib/src/http/router.dart). Those two endpoints are
// off unless the server was started with DARTVEL_DIAGNOSTICS set, so the
// commands have to tell a developer that in the one case they will actually
// hit -- a 404 from a server that is otherwise working fine.
import 'dart:async';
import 'dart:convert';
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

/// A server that answers [path] with [body] and 404s everything else, plus
/// the requests it received so a test can check what the command asked for.
class FakeServer {
  FakeServer(this.server, this.requests);

  static Future<FakeServer> serving(
    String path,
    String body, {
    int status = 200,
    String contentType = 'application/x-ndjson',
  }) async {
    final List<shelf.Request> seen = <shelf.Request>[];
    final HttpServer server = await shelf_io.serve(
      (shelf.Request request) {
        seen.add(request);
        if ('/${request.url.path}' != path) {
          return shelf.Response.notFound('Not Found');
        }
        return shelf.Response(
          status,
          body: body,
          headers: <String, String>{'content-type': contentType},
        );
      },
      InternetAddress.loopbackIPv4,
      0,
    );
    return FakeServer(server, seen);
  }

  final HttpServer server;
  final List<shelf.Request> requests;

  String get base => 'http://${server.address.host}:${server.port}';

  Future<void> close() => server.close(force: true);
}

String logLine(String message, {String level = 'info', String? traceId}) =>
    jsonEncode(<String, Object?>{
      'time': '2026-01-02T03:04:05.000Z',
      'level': level,
      'message': message,
      if (traceId != null) 'traceId': traceId,
    });

void main() {
  setUp(() => exitCode = 0);
  tearDown(() => exitCode = 0);

  group('LogsCommand', () {
    late FakeServer fake;

    tearDown(() => fake.close());

    test('prints the records a running server is holding', () async {
      fake = await FakeServer.serving(
        '/_dartvel/logs',
        <String>[
          logLine('serving on 8080'),
          logLine('charge failed', level: 'error', traceId: 'a' * 32),
        ].join('\n'),
      );

      final String output =
          await runObservability(<String>['logs', '--url', fake.base]);

      expect(output, contains('serving on 8080'));
      expect(output, contains('charge failed'));
      // Case is the renderer's business; that the level reached the terminal
      // at all is not.
      expect(output.toLowerCase(), contains('error'));
      // The correlation id has to survive to the terminal, because quoting it
      // into `dartvel traces` is the next thing anybody does.
      expect(output, contains('a' * 32));
      expect(exitCode, 0);
    });

    test('--json prints the record verbatim, for piping into jq', () async {
      fake = await FakeServer.serving(
        '/_dartvel/logs',
        logLine('serving on 8080'),
      );

      final String output = await runObservability(
          <String>['logs', '--url', fake.base, '--json']);

      final Map<String, Object?> decoded =
          jsonDecode(output.trim()) as Map<String, Object?>;
      expect(decoded['message'], 'serving on 8080');
    });

    test('asks the server for the tail it was told to show', () async {
      fake = await FakeServer.serving('/_dartvel/logs', logLine('one'));

      await runObservability(
          <String>['logs', '--url', fake.base, '--limit', '25']);

      expect(fake.requests.single.url.queryParameters['limit'], '25');
    });

    test('names the switch that turns the endpoint on when it is off',
        () async {
      // A working server with diagnostics off answers 404, and that is the
      // case a developer will actually hit. "Not found" on its own would send
      // them looking for a bug in their routes.
      fake = await FakeServer.serving('/somewhere-else', '');

      final String output =
          await runObservability(<String>['logs', '--url', fake.base]);

      expect(output, contains('DARTVEL_DIAGNOSTICS'));
      expect(exitCode, isNot(0));
    });

    test('says so plainly when the server has logged nothing yet', () async {
      fake = await FakeServer.serving('/_dartvel/logs', '');

      final String output =
          await runObservability(<String>['logs', '--url', fake.base]);

      expect(output.toLowerCase(), contains('no log records'));
      expect(output, isNot(contains('Backend server started successfully')));
    });

    test('fails honestly when nothing is listening', () async {
      fake = await FakeServer.serving('/_dartvel/logs', '');
      final String base = fake.base;
      await fake.close();

      final String output =
          await runObservability(<String>['logs', '--url', base]);

      expect(output, isNot(contains('Database connection established')));
      expect(exitCode, isNot(0));
    });
  });

  group('TracesCommand', () {
    late FakeServer fake;

    tearDown(() => fake.close());

    test('prints the spans a running server is holding', () async {
      fake = await FakeServer.serving(
        '/_dartvel/traces',
        jsonEncode(<String, Object?>{
          'name': 'GET /checkout',
          'traceId': 'b' * 32,
          'spanId': 'c' * 16,
          'durationMs': 12.5,
          'status': 'ok',
        }),
      );

      final String output =
          await runObservability(<String>['traces', '--url', fake.base]);

      expect(output, contains('GET /checkout'));
      expect(output, contains('b' * 32));
      expect(output, contains('12.5'));
      expect(exitCode, 0);
    });

    test('a failed span is not printed as though it succeeded', () async {
      fake = await FakeServer.serving(
        '/_dartvel/traces',
        jsonEncode(<String, Object?>{
          'name': 'POST /charge',
          'traceId': 'd' * 32,
          'spanId': 'e' * 16,
          'durationMs': 900,
          'status': 'error',
          'attributes': <String, Object?>{'error': 'gateway timeout'},
        }),
      );

      final String output =
          await runObservability(<String>['traces', '--url', fake.base]);

      expect(output, contains('error'));
      expect(output, contains('gateway timeout'));
    });

    test('names the switch that turns the endpoint on when it is off',
        () async {
      fake = await FakeServer.serving('/somewhere-else', '');

      final String output =
          await runObservability(<String>['traces', '--url', fake.base]);

      expect(output, contains('DARTVEL_DIAGNOSTICS'));
      expect(exitCode, isNot(0));
    });

    test('does not invent a trace when the server has recorded none',
        () async {
      fake = await FakeServer.serving('/_dartvel/traces', '');

      final String output =
          await runObservability(<String>['traces', '--url', fake.base]);

      expect(output, isNot(contains('4bf92f3577b34da6a3ce929d0e0e4736')));
      expect(output.toLowerCase(), contains('no spans'));
    });
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
