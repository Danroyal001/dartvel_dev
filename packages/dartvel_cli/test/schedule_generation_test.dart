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

  group('catch-up per schedule', () {
    // A schedule that must not miss a period and one that must not repeat
    // itself are both ordinary, and the annotation could say neither. The
    // scheduler took catchUp per task from the day it was written; the only
    // way to reach it was a hand-written register() call, which is the thing
    // generated schedules exist so nobody writes.
    Future<String> schedulesFor(String annotation) async {
      final Directory root =
          await Directory.systemTemp.createTemp('dartvel_cron_catchup_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      final Directory functionsDir =
          Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            ..createSync(recursive: true);
      File(p.join(functionsDir.path, 'rollup.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

$annotation
Future<void> rollUpYesterday() async {}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'cron_catchup_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      return File(
        p.join(root.path, 'lib', 'dartvel_client', 'schedules.g.dart'),
      ).readAsStringSync();
    }

    test('a schedule that asks for catch-up still reaches the list at all',
        () async {
      // The first thing an extra argument breaks is the match: the pattern
      // required the expression to be the whole of the annotation, so a
      // schedule that asked for catch-up was not a schedule. It would have
      // disappeared from the generated list with nothing said, which is a
      // worse outcome than the argument being ignored.
      final String content = await schedulesFor(
        "@DVBackendCron('0 3 * * *', catchUp: true)",
      );

      expect(content, contains('rollUpYesterday'));
    });

    test('and it is carried into the entry', () async {
      final String content = await schedulesFor(
        "@DVBackendCron('0 3 * * *', catchUp: true)",
      );

      expect(content, contains('catchUp: true'));
    });

    test('a schedule that refuses catch-up says so rather than saying nothing',
        () async {
      // Distinct from not mentioning it. An application that starts its
      // schedules with catchUp: true is making a blanket decision, and a
      // nightly digest that wrote catchUp: false has already made a narrower
      // one that must win over it.
      final String content = await schedulesFor(
        "@DVBackendCron('0 3 * * *', catchUp: false)",
      );

      expect(content, contains('catchUp: false'));
    });

    test('a schedule that says nothing carries nothing', () async {
      final String content = await schedulesFor("@DVBackendCron('0 3 * * *')");

      expect(content, contains('rollUpYesterday'));
      expect(content, isNot(contains('catchUp: true')));
      expect(content, isNot(contains('catchUp: false')));
    });

    test('a client schedule can ask for it too', () async {
      final String content = await schedulesFor(
        "@DVClientCron('0 3 * * *', catchUp: true)",
      );

      expect(content, contains('catchUp: true'));
    });

    test('a catch-up the generator cannot read stops the build', () async {
      // Not treated as unstated. Somebody who wrote catchUp has decided
      // something about missed periods, and generating a schedule that
      // ignores it is the silent half of the failure this whole path exists
      // to end.
      await expectLater(
        schedulesFor("@DVBackendCron('0 3 * * *', catchUp: kCatchUp)"),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('rollup.dart'),
              contains('catchUp'),
            ),
          ),
        ),
      );
    });
  });

  group('a client tick is a wakeup as well as a tick', () {
    // On a phone it is both. A timer firing every twenty seconds while the
    // application is in somebody's pocket wakes the device for a schedule
    // that could have waited, and the timer stops mattering the moment the
    // system suspends it anyway -- so the periods that pass while the
    // application is away arrive whenever the timer happens to fire next
    // rather than when it comes back.
    Future<Map<String, String>> generate(String page) async {
      final Directory root =
          await Directory.systemTemp.createTemp('dartvel_cron_wake_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      final Directory pagesDir = Directory(p.join(root.path, 'lib', 'pages'))
        ..createSync(recursive: true);
      File(p.join(pagesDir.path, 'home.dart')).writeAsStringSync(page);

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'cron_wake_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final Directory client =
          Directory(p.join(root.path, 'lib', 'dartvel_client'));
      return <String, String>{
        for (final FileSystemEntity entity in client.listSync())
          if (entity is File) p.basename(entity.path): entity.readAsStringSync(),
      };
    }

    const String withSchedule = '''
import 'package:dartvel_core/dartvel.dart';

@DVClientCron('*/5 * * * *')
void refreshDashboard() {}
''';

    test('it stops while the application is away and starts when it returns',
        () async {
      final Map<String, String> files = await generate(withSchedule);
      final String client = files['client_schedules.g.dart']!;

      expect(client, contains('DV.lifecycle.app'));
      expect(client, contains('DVAppLifecycle.backgrounded'));
      expect(client, contains('DVAppLifecycle.ready'));
    });

    test('and whatever came due while it was away runs on the way back',
        () async {
      // Not on the next tick, which could be twenty seconds after somebody
      // opened the application and is the whole of what they are waiting on.
      final Map<String, String> files = await generate(withSchedule);
      final String client = files['client_schedules.g.dart']!;

      final int resume = client.indexOf('DVAppLifecycle.ready');
      final int tick = client.indexOf('tick()', resume);
      expect(resume, greaterThan(-1));
      expect(tick, greaterThan(resume),
          reason: 'coming back does not tick, so a due period waits');
    });

    test('an application with no client schedule listens to nothing',
        () async {
      // A lifecycle listener in every application that has no schedule is
      // the same cost as the timer this file already refuses to start.
      final Map<String, String> files = await generate('''
import 'package:dartvel_core/dartvel.dart';

void refreshDashboard() {}
''');
      final String client = files['client_schedules.g.dart']!;

      expect(client, isNot(contains('DV.lifecycle.app.listen')));
    });
  });
}
