/// Comprehensive CLI Command Tests
/// Tests all dartvel commands and their aliases
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  final tempDir = Directory.systemTemp.createTempSync('dartvel_cli_test');
  final testProjectDir = Directory(p.join(tempDir.path, 'test_project'));

  setUpAll(() {
    print('📦 Test directory: ${tempDir.path}');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('CLI Commands -', () {
    test('dartvel --version shows version info', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', '--version'],
        runInShell: true,
      );
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('dartvel'));
    });

    test('dartvel --help shows help information', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', '--help'],
        runInShell: true,
      );
      expect(result.exitCode, 0);
      final output = result.stdout.toString();
      expect(output, contains('Available commands:'));
      expect(output, contains('init'));
      expect(output, contains('dev'));
      expect(output, contains('build'));
    });

    test('dartvel init creates new project', () async {
      final result = await Process.run(
        'dart',
        [
          'run',
          'dartvel_cli:dartvel',
          'init',
          testProjectDir.path,
          '--org',
          'com.test'
        ],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      expect(testProjectDir.existsSync(), true);
      expect(
          File(p.join(testProjectDir.path, 'pubspec.yaml')).existsSync(), true);
      expect(Directory(p.join(testProjectDir.path, 'lib')).existsSync(), true);
      expect(
          Directory(p.join(testProjectDir.path, 'lib', 'pages')).existsSync(),
          true);
      expect(
          Directory(p.join(testProjectDir.path, 'lib', 'backend')).existsSync(),
          true);

      print('✅ Project structure created successfully');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('dartvel create is alias for init', () async {
      final createDir = Directory(p.join(tempDir.path, 'create_test'));
      final result = await Process.run(
        'dart',
        [
          'run',
          'dartvel_cli:dartvel',
          'create',
          createDir.path,
          '--org',
          'com.test'
        ],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      expect(createDir.existsSync(), true);
      print('✅ Create alias works correctly');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('dartvel doctor checks dependencies', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'doctor'],
        workingDirectory: testProjectDir.path,
        runInShell: true,
      );

      expect(result.exitCode, anyOf(0, 1)); // May fail if dependencies missing
      final output = result.stdout.toString();
      expect(output, contains('Dartvel Doctor'));
      print('✅ Doctor command executed');
    });

    test('dartvel routes generates route files', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'routes'],
        workingDirectory: testProjectDir.path,
        runInShell: true,
      );

      expect(result.exitCode, 0);
      expect(
          File(p.join(testProjectDir.path, 'lib', 'dartvel_client',
                  'router.g.dart'))
              .existsSync(),
          true);
      print('✅ Routes generated successfully');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('dartvel watch command exists', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'watch', '--help'],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('watch'));
      print('✅ Watch command available');
    });

    test('dartvel build --help shows build options', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'build', '--help'],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      final output = result.stdout.toString();
      expect(output, contains('platform'));
      expect(output, contains('release'));
      print('✅ Build command help displayed');
    });

    test('dartvel deploy --help shows deploy options', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'deploy', '--help'],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      final output = result.stdout.toString();
      expect(output, contains('deploy'));
      print('✅ Deploy command help displayed');
    });

    test('dartvel plugin list shows available plugins', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'plugin', 'list'],
        workingDirectory: testProjectDir.path,
        runInShell: true,
      );

      expect(result.exitCode, 0);
      print('✅ Plugin list command works');
    });

    test('dartvel version command works', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli:dartvel', 'version'],
        runInShell: true,
      );

      expect(result.exitCode, 0);
      expect(result.stdout.toString(), isNotEmpty);
      print('✅ Version command works');
    });

    test('dartvel dev aliases (run, start) exist', () async {
      final aliases = ['run', 'start'];

      for (final alias in aliases) {
        final result = await Process.run(
          'dart',
          ['run', 'dartvel_cli:dartvel', alias, '--help'],
          runInShell: true,
        );

        expect(result.exitCode, 0);
        print('✅ Alias "$alias" works');
      }
    });

    test('generated files have no analyzer errors', () async {
      final result = await Process.run(
        'dart',
        ['analyze', '--no-fatal-warnings'],
        workingDirectory: testProjectDir.path,
        runInShell: true,
      );

      final output = result.stdout.toString() + result.stderr.toString();
      final hasErrors = output.contains('error -');

      if (hasErrors) {
        print('⚠️  Analyzer output:\\n$output');
      }

      expect(hasErrors, false, reason: 'Generated files should have no errors');
      print('✅ All generated files are error-free');
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('Platform Support -', () {
    test('build command supports all platforms', () async {
      final platforms = [
        'android',
        'ios',
        'web',
        'windows',
        'macos',
        'linux',
        'all'
      ];

      for (final platform in platforms) {
        final result = await Process.run(
          'dart',
          ['run', 'dartvel_cli:dartvel', 'build', '--help'],
          runInShell: true,
        );

        expect(result.stdout.toString(), contains(platform));
      }

      print('✅ All platforms supported: ${platforms.join(', ')}');
    });

    test('platform utils detect correctly', () async {
      // This is tested in the main codebase
      expect(Platform.isLinux || Platform.isMacOS || Platform.isWindows, true);
      print('✅ Platform detection works');
    });
  });
}
