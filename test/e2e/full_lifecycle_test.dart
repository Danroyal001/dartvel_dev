import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  group('Full Lifecycle E2E', () {
    late Directory tempDir;
    late String projectPath;
    late String dartvelBin;
    bool hasFlutter = false;

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

      final flutterCheck = await Process.run('which', ['flutter'])
          .catchError((_) => ProcessResult(-1, 1, '', ''));
      hasFlutter = flutterCheck.exitCode == 0;
      print('E2E Test: Flutter SDK present: $hasFlutter');
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
        'dartvel_cli: ^0.1.0',
        'dartvel_cli:\n    path: ${p.join(packagesDir, 'dartvel_cli')}',
      );

      await pubspec.writeAsString(content);

      if (hasFlutter) {
        // Run pub get again
        await Process.run(
          'flutter',
          ['pub', 'get'],
          workingDirectory: projectPath,
        );
      } else {
        print('Skipping: flutter pub get (Flutter SDK not installed)');
      }
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
        [dartvelBin, 'doctor'],
        workingDirectory: projectPath,
      );

      print('Doctor stdout: ${result.stdout}');
      print('Doctor stderr: ${result.stderr}');

      expect(result.exitCode, 0, reason: 'dartvel doctor should pass');
    }, timeout: Timeout(Duration(seconds: 30)));

    test('Build web app', () async {
      if (!hasFlutter) {
        print('Skipping: Build web app (Flutter SDK not installed)');
        return;
      }

      // Run dartvel routes to generate router.g.dart, functions.g.dart, e.t.c.
      print('Running dartvel routes...');
      final routesResult = await Process.run(
        'dart',
        [dartvelBin, 'routes'],
        workingDirectory: projectPath,
      );

      if (routesResult.exitCode != 0) {
        print('routes stdout: ${routesResult.stdout}');
        print('routes stderr: ${routesResult.stderr}');
      }
      expect(routesResult.exitCode, 0, reason: 'dartvel routes should succeed');

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
      if (!hasFlutter) {
        print(
            'Skipping: Start server and make request (Flutter SDK not installed)');
        return;
      }

      // Start dev server
      final serverProcess = await Process.start(
        'dart',
        [dartvelBin, 'preview', '--port', '8889'],
        workingDirectory: projectPath,
      );

      serverProcess.stdout
          .transform(utf8.decoder)
          .listen((data) => print('SERVER STDOUT: $data'));
      serverProcess.stderr
          .transform(utf8.decoder)
          .listen((data) => print('SERVER STDERR: $data'));

      try {
        final uri = Uri.parse('http://127.0.0.1:8889/');
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 30; attempt++) {
          try {
            response = await http.get(uri);
            break;
          } catch (e) {
            lastError = e;
            await Future.delayed(Duration(seconds: 1));
          }
        }

        expect(response, isNotNull,
            reason: 'Server should accept connections. Last error: $lastError');

        expect(response!.statusCode, 200,
            reason: 'Server should respond with 200');
        expect(response.body.contains('test_app'), true,
            reason: 'Response should contain project name');
      } finally {
        // Clean up
        serverProcess.kill();
      }
    }, timeout: Timeout(Duration(minutes: 1)));
  });
}
