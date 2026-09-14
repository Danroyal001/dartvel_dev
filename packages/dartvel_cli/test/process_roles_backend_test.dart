// The generated backend as a web server, a queue worker and the schedules.
//
// dartvel infra renders units that start one binary under different
// environments, and until this the binary read none of them: it bound the
// port fixed at generation, ticked every schedule in every process and had
// no worker. So this generates a real backend the way `dartvel routes` does,
// starts it as a process under each environment a unit writes, and asserts on
// what the process did -- which port answered, whether the schedule ran,
// whether the job ran -- never on the generated text.
//
// The silent failures, each paired with the control that shows the assertion
// can fail: a bad DARTVEL_PORT that quietly binds the generated port; a
// worker that also serves the application or ticks the schedules; a declared
// web instance ticking the schedules its cron process already runs; and two
// cron processes firing one occurrence twice.
@Timeout(Duration(minutes: 15))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:roles_probe/backend/schedules.dart' as cron;
import 'package:roles_probe/dartvel_client/schedules.g.dart' as schedules;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

class Welcome {
  const Welcome(this.id);
  final String id;
}

/// A store two schedulers share, with compare-and-set.
class SharedStore implements DVAtomicCacheAdapter {
  final Set<String> keys = <String>{};
  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async =>
      keys.add(key);
}

