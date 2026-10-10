// DV.log on a device: the directory its file goes in, and what the runtime
// installs from dartvel.logging.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dvLogDirectoryFor', () {
    test('sits beside the crash records on every platform', () {
      expect(
          dvLogDirectoryFor(
              appId: 'shop',
              os: 'linux',
              environment: const <String, String>{'HOME': '/home/ada'}),
          '/home/ada/.local/share/shop/dartvel-logs');
      expect(
          dvLogDirectoryFor(
              appId: 'shop',
              os: 'android',
              environment: const <String, String>{},
              androidStateDirectory: '/data/user/0/shop/files/dartvel'),
          '/data/user/0/shop/files/dartvel-logs');
      expect(
          dvLogDirectoryFor(
              appId: 'shop',
              os: 'ios',
              environment: const <String, String>{'HOME': '/var/app'}),
          '/var/app/Library/Application Support/shop/dartvel-logs');
    });

    test('DARTVEL_LOG_DIR wins, and the crash override does not move it', () {
      expect(
          dvLogDirectoryFor(
              appId: 'shop',
              os: 'linux',
              environment: const <String, String>{
                'HOME': '/home/ada',
                'DARTVEL_LOG_DIR': '/srv/logs',
              }),
          '/srv/logs');
      expect(
          dvLogDirectoryFor(
              appId: 'shop',
              os: 'linux',
              environment: const <String, String>{
                'HOME': '/home/ada',
                'DARTVEL_CRASH_DIR': '/srv/crashes',
              }),
          '/home/ada/.local/share/shop/dartvel-logs');
    });

    test('no directory that survives a restart means no file', () {
      expect(
          dvLogDirectoryFor(
              appId: 'shop', os: 'android', environment: const <String, String>{}),
          isNull);
    });
  });

  group('dvInstallApplicationLogging', () {
    tearDown(dvResetApplicationLogging);

    test('nothing is installed under flutter test unless asked', () {
      expect(
          dvInstallApplicationLogging(
              appId: 'shop', release: '1', config: const DVLogConfig()),
          isNull);
    });

    test('the declared level applies and the device keeps a file', () async {
      final String appId =
          'dv_log_install_${DateTime.now().microsecondsSinceEpoch}';
      final DVLogInstallation? installed = dvInstallApplicationLogging(
        appId: appId,
        release: '1',
        config: DVLogConfig.parse(<String, Object?>{'level': 'warn'}),
        evenUnderTest: true,
      );
      final String? directory = dvLogDirectoryFor(
          appId: appId, os: Platform.operatingSystem, environment: Platform.environment);
      addTearDown(() {
        if (directory != null && Directory(directory).existsSync()) {
          Directory(directory).parent.deleteSync(recursive: true);
        }
      });
      expect(installed, isNotNull);
      expect(installed!.file, isNotNull);
      expect(installed.shipper, isNull,
          reason: 'nothing leaves the device unless shipping is declared');

      DV.log.info('below the declared floor');
      DV.log.warn('kept on disk', tag: 'boot');

      final String exported = await DV.log.export();
      expect(exported, contains('kept on disk'));
      expect(exported, isNot(contains('below the declared floor')));
      expect(File('$directory/dartvel.log').readAsStringSync(),
          contains('kept on disk'));
    });
  });
}
