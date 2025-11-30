import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

void main() {
  group('Full Lifecycle E2E', () {
    late Directory tempDir;
    late String projectPath;

    late String dartvelBin;

    setUpAll(() async {
      // Create temp directory for test project
      tempDir = await Directory.systemTemp.createTemp('dartvel_e2e_');
      projectPath = p.join(tempDir.path, 'test_app');

      // Resolve path to dartvel executable
      final currentDir = Directory.current;
      dartvelBin = p.join(
          currentDir.path, 'packages', 'dartvel_cli', 'bin', 'dartvel.dart');

      print('E2E Test: Created temp directory at ${tempDir.path}');
      print('E2E Test: Using dartvel binary at $dartvelBin');
    });

    tearDownAll(() async {
      // Clean up
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Create new project', () async {
      // Run dartvel init
      final result = await Process.run(
        'dart',
        [dartvelBin, 'init', 'test_app'],
        workingDirectory: tempDir.path,
      );

      print('Init stdout: ${result.stdout}');
      print('Init stderr: ${result.stderr}');
      print('Exit code: ${result.exitCode}');

      expect(result.exitCode, 0,
          reason: 'dartvel init should succeed. Stderr: ${result.stderr}');
      expect(await Directory(projectPath).exists(), true,
          reason: 'Project directory should be created');

      // Patch pubspec.yaml to use local path dependencies
      final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
      var content = await pubspec.readAsString();

      final packagesDir = p.join(Directory.current.path, 'packages');

      content = content.replaceAll(
        'dartvel_core: ^0.1.0',
        'dartvel_core:\n    path: ${p.join(packagesDir, 'dartvel_core')}',
      );
      content = content.replaceAll(
        'dartvel_flutter: ^0.1.0',
        'dartvel_flutter:\n    path: ${p.join(packagesDir, 'dartvel_flutter')}',
      );
      content = content.replaceAll(
        'dartvel_shelf: ^0.1.0',
        'dartvel_shelf:\n    path: ${p.join(packagesDir, 'dartvel_shelf')}',
      );
      content = content.replaceAll(
        'dartvel_generator: ^1.0.0',
        'dartvel_generator:\n    path: ${p.join(packagesDir, 'dartvel_generator')}',
      );
      content = content.replaceAll(
        'dartvel_cli: ^0.1.0',
        'dartvel_cli:\n    path: ${p.join(packagesDir, 'dartvel_cli')}',
      );

      await pubspec.writeAsString(content);

      // Run pub get again
      await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: projectPath,
      );
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Project has correct structure', () async {
      final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
      final libDir = Directory(p.join(projectPath, 'lib'));

      expect(await pubspecFile.exists(), true,
          reason: 'pubspec.yaml should exist');
      expect(await libDir.exists(), true, reason: 'lib directory should exist');
    });

    test('Run dartvel doctor', () async {
      final result = await Process.run(
        'dart',
        ['run', 'dartvel_cli', 'doctor'],
        workingDirectory: projectPath,
      );

      print('Doctor stdout: ${result.stdout}');
      print('Doctor stderr: ${result.stderr}');

      expect(result.exitCode, 0, reason: 'dartvel doctor should pass');
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('Build web app', () async {
      // Run build_runner first to generate router.g.dart
      print('Running build_runner...');
      final buildRunnerResult = await Process.run(
        'dart',
        ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
        workingDirectory: projectPath,
      );

      if (buildRunnerResult.exitCode != 0) {
        print('build_runner stdout: ${buildRunnerResult.stdout}');
        print('build_runner stderr: ${buildRunnerResult.stderr}');
      }
      expect(buildRunnerResult.exitCode, 0,
          reason: 'build_runner should succeed');

      final result = await Process.run(
        'flutter',
        ['build', 'web', '--release'],
        workingDirectory: projectPath,
      );

      print(
          'Build stdout (last 500 chars): ${result.stdout.toString().substring(result.stdout.toString().length > 500 ? result.stdout.toString().length - 500 : 0)}');
      print('Build stderr: ${result.stderr}');

      if (result.exitCode != 0) {
        print('Flutter build web failed:');
        print('Stdout: ${result.stdout}');
        print('Stderr: ${result.stderr}');
      }
      expect(result.exitCode, 0, reason: 'flutter build web should succeed');

      final buildDir = Directory(p.join(projectPath, 'build', 'web'));
      expect(await buildDir.exists(), true,
          reason: 'build/web directory should exist');
    }, timeout: Timeout(Duration(minutes: 5)));

    test('Start server and make request', () async {
      // Start dev server
      final serverProcess = await Process.start(
        'dart',
        [dartvelBin, 'preview', '--port', '8765'],
        workingDirectory: projectPath,
      );

      // Wait for server to start
      await Future.delayed(Duration(seconds: 5));

      try {
        // Make HTTP request
        final response = await http.get(Uri.parse('http://localhost:8765/'));

        expect(response.statusCode, 200,
            reason: 'Server should respond with 200');
        expect(response.body.contains('Dartvel'), true,
            reason: 'Response should contain Dartvel');
      } finally {
        // Clean up
        serverProcess.kill();
        await serverProcess.exitCode;
      }
    }, timeout: Timeout(Duration(minutes: 1)));
  });
}
