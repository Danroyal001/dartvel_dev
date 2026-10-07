import 'dart:io';

import 'package:dartvel_cli/src/update/self_update.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File current;
  late File stale;
  late File rc;
  const script = '#!/bin/sh\nprintf upgraded';
  final bytes = script.codeUnits;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv-upgrade-');
    Directory('${root.path}/download').createSync();
    Directory('${root.path}/bin').createSync();
    current = File('${root.path}/download/dartvel-linux-amd64')
      ..writeAsStringSync('original');
    stale = File('${root.path}/bin/dartvel')..writeAsStringSync('stale');
    rc = File('${root.path}/.bashrc')..writeAsStringSync('# original\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<bool> upgrade({
    String sum = '',
    String version = '2.0.0',
    Future<void> Function(String)? checkpoint,
  }) => dvUpgradeExecutable(
    current: current,
    runningVersion: '1.0.0',
    os: 'linux',
    arch: 'x64',
    currentPath: '${root.path}/bin',
    home: root.path,
    shell: '/bin/bash',
    fetchManifest: () async => {
      'version': version,
      'assets': {
        'dartvel-linux-amd64': {
          'url': 'https://fake.test/binary',
          'sha256': sum.isEmpty ? dvSha256Hex(bytes) : sum,
        },
      },
    },
    download: (_) async => bytes,
    checkpoint: checkpoint,
  );

  group('POSIX installation', () {
    test(
      'verified install is callable on PATH and old copies are removed',
      () async {
        expect(await upgrade(), isTrue);
        final installed = File('${current.parent.path}/dartvel');
        expect(installed.readAsStringSync(), script);
        expect(installed.statSync().mode & 0x40, isNot(0));
        expect(current.existsSync(), isFalse);
        expect(stale.existsSync(), isFalse);
        final result = await Process.run(
          'bash',
          ['-c', 'source "${rc.path}"; command -v dartvel'],
          environment: {'PATH': '${root.path}/bin:/usr/bin'},
        );
        expect(result.stdout.toString().trim(), installed.path);
        final invoked = await Process.run(
          'bash',
          ['-c', 'source "${rc.path}"; dartvel'],
          environment: {'PATH': '${root.path}/bin:/usr/bin'},
        );
        expect(invoked.exitCode, 0);
        expect(invoked.stdout, 'upgraded');
      },
      skip: Platform.isWindows,
    );

    test('checksum mismatch changes nothing', () async {
      await expectLater(upgrade(sum: 'bad'), throwsStateError);
      expect(current.readAsStringSync(), 'original');
      expect(stale.readAsStringSync(), 'stale');
      expect(rc.readAsStringSync(), '# original\n');
    });
    for (final stage in ['install', 'ensure-path', 'cleanup', 'retire']) {
      test(
        'failure at $stage restores binary, stale copies and shell config',
        () async {
          await expectLater(
            upgrade(
              checkpoint: (step) async {
                if (step == stage) throw StateError('injected $stage failure');
              },
            ),
            throwsStateError,
          );
          expect(current.readAsStringSync(), 'original');
          expect(stale.readAsStringSync(), 'stale');
          expect(rc.readAsStringSync(), '# original\n');
          expect(File('${current.parent.path}/dartvel').existsSync(), isFalse);
        },
      );
    }
    test('latest is a no-op without downloading or touching files', () async {
      expect(await upgrade(version: '1.0.0'), isFalse);
      expect(current.readAsStringSync(), 'original');
      expect(stale.readAsStringSync(), 'stale');
      expect(rc.readAsStringSync(), '# original\n');
    });
    test(
      'an actual ensure-path write failure restores the installation',
      () async {
        rc.deleteSync();
        Directory(rc.path).createSync();
        await expectLater(upgrade(), throwsA(isA<FileSystemException>()));
        expect(current.readAsStringSync(), 'original');
        expect(stale.readAsStringSync(), 'stale');
        expect(File('${current.parent.path}/dartvel').existsSync(), isFalse);
      },
    );
    test('rollback restores an existing canonical binary too', () async {
      final canonical = File('${current.parent.path}/dartvel')
        ..writeAsStringSync('previous canonical');
      await expectLater(
        upgrade(
          checkpoint: (stage) async {
            if (stage == 'retire') throw StateError('retirement failure');
          },
        ),
        throwsStateError,
      );
      expect(canonical.readAsStringSync(), 'previous canonical');
      expect(current.readAsStringSync(), 'original');
    });
    test('already-latest never calls the download function', () async {
      await dvUpgradeExecutable(
        current: current,
        runningVersion: '1.0.0',
        os: 'linux',
        arch: 'x64',
        currentPath: '',
        home: root.path,
        fetchManifest: () async => {
          'version': '1.0.0',
          'assets': {
            'dartvel-linux-amd64': {
              'url': 'https://fake.test',
              'sha256': 'unused',
            },
          },
        },
        download: (_) async => throw StateError('must not download'),
      );
      expect(current.readAsStringSync(), 'original');
    });
  }, skip: Platform.isWindows);
  test(
    'Windows PATH failure restores renamed images and unset user PATH',
    () async {
      final commands = <String>[];
      final exe = File('${current.parent.path}/dartvel-windows-amd64.exe')
        ..writeAsStringSync('original exe');
      await expectLater(
        dvUpgradeExecutable(
          current: exe,
          runningVersion: '1.0.0',
          os: 'windows',
          arch: 'x64',
          currentPath: '',
          home: root.path,
          fetchManifest: () async => {
            'version': '2.0.0',
            'assets': {
              'dartvel-windows-amd64.exe': {
                'url': 'https://fake.test',
                'sha256': dvSha256Hex(bytes),
              },
            },
          },
          download: (_) async => bytes,
          powershell: (command) async {
            commands.add(command);
            if (commands.length == 1) return 'null';
            if (commands.length == 2) throw StateError('PATH denied');
            return '';
          },
        ),
        throwsStateError,
      );
      expect(exe.readAsStringSync(), 'original exe');
      expect(File('${exe.parent.path}/dartvel.exe').existsSync(), isFalse);
      expect(commands.last, contains(r'$null'));
    },
  );
  test(
    'retirement failure restores a callable original already on PATH',
    () async {
      current = stale;
      current.writeAsStringSync('#!/bin/sh\nprintf original');
      await Process.run('chmod', ['+x', current.path]);
      await expectLater(
        upgrade(
          checkpoint: (stage) async {
            if (stage == 'retire') throw StateError('retirement failure');
          },
        ),
        throwsStateError,
      );
      final result = await Process.run(
        'bash',
        ['-c', 'dartvel'],
        environment: {'PATH': '${root.path}/bin:/usr/bin'},
      );
      expect(result.exitCode, 0);
      expect(result.stdout, 'original');
      expect(rc.readAsStringSync(), '# original\n');
    },
    skip: Platform.isWindows,
  );

  test(
    'update check works through the VM without download or installation',
    () async {
      expect(
        await dvUpgradeExecutable(
          current: File('${root.path}/dart'),
          runningVersion: '1.0.0',
          os: 'linux',
          arch: 'x64',
          currentPath: '',
          home: root.path,
          fetchManifest: () async => {
            'version': '2.0.0',
            'assets': {
              'dartvel-linux-amd64': {
                'url': 'https://fake.test',
                'sha256': 'unused',
              },
            },
          },
          download: (_) async => throw StateError('must not download'),
          checkOnly: true,
        ),
        isTrue,
      );
      expect(current.readAsStringSync(), 'original');
    },
  );
}
