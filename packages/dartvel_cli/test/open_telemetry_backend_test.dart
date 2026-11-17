// dartvel.openTelemetry reaching the generated server.
//
// Zero code is the claim: a project writes a pubspec section, or a deployment
// sets OTEL_EXPORTER_OTLP_ENDPOINT, and a served request arrives at an OTLP
// collector as a span, a metric and a log line. So this generates a real
// backend the way `dartvel routes` does, starts it as a process, sends it a
// request, and reads what a collector -- an HttpServer here, decoding nothing
// but looking for the bytes a real one would index on -- was sent.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' as core;
import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  Object? error;
  String? traceparent;
  try {
    final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
    final HttpClient client = HttpClient();
    try {
      final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${handle.port}/api/ping'));
      final response = await request.close();
      traceparent = response.headers.value('traceparent');
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    await core.DVOpenTelemetry.forceFlush();
    await handle.stop();
  } catch (e) {
    error = e;
  }
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'error': error?.toString(),
    'traceparent': traceparent,
  })}');
  exit(0);
}
''';

void main() {
  late Directory project;
  late String packages;
  late HttpServer collector;
  final Map<String, List<List<int>>> received = <String, List<List<int>>>{};

  Future<ProcessResult> generate(Directory root) {
    final String cliPackage = p.join(packages, 'dartvel_cli');
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: root.path,
    );
  }

  Directory scaffold() {
    final Directory root = Directory.systemTemp.createTempSync('dv_otel_');
    void write(String relative, String content) {
      final File file = File(p.join(root.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: otel_probe
version: 2.3.4
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
  openTelemetry:
    enabled: true
    # Unreachable on purpose: the deployment's OTEL_EXPORTER_OTLP_ENDPOINT
    # has to win over it for anything to arrive.
    endpoint: http://127.0.0.1:9
    serviceName: probe-shop
    scheduleDelayMs: 20
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

@DVBackendFunction()
Future<String> _ping() async {
  DV.ObservabilityAndLogging.log('ping answered', context: <String, Object?>{'probe': true});
  return 'pong';
}
''');
    write('bin/probe.dart', _probe);
    return root;
  }

  setUpAll(() async {
    collector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    collector.listen((HttpRequest request) async {
      final List<int> body = <int>[
        for (final List<int> chunk in await request.toList()) ...chunk,
      ];
      received.putIfAbsent(request.uri.path, () => <List<int>>[]).add(body);
      request.response.statusCode = 200;
      await request.response.close();
    });
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    project = scaffold();
    final ProcessResult generated = await generate(project);
    if (generated.exitCode != 0) {
      throw StateError(
        'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}',
      );
    }
    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() async {
    await collector.close(force: true);
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  setUp(received.clear);

  Future<Map<String, Object?>> run(Map<String, String> environment) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
        ...environment,
      },
    ).timeout(const Duration(minutes: 3));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    final Map<String, Object?> r =
        jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    expect(r['error'], isNull);
    return r;
  }

  bool sent(String path, String text) => (received[path] ?? const <List<int>>[])
      .any((List<int> body) => latin1.decode(body).contains(text));

  test('a served request reaches the collector as a span, a log line and '
      'metrics, with no code: the pubspec section and one variable', () async {
    final Map<String, Object?> r = await run(<String, String>{
      'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://127.0.0.1:${collector.port}',
    });

    expect(received.keys,
        containsAll(<String>['/v1/traces', '/v1/logs', '/v1/metrics']));
    expect(sent('/v1/traces', 'probe-shop'), isTrue,
        reason: 'service.name from the pubspec section');
    expect(sent('/v1/traces', '2.3.4'), isTrue,
        reason: 'service.version defaults to the pubspec version');
    expect(sent('/v1/traces', '/api/ping'), isTrue,
        reason: 'the route the request matched');
    expect(sent('/v1/logs', 'ping answered'), isTrue,
        reason: 'the backend function\'s log line');
    expect(sent('/v1/metrics', 'http.server.request.duration'), isTrue);

    // The trace the response names is the trace the collector was sent.
    final String traceparent = r['traceparent']! as String;
    final String traceId = traceparent.split('-')[1];
    final List<int> idBytes = <int>[
      for (int i = 0; i < 32; i += 2) int.parse(traceId.substring(i, i + 2), radix: 16),
    ];
    expect(sent('/v1/traces', latin1.decode(idBytes)), isTrue);
  });

  test('OTEL_SERVICE_NAME and the JSON protocol are honoured', () async {
    await run(<String, String>{
      'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://127.0.0.1:${collector.port}',
      'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/json',
      'OTEL_SERVICE_NAME': 'renamed-at-deploy',
    });
    final String body = utf8.decode(received['/v1/traces']!.first);
    final Map<String, Object?> json = jsonDecode(body) as Map<String, Object?>;
    expect(json['resourceSpans'], isNotEmpty);
    expect(body, contains('renamed-at-deploy'));
  });

  test('OTEL_SDK_DISABLED sends nothing', () async {
    await run(<String, String>{
      'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://127.0.0.1:${collector.port}',
      'OTEL_SDK_DISABLED': 'true',
    });
    expect(received, isEmpty);
  });
}
