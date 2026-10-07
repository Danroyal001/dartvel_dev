import 'dart:io';

import 'package:dartvel_cli/src/update/self_update.dart';
import 'package:test/test.dart';

void main() {
  for (final name in [
    'dart',
    'dart.exe',
    'dartvm',
    'dartvm.exe',
    'dartaotruntime',
    'dartaotruntime.exe',
  ]) {
    test('refuses to replace the $name runtime before downloading', () async {
      final root = Directory.systemTemp.createTempSync('dv-runtime-guard-');
      addTearDown(() => root.deleteSync(recursive: true));
      final runtime = File('${root.path}/$name')
        ..writeAsStringSync('original runtime');
      final bytes = '#!/bin/sh\nexit 0'.codeUnits;
      var downloaded = false;
      await expectLater(
        dvUpgradeExecutable(
          current: runtime,
          runningVersion: '1.0.0',
          os: 'linux',
          arch: 'x64',
          currentPath: '',
          home: root.path,
          shell: '/bin/bash',
          fetchManifest: () async => {
            'version': '2.0.0',
            'assets': {
              'dartvel-linux-amd64': {
                'url': 'https://fake.test',
                'sha256': dvSha256Hex(bytes),
              },
            },
          },
          download: (_) async {
            downloaded = true;
            return bytes;
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('packaged dartvel binary'),
          ),
        ),
      );
      expect(downloaded, isFalse);
      expect(runtime.readAsStringSync(), 'original runtime');
      expect(File('${root.path}/dartvel').existsSync(), isFalse);
    });
  }
}
