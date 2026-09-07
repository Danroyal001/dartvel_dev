import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('backend generator emits typed cron schedule metadata', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_cron_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);
      final pagesDir = Directory(p.join(root.path, 'lib', 'pages'))
        ..createSync(recursive: true);

      File(p.join(functionsDir.path, 'cleanup.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('0 * * * *')
Future<void> cleanupExpiredSessions() async {}
''');
      File(p.join(pagesDir.path, 'refresh.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVClientCron('*/5 * * * *')
void refreshDashboard() {}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'cron_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final schedules = File(
        p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      );
      expect(schedules.existsSync(), isTrue);
      final content = schedules.readAsStringSync();
      expect(content, contains('library dartvel_client_schedules'));
      expect(content, contains('cleanupExpiredSessions'));
      expect(content, contains('refreshDashboard'));
      expect(content, contains('DVCronTarget.backend'));
      expect(content, contains('DVCronTarget.client'));
      expect(content, contains('dartvelBackendCronEntries'));
      expect(content, contains('dartvelClientCronEntries'));
    } finally {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    }
  });

  test('a backend cron schedule is actually run', () async {
    // The metadata test above asserts the entries exist. They did, and
    // nothing ever read them: DVScheduler was instantiated in exactly one
    // place in the repository and that place was its own unit test, so a
    // schedule travelled from the annotation into a generated list and
    // stopped. The section recorded this as shipped and said the scheduler
    // ran them.
    final root = await Directory.systemTemp.createTemp('dartvel_cron_runs_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);

      File(p.join(functionsDir.path, 'cleanup.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('0 * * * *')
Future<void> cleanupExpiredSessions() async {}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'cron_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final schedules = File(
        p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      ).readAsStringSync();

      // A handler map, so registerAll has something to register against.
      // Without it registerAll throws rather than silently skipping, which
      // is deliberate -- a job that appears scheduled and never runs is the
      // failure being fixed here.
      expect(schedules, contains('dartvelBackendCronHandlers'));
      expect(schedules, contains('cleanupExpiredSessions()'));
      expect(schedules, contains('DVScheduler('));
      expect(schedules, contains('registerAll('));
      expect(schedules, contains('.tick()'));

      // And something has to call it. The scheduler existing in a generated
      // file nobody imports is the same silence one directory over.
      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, contains('dartvelStartBackendSchedules('));
      final startAt = routes.indexOf('Future<dv.ServerHandle> startBackend(');
      expect(startAt, greaterThan(-1));
      expect(
        routes.substring(startAt, routes.indexOf('dv.serve(', startAt)),
        contains('dartvelStartBackendSchedules('),
      );
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  test('an application with no cron does not start a scheduler', () async {
    // A timer ticking every thirty seconds in every application that
    // declares no schedule is a cost nobody asked for, and it would make the
    // test above pass whether or not anything was registered.
    final root = await Directory.systemTemp.createTemp('dartvel_cron_none_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'quiet_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final schedules = File(
        p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      ).readAsStringSync();
      expect(schedules, contains('dartvelStartBackendSchedules'));
      expect(schedules, contains('dartvelBackendCronHandlers'));
      // Declared and empty, so the call is a no-op rather than a timer.
      expect(
        schedules,
        contains('dartvelBackendCronHandlers = '
            '<String, Future<void> Function()>{};'),
      );
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });
}