Future<Object?> get(int port, String path) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);
  try {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
    };
  } on SocketException {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> env = Platform.environment;
  int jobsRun = 0;
  if (env['PROBE_QUEUE'] == 'configured') {
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    const DVQueues().register<Welcome>((Welcome job) async => jobsRun++);
    await const DVQueues().dispatch(const Welcome('ada'));
  }

  // Half a second before a minute boundary and running at real speed, so the
  // every-minute schedule comes due exactly once in the probe's window.
  final DateTime origin = DateTime.now();
  DateTime clock() => DateTime(2026, 9, 1, 2, 59, 59, 500)
      .add(DateTime.now().difference(origin));
  const Duration tick = Duration(milliseconds: 50);

  final Completer<void> stop = Completer<void>();
  Object? error;
  final String mode = env['PROBE_MODE'] ?? 'main';
  final Future<void> running;
  if (mode == 'main') {
    running = gen
        .dartvelMain(
          arguments,
          until: stop.future,
          scheduleClock: clock,
          scheduleTick: tick,
        )
        .catchError((Object e) => error = e);
  } else if (mode == 'start-backend') {
    // Future.sync: a refusal thrown before the server starts is reported
    // like one thrown after.
    running = Future<dynamic>.sync(
      () => gen.startBackend(host: '127.0.0.1', port: 0),
    ).then<void>((dynamic handle) async {
      await stop.future;
      await handle.stop();
    }).catchError((Object e) => error = e);
  } else {
    // cron-pair / cron-pair-unguarded: two schedulers as two processes.
    final SharedStore store = SharedStore();
    final List<Timer?> timers = <Timer?>[
      for (int i = 0; i < 2; i++)
        schedules.dartvelStartBackendSchedules(
          every: tick,
          clock: clock,
          lease: mode == 'cron-pair' ? DVCacheScheduleLease(store) : null,
        ),
    ];
    running = stop.future.then((_) {
      for (final Timer? t in timers) {
        t?.cancel();
      }
    });
  }

  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final Map<String, Object?> ports = <String, Object?>{};
  for (final String port in (env['PROBE_PORTS'] ?? '').split(',')) {
    if (port.isEmpty) continue;
    ports[port] = await get(int.parse(port), '/api/ping');
  }
  if (!stop.isCompleted) stop.complete();
  await running.timeout(const Duration(seconds: 10));

  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'cronRuns': cron.cronRuns,
    'jobsRun': jobsRun,
    'ports': ports,
    'error': error?.toString(),
  })}');
  exit(0);
}
''';

Future<int> freePort() async {
  final ServerSocket socket = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late Directory project;
  late int generatedPort;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    generatedPort = await freePort();

    project = Directory.systemTemp.createTempSync('dv_process_roles_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: roles_probe
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
  backendPort: $generatedPort
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

@DVBackendFunction()
Future<String> _ping() async => 'pong';
''');
    write('lib/backend/schedules.dart', '''
import 'package:dartvel_core/dartvel.dart';

int cronRuns = 0;

@DVBackendCron('* * * * *')
Future<void> everyMinute() async {
  cronRuns++;
}
''');
    write('bin/probe.dart', _probe);

    final Directory previous = Directory.current;
    Directory.current = project;
    try {
      await routes.generate();
    } finally {
      Directory.current = previous;
    }
    // The schedule has to have been found, or every count below is 0 for the
    // wrong reason.
    expect(
      File(
        p.join(project.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      ).readAsStringSync(),
      contains('everyMinute'),
    );

    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, String> inherited() => <String, String>{
    for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
      if (Platform.environment[key] != null) key: Platform.environment[key]!,
  };

  Future<ProcessResult> probe(
    Map<String, String> environment, {
    List<String> arguments = const <String>[],
    List<int> ports = const <int>[],
  }) {
    return Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart', ...arguments],
      workingDirectory: project.path,
      // Nothing of the runner's own: a DARTVEL_ROLE exported in the shell
      // running the suite would decide the answer.
      includeParentEnvironment: false,
      environment: <String, String>{
        ...inherited(),
        'PROBE_PORTS': <int>[generatedPort, ...ports].join(','),
        ...environment,
      },
    ).timeout(const Duration(minutes: 3));
  }

  Map<String, Object?> report(ProcessResult result) {
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail(
        'the probe did not run (exit ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  Object? answered(Map<String, Object?> r, int port) =>
      (r['ports']! as Map<String, Object?>)['$port'];

  const Map<String, Object?> pong = <String, Object?>{
    'status': 200,
    'body': 'pong',
  };

  group('port', () {
    test(
      'DARTVEL_PORT is the port served, and the generated one is not',
      () async {
        final int port = await freePort();
        final Map<String, Object?> r = report(
          await probe(
            <String, String>{'DARTVEL_PORT': '$port'},
            ports: <int>[port],
          ),
        );
        expect(r['error'], isNull);
        expect(answered(r, port), pong);
        expect(answered(r, generatedPort), isNull);
      },
    );

    test('with no DARTVEL_PORT the generated port is served', () async {
      final Map<String, Object?> r = report(
        await probe(const <String, String>{}),
      );
      expect(r['error'], isNull);
      expect(answered(r, generatedPort), pong);
    });

    for (final String bad in <String>['abc', '', '70000', '0']) {
      test('DARTVEL_PORT="$bad" refuses to start, serving nothing', () async {
        final Map<String, Object?> r = report(
          await probe(<String, String>{'DARTVEL_PORT': bad}),
        );
        expect(r['error'], contains('DARTVEL_PORT'));
        // Not the generated port instead: that is the silent fallback.
        expect(answered(r, generatedPort), isNull);
        expect(r['cronRuns'], 0);
      });
    }
  });

  group('roles', () {
    test('a process given no role serves and ticks the schedules', () async {
      final Map<String, Object?> r = report(
        await probe(const <String, String>{'PROBE_QUEUE': 'configured'}),
      );
      expect(r['error'], isNull);
      expect(answered(r, generatedPort), pong);
      expect(r['cronRuns'], 1);
      // Serving is not working: the job waits for a worker.
      expect(r['jobsRun'], 0);
    });

    test(
      'a declared web process serves and leaves the schedules to cron',
      () async {
        final Map<String, Object?> r = report(
          await probe(const <String, String>{'DARTVEL_ROLE': 'web'}),
        );
        expect(r['error'], isNull);
        expect(answered(r, generatedPort), pong);
        expect(r['cronRuns'], 0);
      },
    );

    test(
      'a worker works its queue, serves nothing and ticks nothing',
      () async {
        final int port = await freePort();
        final Map<String, Object?> r = report(
          await probe(
            <String, String>{
              'DARTVEL_ROLE': 'worker',
              'DARTVEL_PORT': '$port',
              'PROBE_QUEUE': 'configured',
            },
            ports: <int>[port],
          ),
        );
        expect(r['error'], isNull);
        expect(r['jobsRun'], 1);
        expect(answered(r, generatedPort), isNull);
        expect(answered(r, port), isNull);
        expect(r['cronRuns'], 0);
      },
    );

    test('--role=worker selects it as well', () async {
      final Map<String, Object?> r = report(
        await probe(
          const <String, String>{'PROBE_QUEUE': 'configured'},
          arguments: <String>['--role=worker'],
        ),
      );
      expect(r['error'], isNull);
      expect(r['jobsRun'], 1);
      expect(answered(r, generatedPort), isNull);
    });

    test(
      'a worker with no queue adapter configured refuses to start',
      () async {
        final Map<String, Object?> r = report(
          await probe(const <String, String>{'DARTVEL_ROLE': 'worker'}),
        );
        expect(r['error'], contains('no queue adapter'));
      },
    );

    test(
      'cron ticks the schedules, serves nothing and works nothing',
      () async {
        final Map<String, Object?> r = report(
          await probe(const <String, String>{
            'DARTVEL_ROLE': 'cron',
            'PROBE_QUEUE': 'configured',
          }),
        );
        expect(r['error'], isNull);
        expect(r['cronRuns'], 1);
        expect(r['jobsRun'], 0);
        expect(answered(r, generatedPort), isNull);
      },
    );

    test('an unknown role refuses to start', () async {
      final Map<String, Object?> r = report(
        await probe(const <String, String>{'DARTVEL_ROLE': 'backend'}),
      );
      expect(r['error'], contains('web, worker, cron'));
      expect(answered(r, generatedPort), isNull);
      expect(r['cronRuns'], 0);
    });

    test('startBackend in a worker process refuses to serve', () async {
      final Map<String, Object?> r = report(
        await probe(const <String, String>{
          'DARTVEL_ROLE': 'worker',
          'PROBE_MODE': 'start-backend',
        }),
      );
      expect(r['error'], contains('DARTVEL_ROLE=worker'));
      expect(r['cronRuns'], 0);
    });
  });

  group('two cron processes', () {
    test('without a lease each fires the occurrence', () async {
      // The control for the test below.
      final Map<String, Object?> r = report(
        await probe(const <String, String>{
          'PROBE_MODE': 'cron-pair-unguarded',
        }),
      );
      expect(r['cronRuns'], 2);
    });

    test('sharing a lease they fire it once', () async {
      final Map<String, Object?> r = report(
        await probe(const <String, String>{'PROBE_MODE': 'cron-pair'}),
      );
      expect(r['cronRuns'], 1);
    });
  });

  group('the generated entry point', () {
    Future<(int, String)> runEntryPoint(
      Map<String, String> environment, {
      Future<void> Function()? whileRunning,
    }) async {
      final Process process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', '.dart_tool/dartvel_server.dart'],
        workingDirectory: project.path,
        includeParentEnvironment: false,
        environment: <String, String>{...inherited(), ...environment},
      );
      final StringBuffer output = StringBuffer();
      final Completer<void> listening = Completer<void>();
      process.stdout.transform(utf8.decoder).listen((String s) {
        output.write(s);
        if (s.contains('listening') && !listening.isCompleted) {
          listening.complete();
        }
      });
      process.stderr.transform(utf8.decoder).listen(output.write);
      if (whileRunning != null) {
        await Future.any(<Future<void>>[
          listening.future,
          process.exitCode,
        ]).timeout(const Duration(minutes: 3));
        await whileRunning();
        process.kill();
      }
      final int code = await process.exitCode.timeout(
        const Duration(minutes: 3),
      );
      return (code, output.toString());
    }

    test('serves on DARTVEL_PORT', () async {
      final int port = await freePort();
      Object? body;
      final (int _, String output) = await runEntryPoint(
        <String, String>{'DARTVEL_PORT': '$port'},
        whileRunning: () async {
          final HttpClient client = HttpClient();
          try {
            final request = await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/api/ping'),
            );
            body = await (await request.close()).transform(utf8.decoder).join();
          } finally {
            client.close(force: true);
          }
        },
      );
      expect(body, 'pong', reason: output);
    });

    test('exits non-zero on a bad DARTVEL_PORT, naming it', () async {
      final (int code, String output) = await runEntryPoint(
        const <String, String>{'DARTVEL_PORT': 'http'},
      );
      expect(code, isNot(0), reason: output);
      expect(output, contains('DARTVEL_PORT'));
      expect(output, isNot(contains('listening')));
    });
  });
}
