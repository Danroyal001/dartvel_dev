// The generated server starts what DV.Privacy runs in the background.
//
// DV.Privacy was configured by the generated server and nothing more: the
// walk's own tables were never created, so the first requestErasure failed on
// a missing table; its jobs were registered by no process, so a worker
// dead-lettered an erasure or refused to start; worker and cron processes did
// not configure DV.Privacy at all; and no process swept retention or ran an
// erasure whose deadline was coming. This generates a backend, runs it as a
// web, worker and cron process against one SQLite database with
// DARTVEL_PRIVACY_KEY set, and asserts on that database and on the schedule
// occurrences each process claimed -- with the control of the same run with
// no key, where none of it may happen.
@Timeout(Duration(minutes: 15))
library;

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

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

class RecordingLease implements DVScheduleLease {
  final List<String> claimed = <String>[];

  @override
  Future<bool> claim(String task, DateTime occurrence) async {
    claimed.add(task);
    return true;
  }
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> env = Platform.environment;
  final Completer<void> stop = Completer<void>();
  final Map<String, Object?> report = <String, Object?>{};
  Object? error;
  final RecordingLease lease = RecordingLease();
  // Half a second before 03:00 when a scheduler first reads the clock, then
  // real speed, so the daily retention occurrence comes due once.
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
        scheduleLease: lease,
        scheduleClock: clock,
        scheduleTick: const Duration(milliseconds: 50),
      )
      .catchError((Object e) => error = e);

  if (env['PROBE_MODE'] == 'worker') {
    // --max-jobs 1 returns once the job completed.
    await running.timeout(const Duration(seconds: 60), onTimeout: () {
      error ??= 'the worker completed no job';
    });
  } else {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (error == null &&
        DateTime.now().isBefore(deadline) &&
        (first == null ||
            DateTime.now().difference(first!) <
                const Duration(milliseconds: 1500))) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    report['configured'] = DVPrivacyRuntime.isConfigured;
    if (env['PROBE_MODE'] == 'web' && error == null && DVPrivacyRuntime.isConfigured) {
      try {
        await DVPrivacyRuntime.current.requestErasure(subject: 'u1', reason: 'DSAR');
      } on Object catch (e) {
        report['requestError'] = '$e';
      }
    }
    if (!stop.isCompleted) stop.complete();
    await running.timeout(const Duration(seconds: 10));
  }
  report['claimed'] = lease.claimed;
  report['error'] = error?.toString();
  stdout.writeln('PROBE ${jsonEncode(report)}');
  exit(0);
}
''';

Future<int> freePort() async {
  final ServerSocket socket =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late Directory project;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    project = Directory.systemTemp.createTempSync('dv_privacy_server_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: privacy_server_probe
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
    write('bin/probe.dart', _probe);
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
          'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
    }
    final ProcessResult resolved = await Process.run(
        Platform.resolvedExecutable, <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  final String key = List<String>.filled(32, 'cd').join();

  String database() {
    final Directory dir = Directory.systemTemp.createTempSync('dv_privacy_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    return p.join(dir.path, 'app.db');
  }

  Future<Map<String, Object?>> probe(
    Map<String, String> environment, {
    List<String> arguments = const <String>[],
  }) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart', ...arguments],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String k in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[k] != null) k: Platform.environment[k]!,
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
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  Future<T> inDatabase<T>(
      String file, Future<T> Function(SqliteDVDatabaseAdapter db) read) async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(file);
    try {
      return await read(db);
    } finally {
      db.close();
    }
  }

  Future<Set<String>> tables(String file) => inDatabase(
        file,
        (SqliteDVDatabaseAdapter db) async => <String>{
          for (final Map<String, Object?> row in await db.query(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
            '${row['name']}',
        },
      );

  Future<int> count(String file, String sql) => inDatabase(
        file,
        (SqliteDVDatabaseAdapter db) async =>
            ((await db.query(sql)).single.values.single! as num).toInt(),
      );

  test(
      'a web process creates the walk\'s tables, queues an erasure a worker '
      'runs, and sweeps retention on its schedule', () async {
    final String file = database();
    final Map<String, Object?> web = await probe(<String, String>{
      'PROBE_MODE': 'web',
      'DARTVEL_PORT': '${await freePort()}',
      'DATABASE_URL': 'sqlite://$file',
      'DARTVEL_PRIVACY_KEY': key,
    });
    expect(web['error'], isNull);
    expect(web['configured'], isTrue);
    expect(web['requestError'], isNull);
    expect(
      await tables(file),
      containsAll(<String>[
        'dv_privacy_requests',
        DVPrivacy.tombstoneTable,
        DVPrivacy.openErasuresTable,
      ]),
    );
    expect(web['claimed'], contains(DVPrivacyRuntime.retentionTask));
    expect(
        await count(file, 'SELECT COUNT(*) AS n FROM ${DVPrivacy.openErasuresTable}'),
        1);

    final Map<String, Object?> worker = await probe(
      <String, String>{
        'PROBE_MODE': 'worker',
        'DARTVEL_ROLE': 'worker',
        'DATABASE_URL': 'sqlite://$file',
        'DARTVEL_PRIVACY_KEY': key,
      },
      arguments: <String>['--max-jobs', '1'],
    );
    expect(worker['error'], isNull);
    expect(
        await count(file, 'SELECT COUNT(*) AS n FROM ${DVPrivacy.openErasuresTable}'),
        0,
        reason: 'the worker ran the erasure, which closed the request');
    expect(
        await count(file,
            "SELECT COUNT(*) AS n FROM dv_privacy_requests WHERE kind = 'erase'"),
        1);
  });

  test('a cron process configures DV.Privacy and ticks its schedules',
      () async {
    final String file = database();
    final Map<String, Object?> cron = await probe(<String, String>{
      'PROBE_MODE': 'cron',
      'DARTVEL_ROLE': 'cron',
      'DATABASE_URL': 'sqlite://$file',
      'DARTVEL_PRIVACY_KEY': key,
    });
    expect(cron['error'], isNull);
    expect(cron['configured'], isTrue);
    expect(cron['claimed'], contains(DVPrivacyRuntime.retentionTask));
  });

  test('the control: with no DARTVEL_PRIVACY_KEY nothing of it starts',
      () async {
    final String file = database();
    final Map<String, Object?> web = await probe(<String, String>{
      'PROBE_MODE': 'web',
      'DARTVEL_PORT': '${await freePort()}',
      'DATABASE_URL': 'sqlite://$file',
    });
    expect(web['error'], isNull);
    expect(web['configured'], isFalse);
    expect(web['claimed'], isNot(contains(DVPrivacyRuntime.retentionTask)));
    expect(await tables(file), isNot(contains(DVPrivacy.openErasuresTable)));
  });
}
