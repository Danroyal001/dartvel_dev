// The generated server runs change capture from the pubspec.
//
// `@DVModel(capture: true)` and `dartvel.capture` are all an application
// writes. This generates a project with exactly that -- one captured data
// model and one database destination, its connection named by a secret --
// runs the generated backend as the whole deployment against a SQLite
// database, and asserts on what reaches the destination's database: the row
// that was there before the destination existed (a backfill), the row
// written while the server runs (delivery on the job queue), no sensitive
// field in either, and the lag gauge the server reports. Nothing in the
// project names the capture machinery.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(capture: true, subject: DVSubject.self)
class _Order {
  final String id;
  final int total;
  @DVModel.sensitiveField()
  final String email;

  const _Order({required this.id, required this.total, required this.email});
}
''';

/// Runs the generated backend and writes the way a generated data model
/// does. The model class itself imports Flutter, which a server probe does
/// not have, so its table is built here exactly as the model builds it --
/// the same table, key, columns, sensitive set and log.
const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_core/src/observability/observability.dart';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

DVRecordTable orders({DVDatabaseAdapter? database}) => DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'total', 'email'],
      sensitive: const <String>{'email'},
      capture: DVCapture.configured,
      database: database,
    );

Future<void> main(List<String> arguments) async {
  final Map<String, String> env = Platform.environment;
  final Map<String, Object?> report = <String, Object?>{};
  Object? error;

  // A row stored before the destination existed, by a process with no
  // database configured and so no log: what a destination added today has
  // to be backfilled with.
  final SqliteDVDatabaseAdapter before =
      SqliteDVDatabaseAdapter.file(env['APP_DB']!);
  await orders(database: before).ensureSchema();
  await orders(database: before).write(
      <String, Object?>{'id': 'o1', 'total': 10, 'email': 'ada@x.test'});
  before.close();

  final Completer<void> stop = Completer<void>();
  final Future<void> running = gen
      .dartvelMain(
        arguments,
        until: stop.future,
        scheduleTick: const Duration(milliseconds: 100),
      )
      .catchError((Object e) => error = e);

  final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
  while (error == null &&
      !DVCaptureRuntime.isConfigured &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  report['configured'] = DVCaptureRuntime.isConfigured;
  report['queues'] = DVCaptureRuntime.queues;

  if (error == null && DVCaptureRuntime.isConfigured) {
    // An ordinary save, while the server runs.
    await orders().write(
        <String, Object?>{'id': 'o2', 'total': 20, 'email': 'bo@x.test'});

    final SqliteDVDatabaseAdapter warehouse =
        SqliteDVDatabaseAdapter.file(env['WAREHOUSE_DB']!);
    List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    while (DateTime.now().isBefore(deadline)) {
      try {
        rows = await warehouse.query('SELECT * FROM orders ORDER BY _dv_key');
      } on Object {
        rows = <Map<String, Object?>>[];
      }
      if (rows.length >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    warehouse.close();
    report['keys'] = <Object?>[for (final r in rows) r['_dv_key']];
    report['totals'] = <Object?>[for (final r in rows) r['total']];
    report['columns'] = rows.isEmpty ? <String>[] : rows.first.keys.toList();
    // Give the schedule a pass after delivery, so the gauge is measured.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    report['metrics'] = DVObservability.metrics.render();
  }

  if (!stop.isCompleted) stop.complete();
  await running.timeout(const Duration(seconds: 10), onTimeout: () {});
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
    project = Directory.systemTemp.createTempSync('dv_capture_server_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: capture_server_probe
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
  capture:
    retention: 7d
    destinations:
      warehouse:
        type: database
        connection: WAREHOUSE_URL
        models: [Order]
        lagThreshold: 10m
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    write('lib/models/order.dart', _model);
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

  test('nothing in the project names the capture machinery', () {
    final Iterable<File> written = Directory(p.join(project.path, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('.dart') && !f.path.contains('dartvel_client'));
    for (final File file in written) {
      expect(file.readAsStringSync(),
          isNot(matches(RegExp(r'DVCapture|DVWarehouseSink|backfillTo'))),
          reason: file.path);
    }
  });

  test(
      'the whole deployment backfills the destination, delivers every save '
      'and reports lag', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('dv_capture_server_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String appDb = p.join(dir.path, 'app.db');
    final String warehouseDb = p.join(dir.path, 'warehouse.db');

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String k in <String>[
          'PATH',
          'HOME',
          'PUB_CACHE',
          'TMPDIR',
          'LD_LIBRARY_PATH',
        ])
          if (Platform.environment[k] != null) k: Platform.environment[k]!,
        'DARTVEL_PORT': '${await freePort()}',
        'DATABASE_URL': 'sqlite://$appDb',
        'WAREHOUSE_URL': 'sqlite://$warehouseDb',
        'APP_DB': appDb,
        'WAREHOUSE_DB': warehouseDb,
      },
    ).timeout(const Duration(minutes: 5));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    final Map<String, Object?> report =
        jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;

    expect(report['error'], isNull, reason: '${result.stderr}');
    expect(report['configured'], isTrue,
        reason: 'the pubspec declares capture, so the server configures it');
    expect(report['keys'], <Object?>['o1', 'o2'],
        reason: 'o1 by backfill, o2 by delivery');
    expect(report['columns'], isNot(contains('email')),
        reason: 'a sensitive field never reaches a destination');
    expect('${report['metrics']}',
        contains('dv_capture_lag_changes{consumer="warehouse"}'));
  });
}
