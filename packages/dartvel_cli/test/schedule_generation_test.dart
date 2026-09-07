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
      // Awaited, because it returns a Future. The plain-void case is next
      // door and is the one that must not be.
      expect(schedules, contains('await cron0.cleanupExpiredSessions();'));
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

  test('a client cron schedule is started by the runtime', () async {
    // The client entries were generated and nothing started them, so a
    // schedule declared on a page never ran once. Its handlers live in their
    // own file because the generated backend imports schedules.g.dart, and a
    // page pulled in there would put Flutter into a server with no dart:ui.
    final root = await Directory.systemTemp.createTemp('dartvel_client_cron_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      final pagesDir = Directory(p.join(root.path, 'lib', 'pages'))
        ..createSync(recursive: true);

      File(p.join(pagesDir.path, 'refresh.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVClientCron('*/5 * * * *')
void refreshDashboard() {}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'client_cron_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final client = File(
        p.join(root.path, 'lib', 'dartvel_client', 'client_schedules.g.dart'),
      ).readAsStringSync();
      expect(client, contains('dartvelClientCronHandlers'));
      // Not awaited. A @DVClientCron is usually written void refresh() {},
      // and  on a plain void is an error rather than a no-op -- the
      // generated handler did not compile, and every job that runs the
      // example failed on it at once.
      expect(client, contains('{ cron0.refreshDashboard(); }'));
      expect(client, isNot(contains('await cron0.refreshDashboard')));
      expect(client, contains('DVScheduler('));
      expect(client, contains('.tick()'));

      // And the page it came from must not be imported into the backend's
      // file, which is the reason there are two. Its path is in there as an
      // entry's filePath, which is data; an import is what would pull
      // Flutter into the server.
      final backend = File(
        p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      ).readAsStringSync();
      expect(
        backend,
        isNot(contains("import 'package:client_cron_app/pages/refresh.dart'")),
      );
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  test('a schedule on a private function is refused, not dropped', () async {
    // Dropping it silently is not available: the entry list is what
    // registerAll reads, and it refuses an entry with no handler, so a
    // schedule left in the list without one is a server that will not start.
    // Filtering it out of both would be a schedule that is declared and
    // never runs, which is what this whole path was fixed to end.
    final root = await Directory.systemTemp.createTemp('dartvel_cron_priv_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);

      File(p.join(functionsDir.path, 'sweep.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendCron('0 * * * *')
Future<void> _sweep() async {}
''');

      await expectLater(
        BackendGenerator.generate(
          root: root.path,
          backendDir: 'lib/backend',
          pkgName: 'cron_priv_app',
          buildId: 'test-build',
          backendHost: '127.0.0.1',
          backendPort: 3000,
          apiBasePath: '/api',
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('_sweep'),
              contains('sweep.dart'),
              contains('private'),
            ),
          ),
        ),
      );
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });
}
