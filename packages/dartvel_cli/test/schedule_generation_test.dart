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
}
