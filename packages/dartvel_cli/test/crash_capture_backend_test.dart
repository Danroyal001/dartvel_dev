// A generated backend's unhandled errors are crash reports, labelled with the
// role of the process that had them.
//
// One binary runs as the web server, the queue worker and the schedules, and
// each of them fails in its own way: a request that answers 500, a job whose
// handler throws until it is dead-lettered, a schedule that throws. Before
// this the first printed to stderr, the second became a row in a dead-letter
// table and the third was appended to a list nothing read -- none reached the
// crash runtime. This generates a real backend and runs each role as its own
// process, asserting on the records each wrote. The silent failures:
//
//  * a failure that writes no record, or one labelled with the wrong role;
//  * a job recorded on every retry, where only the failure nothing recovered
//    from is unhandled.
@Timeout(Duration(minutes: 20))
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

import 'package:capture_probe/dartvel_client/jobs.g.dart' as jobs;
import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  final Map<String, String> env = Platform.environment;
  final Completer<void> stop = Completer<void>();
  final Map<String, Object?> out = <String, Object?>{};
  Object? error;
  final String mode = env['PROBE_MODE']!;

  if (mode == 'web' || mode == 'dispatch') {
    final Future<void> running = gen
        .dartvelMain(arguments, until: stop.future)
        .catchError((Object e) => error = e);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (error == null && mode == 'web') {
      final HttpClient client = HttpClient();
      try {
        final HttpClientResponse response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${env['DARTVEL_PORT']}/api/boom'),
        ))
            .close();
        out['status'] = response.statusCode;
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    }
    if (error == null && mode == 'dispatch') {
      await jobs.Poison(id: 'p1').dispatch();
    }
    stop.complete();
    await running.timeout(const Duration(seconds: 10));
  } else {
    // cron: half a second before a minute boundary from the first clock read.
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
    stop.complete();
    await running.timeout(const Duration(seconds: 10));
  }

  out['error'] = error?.toString();
  stdout.writeln('PROBE ${jsonEncode(out)}');
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
    project = Directory.systemTemp.createTempSync('dv_crash_capture_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: capture_probe
version: 3.1.0
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
  backendPort: ${await freePort()}
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    write('lib/backend/functions/boom.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _boom() async => throw StateError('request failed');
''');
    write('lib/backend/schedules.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('* * * * *')
Future<void> failingSchedule() async {
  throw StateError('schedule failed');
}
''');
    write('lib/jobs/poison.dart', '''
import 'package:capture_probe/dartvel_client/dartvel_client.dart';

@DVJob()
class _Poison {
  final String id;

  const _Poison({required this.id});
}

@DVJob.handler()
Future<void> _handlePoison(Poison job) async {
  throw StateError('job failed');
}
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
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
      };

  String temporary(String prefix) {
    final Directory dir = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir.path;
  }

  List<Map<String, Object?>> records(String directory) => <Map<String, Object?>>[
        if (Directory(directory).existsSync())
          for (final FileSystemEntity f in Directory(directory).listSync())
            if (f is File && f.path.endsWith('.crash'))
              jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
      ];

  Map<String, Object?> contextOf(Map<String, Object?> record) =>
      record['context']! as Map<String, Object?>;

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
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  test('a request that fails with a 500 is recorded by the web process',
      () async {
    final String crashes = temporary('dv_capture_web_');
    final Map<String, Object?> r = await probe(<String, String>{
      'PROBE_MODE': 'web',
      'DARTVEL_ROLE': 'web',
      'DARTVEL_PORT': '${await freePort()}',
      'DARTVEL_CRASH_DIR': crashes,
    });

    expect(r['error'], isNull);
    expect(r['status'], 500);
    final Map<String, Object?> record = records(crashes).single;
    expect(contextOf(record)['role'], 'web');
    expect(contextOf(record)['release'], '3.1.0');
    expect(record['message'], 'Bad state: request failed');
    expect(record['kind'], 'fatal');
  });

  test('a schedule that throws is recorded by the cron process', () async {
    final String crashes = temporary('dv_capture_cron_');
    final Map<String, Object?> r = await probe(<String, String>{
      'PROBE_MODE': 'cron',
      'DARTVEL_ROLE': 'cron',
      'DARTVEL_SCHEDULE_LEASE': 'none',
      'DARTVEL_CRASH_DIR': crashes,
    });

    expect(r['error'], isNull);
    final Map<String, Object?> record = records(crashes).single;
    expect(contextOf(record)['role'], 'cron');
    expect(record['message'], 'Bad state: schedule failed');
  });

  test('a job that fails until it is dead-lettered is recorded once, by the '
      'worker', () async {
    final String database = p.join(temporary('dv_capture_db_'), 'app.db');
    final String webCrashes = temporary('dv_capture_dispatch_');
    final Map<String, Object?> dispatched = await probe(<String, String>{
      'PROBE_MODE': 'dispatch',
      'DARTVEL_PORT': '${await freePort()}',
      'DATABASE_URL': 'sqlite://$database',
      'DARTVEL_CRASH_DIR': webCrashes,
    });
    expect(dispatched['error'], isNull);

    final String crashes = temporary('dv_capture_worker_');
    final Process worker = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '.dart_tool/dartvel_server.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        ...inherited(),
        'DARTVEL_ROLE': 'worker',
        'DATABASE_URL': 'sqlite://$database',
        'DARTVEL_CRASH_DIR': crashes,
      },
    );
    addTearDown(worker.kill);
    final StringBuffer output = StringBuffer();
    worker.stdout.transform(utf8.decoder).listen(output.write);
    worker.stderr.transform(utf8.decoder).listen(output.write);

    final DateTime deadline = DateTime.now().add(const Duration(minutes: 2));
    while (records(crashes).isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // Long enough for a retry to have been recorded too, if retries were.
    await Future<void>.delayed(const Duration(seconds: 5));

    final List<Map<String, Object?>> written = records(crashes);
    expect(written, hasLength(1), reason: '$output');
    expect(contextOf(written.single)['role'], 'worker');
    expect(written.single['message'], 'Bad state: job failed');
    expect(records(webCrashes), isEmpty);
  });
}
