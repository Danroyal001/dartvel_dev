// A generated backend's worker runs the application's @DVJob handlers, and
// its cron processes fire a schedule once between them.
//
// Until this the generated entry point registered no handler and no queue
// adapter -- jobs.g.dart imported dartvel_flutter, which a server cannot load
// -- so a DARTVEL_ROLE=worker process refused to start, and nothing gave the
// cron processes a lease, so each fired every schedule. These generate a real
// project with an @DVJob, a handler and a schedule, and run it as separate
// processes sharing one SQLite database, asserting on what happened in that
// database rather than on the generated text.
//
// The silent failures, each with the control that shows the assertion can
// fail: a web process whose job never reaches the worker; two cron processes
// each firing the occurrence; a declared cron process with no shared store
// starting anyway; and a health port that answers the application.
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:jobs_probe/backend/schedules.dart' as cron;
import 'package:jobs_probe/dartvel_client/jobs.g.dart' as jobs;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  final Map<String, String> env = Platform.environment;
  final Completer<void> stop = Completer<void>();
  Object? error;
  final Map<String, Object?> report = <String, Object?>{};

  if (env['PROBE_MODE'] == 'dispatch') {
    // A web process as the generated entry point starts one, dispatching
    // the way a backend function does.
    final Future<void> running = gen
        .dartvelMain(arguments, until: stop.future)
        .catchError((Object e) => error = e);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (error == null) {
      await jobs.Welcome(id: env['PROBE_JOB_ID']!).dispatch();
    }
    report['queueShared'] = const DVQueues().adapterConfigured;
    stop.complete();
    await running.timeout(const Duration(seconds: 10));
  } else {
    // Half a second before a minute boundary from the moment the scheduler
    // first reads the clock, then real speed, so the every-minute schedule
    // comes due exactly once in each process however long its startup took.
    // Counted from process start instead, a start slower than half a second
    // put the scheduler past the boundary and that process fired nothing --
    // so "once between two processes" passed with no lease at all.
    DateTime? first;
    DateTime clock() {
      final DateTime now = DateTime.now();
      first ??= now;
      return DateTime(2026, 9, 1, 2, 59, 59, 500).add(now.difference(first!));
    }
    final Future<void> running = gen
        .dartvelMain(
          arguments,
          until: stop.future,
          scheduleClock: clock,
          scheduleTick: const Duration(milliseconds: 50),
        )
        .catchError((Object e) => error = e);
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (error == null &&
        DateTime.now().isBefore(deadline) &&
        (first == null ||
            DateTime.now().difference(first!) <
                const Duration(milliseconds: 1500))) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    report['clockRead'] = first != null;
    if (!stop.isCompleted) stop.complete();
    await running.timeout(const Duration(seconds: 10));
    report['cronRuns'] = cron.cronRuns;
  }

  report['error'] = error?.toString();
  stdout.writeln('PROBE ${jsonEncode(report)}');
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
  late String packages;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );

    project = Directory.systemTemp.createTempSync('dv_worker_jobs_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: jobs_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
  backendPort: ${await freePort()}
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
    // Written the way application code is told to write it: through the
    // generated barrel, which exports Flutter. The handler needs nothing its
    // file declares, so the server never compiles the file.
    write('lib/jobs/welcome.dart', '''
import 'package:jobs_probe/dartvel_client/dartvel_client.dart';

@DVJob()
class _Welcome {
  final String id;

  const _Welcome({required this.id});
}

@DVJob.handler()
Future<void> _handleWelcome(Welcome job) async {
  // Its own connection: outside a preview the generated backend leaves
  // DV.Database for the application to configure.
  final DVDatabaseAdapter db = DVDatabaseConnection.parse(
    const DVSecrets().get('DATABASE_URL'),
  ).open();
  await db.execute(
    'CREATE TABLE IF NOT EXISTS welcome_runs (id TEXT NOT NULL)',
  );
  await db.execute(
    'INSERT INTO welcome_runs (id) VALUES (?)',
    <Object?>[job.id],
  );
}
''');
    write('bin/probe.dart', _probe);

    // `dartvel routes` as a separate process, so this suite never moves the
    // runner's working directory, which every suite beside it shares.
    final String cliPackage = p.join(packages, 'dartvel_cli');
    final ProcessResult generated = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: project.path,
    );
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

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, String> inherited() => <String, String>{
    for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
      if (Platform.environment[key] != null) key: Platform.environment[key]!,
  };

  /// A fresh shared database for one test, as DATABASE_URL names it.
  String database() {
    final Directory dir = Directory.systemTemp.createTempSync('dv_jobs_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    return p.join(dir.path, 'app.db');
  }

  Future<Map<String, Object?>> probe(Map<String, String> environment) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{...inherited(), ...environment},
    ).timeout(const Duration(minutes: 3));
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

  /// Starts the generated entry point, `.dart_tool/dartvel_server.dart`.
  Future<(Process, StringBuffer)> start(Map<String, String> environment) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '.dart_tool/dartvel_server.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{...inherited(), ...environment},
    );
    addTearDown(process.kill);
    final StringBuffer output = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(output.write);
    process.stderr.transform(utf8.decoder).listen(output.write);
    return (process, output);
  }

  Future<void> until(
    bool Function() condition,
    StringBuffer output, {
    Duration within = const Duration(minutes: 2),
  }) async {
    final DateTime deadline = DateTime.now().add(within);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting; the process said:\n$output');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<List<String>> welcomed(String file) async {
    if (!File(file).existsSync()) return const <String>[];
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(file);
    try {
      final List<Map<String, Object?>> tables = await db.query(
        "SELECT name FROM sqlite_master WHERE name = 'welcome_runs'",
      );
      if (tables.isEmpty) return const <String>[];
      return <String>[
        for (final Map<String, Object?> row
            in await db.query('SELECT id FROM welcome_runs'))
          row['id']! as String,
      ];
    } finally {
      db.close();
    }
  }

  group('a worker', () {
    test(
      'runs a job a web process dispatched, once, from the shared database',
      () async {
        final String file = database();
        final Map<String, Object?> dispatched = await probe(<String, String>{
          'PROBE_MODE': 'dispatch',
          'PROBE_JOB_ID': 'ada',
          'DARTVEL_PORT': '${await freePort()}',
          'DATABASE_URL': 'sqlite://$file',
        });
        expect(dispatched['error'], isNull);
        expect(dispatched['queueShared'], isTrue);
        // Not run in the web process: it serves, and the job waits.
        expect(await welcomed(file), isEmpty);

        final (Process _, StringBuffer output) = await start(<String, String>{
          'DARTVEL_ROLE': 'worker',
          'DATABASE_URL': 'sqlite://$file',
        });
        await until(() => '$output'.contains('dartvel worker'), output);
        final DateTime deadline =
            DateTime.now().add(const Duration(seconds: 30));
        while ((await welcomed(file)).isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(await welcomed(file), <String>['ada'], reason: '$output');
      },
    );

    test(
      'the control: a web process with no DATABASE_URL reaches no worker',
      () async {
        final String file = database();
        final Map<String, Object?> dispatched = await probe(<String, String>{
          'PROBE_MODE': 'dispatch',
          'PROBE_JOB_ID': 'lost',
          'DARTVEL_PORT': '${await freePort()}',
        });
        expect(dispatched['error'], isNull);
        expect(dispatched['queueShared'], isFalse);

        final (Process _, StringBuffer output) = await start(<String, String>{
          'DARTVEL_ROLE': 'worker',
          'DATABASE_URL': 'sqlite://$file',
        });
        await until(() => '$output'.contains('dartvel worker'), output);
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(await welcomed(file), isEmpty);
      },
    );

    test('with no DATABASE_URL it refuses to start, naming it', () async {
      final (Process process, StringBuffer output) = await start(
        const <String, String>{'DARTVEL_ROLE': 'worker'},
      );
      final int code =
          await process.exitCode.timeout(const Duration(minutes: 3));
      expect(code, isNot(0), reason: '$output');
      expect('$output', contains('DATABASE_URL'));
    });

    test(
      'serves /healthz on DARTVEL_HEALTH_PORT, and nothing of the application',
      () async {
        final String file = database();
        final int health = await freePort();
        final (Process _, StringBuffer output) = await start(<String, String>{
          'DARTVEL_ROLE': 'worker',
          'DATABASE_URL': 'sqlite://$file',
          'DARTVEL_HEALTH_PORT': '$health',
        });
        await until(() => '$output'.contains('dartvel worker'), output);

        Future<(int, String)> get(String path) async {
          final HttpClient client = HttpClient();
          try {
            final HttpClientResponse response = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:$health$path'),
            ))
                .close();
            return (
              response.statusCode,
              await response.transform(utf8.decoder).join(),
            );
          } finally {
            client.close(force: true);
          }
        }

        final (int status, String body) = await get('/healthz');
        expect(status, 200, reason: '$output');
        expect(jsonDecode(body), <String, Object?>{
          'status': 'ok',
          'role': 'worker',
        });
        expect((await get('/api/ping')).$1, 404);
      },
    );
  });

  group('two cron processes on one database', () {
    Future<int> pair(Map<String, String> environment) async {
      final List<Map<String, Object?>> reports =
          await Future.wait(<Future<Map<String, Object?>>>[
        probe(environment),
        probe(environment),
      ]);
      for (final Map<String, Object?> r in reports) {
        expect(r['error'], isNull);
        // Both schedulers ran through the boundary, or a count of 1 means a
        // process that never got there rather than a lease.
        expect(r['clockRead'], isTrue);
      }
      return reports.fold<int>(
        0,
        (int sum, Map<String, Object?> r) => sum + (r['cronRuns']! as int),
      );
    }

    test('fire an occurrence once between them', () async {
      final String file = database();
      expect(
        await pair(<String, String>{
          'PROBE_MODE': 'cron',
          'DARTVEL_ROLE': 'cron',
          'DATABASE_URL': 'sqlite://$file',
        }),
        1,
      );
    });

    test('the control: told there is no lease, each fires it', () async {
      final String file = database();
      expect(
        await pair(<String, String>{
          'PROBE_MODE': 'cron',
          'DARTVEL_ROLE': 'cron',
          'DATABASE_URL': 'sqlite://$file',
          'DARTVEL_SCHEDULE_LEASE': 'none',
        }),
        2,
      );
    });

    test('a declared cron process with no shared store exits 78', () async {
      final (Process process, StringBuffer output) = await start(
        const <String, String>{'DARTVEL_ROLE': 'cron'},
      );
      final int code =
          await process.exitCode.timeout(const Duration(minutes: 3));
      expect(code, 78, reason: '$output');
      expect('$output', contains('DATABASE_URL'));
      expect('$output', contains('DARTVEL_SCHEDULE_LEASE=none'));
      // The start line, not the word: the refusal itself says "ticking".
      expect('$output', isNot(contains('dartvel cron ticking')));
    });
  });

  test('dartvel queue work runs the application\'s handlers', () async {
    final String file = database();
    final Map<String, Object?> dispatched = await probe(<String, String>{
      'PROBE_MODE': 'dispatch',
      'PROBE_JOB_ID': 'grace',
      'DARTVEL_PORT': '${await freePort()}',
      'DATABASE_URL': 'sqlite://$file',
    });
    expect(dispatched['queueShared'], isTrue);

    final String cliPackage = p.join(packages, 'dartvel_cli');
    final ProcessResult worked = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'dartvel.dart'),
        'queue',
        'work',
        '--max-jobs',
        '5',
      ],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        ...inherited(),
        'DATABASE_URL': 'sqlite://$file',
      },
    ).timeout(const Duration(minutes: 4));
    expect(
      worked.exitCode,
      0,
      reason: '${worked.stdout}\n${worked.stderr}',
    );
    expect(await welcomed(file), <String>['grace']);
  });
}
