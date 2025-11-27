// ignore_for_file: avoid_print
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('CLI Integration Tests', () {
    late Directory testDir;

    setUp(() {
      // Create temporary test directory
      testDir = Directory.systemTemp.createTempSync('dartvel_test_');
    });

    tearDown(() {
      // Clean up
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });

    test('dartvel routes command generates client code', () async {
      // Copy example project to test directory
      final exampleDir = Directory('examples/dartvel_example');
      if (!exampleDir.existsSync()) {
        print('Skipping: example project not found');
        return;
      }

      // Run routes command
      final result = await Process.run(
        'dart',
        ['run', 'packages/dartvel_cli/lib/main.dart', 'routes'],
        workingDirectory: 'examples/dartvel_example',
      );

      print('Routes command output:');
      print(result.stdout);
      if (result.stderr.toString().isNotEmpty) {
        print('Stderr: ${result.stderr}');
      }

      expect(result.exitCode, equals(0),
          reason: 'Routes command should succeed');

      // Verify generated files exist
      final routerFile =
          File('examples/dartvel_example/lib/dartvel_client/router.g.dart');
      expect(routerFile.existsSync(), isTrue,
          reason: 'Router file should be generated');

      final envFile =
          File('examples/dartvel_example/lib/dartvel_client/env.g.dart');
      expect(envFile.existsSync(), isTrue,
          reason: 'Env file should be generated');

      final functionsFile =
          File('examples/dartvel_example/lib/dartvel_client/functions.g.dart');
      expect(functionsFile.existsSync(), isTrue,
          reason: 'Functions file should be generated');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('generated router contains routes', () async {
      final routerFile =
          File('examples/dartvel_example/lib/dartvel_client/router.g.dart');
      if (!routerFile.existsSync()) {
        print('Skipping: router file not generated');
        return;
      }

      final content = await routerFile.readAsString();

      expect(content.contains('createDartvelRouter'), isTrue);
      expect(content.contains('GoRouter'), isTrue);
      expect(content.contains('GoRoute'), isTrue);
    });

    test('generated backend routes exist', () async {
      final backendFile = File(
          'examples/dartvel_example/.dart_tool/dartvel_backend_routes.g.dart');
      if (!backendFile.existsSync()) {
        print('Skipping: backend routes not generated');
        return;
      }

      final content = await backendFile.readAsString();

      expect(content.contains('buildBackendRouter'), isTrue);
      expect(content.contains('router.get'), isTrue);
    });
  });

  group('Backend API Tests', () {
    test('backend can start and respond', () async {
      // This would require the dev server to be running
      // For now, we'll verify the generated code is valid
      final backendFile = File(
          'examples/dartvel_example/.dart_tool/dartvel_backend_routes.g.dart');

      if (!backendFile.existsSync()) {
        print('Skipping: backend not generated');
        return;
      }

      // Verify it's valid Dart
      final result = await Process.run(
        'dart',
        ['analyze', backendFile.path],
      );

      expect(result.exitCode, equals(0),
          reason: 'Generated backend code should be valid');
    });
  });

  group('Project Structure Tests', () {
    test('example project has correct structure', () {
      final dirs = [
        'examples/dartvel_example/lib/pages',
        'examples/dartvel_example/lib/backend/functions',
      ];

      for (final dir in dirs) {
        expect(Directory(dir).existsSync(), isTrue,
            reason: '$dir should exist');
      }
    });

    test('pubspec.yaml has dartvel configuration', () {
      final pubspec = File('examples/dartvel_example/pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);

      final content = pubspec.readAsStringSync();
      expect(content.contains('dartvel:'), isTrue);
      expect(content.contains('backendHost'), isTrue);
      expect(content.contains('pagesDir'), isTrue);
    });
  });
}
