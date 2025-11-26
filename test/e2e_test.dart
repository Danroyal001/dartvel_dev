import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('Real End-to-End Tests', () {
    test('generated router file exists and is valid', () {
      final routerFile = File('examples/dartvel_example/lib/dartvel_client/router.g.dart');
      
      expect(routerFile.existsSync(), isTrue, 
        reason: 'Router file should exist after generation');
      
      final content = routerFile.readAsStringSync();
      
      // Verify key components
      expect(content.contains('createDartvelRouter'), isTrue,
        reason: 'Should export router factory');
      expect(content.contains('GoRouter'), isTrue,
        reason: 'Should use GoRouter');
      expect(content.contains('GoRoute'), isTrue,
        reason: 'Should define routes');
      expect(content.contains('DartvelRouteState'), isTrue,
        reason: 'Should use Dartvel state management');
      expect(content.contains('DvDataLoader'), isTrue,
        reason: 'Should include data loader');
      
      // Verify no syntax errors (basic check)
      expect(content.contains('GENERATED'), isTrue,
        reason: 'Should be marked as generated');
      expect(content.split('\n').length, greaterThan(100),
        reason: 'Should be substantial (100+ lines)');
      
      print('✅ Router file validated: ${content.split('\n').length} lines');
    });

    test('generated functions file exists and has API client', () {
      final functionsFile = File('examples/dartvel_example/lib/dartvel_client/functions.g.dart');
      
      expect(functionsFile.existsSync(), isTrue,
        reason: 'Functions file should exist');
      
      final content = functionsFile.readAsStringSync();
      
      // Verify API client structure
      expect(content.contains('class DartvelApi'), isTrue,
        reason: 'Should define API client class');
      expect(content.contains('Future<'), isTrue,
        reason: 'Should have async methods');
      
      final lineCount = content.split('\n').length;
      expect(lineCount, greaterThan(500),
        reason: 'Should be comprehensive (500+ lines)');
      
      print('✅ Functions file validated: $lineCount lines');
    });

    test('generated env file has obfuscated variables', () {
      final envFile = File('examples/dartvel_example/lib/dartvel_client/env.g.dart');
      
      expect(envFile.existsSync(), isTrue,
        reason: 'Env file should exist');
      
      final content = envFile.readAsStringSync();
      
      // Verify obfuscation
      expect(content.contains('class Env'), isTrue,
        reason: 'Should define Env class');
      expect(content.contains('_d('), isTrue,
        reason: 'Should have deobfuscation function');
      expect(content.contains('static String get PUBLIC_'), isTrue,
        reason: 'Should export PUBLIC_ variables');
      
      // Verify actual obfuscation (XOR)
      final hasXorPattern = RegExp(r'x \^ k').hasMatch(content);
      expect(hasXorPattern, isTrue,
        reason: 'Should use XOR obfuscation');
      
      print('✅ Env file validated with XOR obfuscation');
    });

    test('backend routes file exists and is valid', () {
      final backendFile = File('examples/dartvel_example/.dart_tool/dartvel_backend_routes.g.dart');
      
      expect(backendFile.existsSync(), isTrue,
        reason: 'Backend routes should be generated');
      
      final content = backendFile.readAsStringSync();
      
      // Verify backend structure
      expect(content.contains('buildBackendRouter'), isTrue,
        reason: 'Should export router builder');
      expect(content.contains('router.get'), isTrue,
        reason: 'Should have GET routes');
      
      final lineCount = content.split('\n').length;
      expect(lineCount, greaterThan(700),
        reason: 'Should be substantial (700+ lines)');
      
      print('✅ Backend file validated: $lineCount lines');
    });

    test('all generated files pass dart analyzer', () async {
      final files = [
        'examples/dartvel_example/lib/dartvel_client/router.g.dart',
        'examples/dartvel_example/lib/dartvel_client/functions.g.dart',
        'examples/dartvel_example/lib/dartvel_client/env.g.dart',
      ];

      for (final filePath in files) {
        final result = await Process.run(
          'dart',
          ['analyze', filePath],
        );

        expect(result.exitCode, equals(0),
          reason: '$filePath should have no analyzer errors');
        
        print('✅ Analyzed: ${p.basename(filePath)} - PASSED');
      }
    }, timeout: Timeout(Duration(seconds: 30)));

    test('project structure is correct', () {
      final requiredDirs = [
        'examples/dartvel_example/lib/pages',
        'examples/dartvel_example/lib/backend/functions',
        'examples/dartvel_example/lib/dartvel_client',
        'examples/dartvel_example/.dart_tool',
      ];

      for (final dir in requiredDirs) {
        expect(Directory(dir).existsSync(), isTrue,
          reason: '$dir should exist');
      }

      print('✅ Project structure validated');
    });

    test('pubspec.yaml has dartvel configuration', () {
      final pubspec = File('examples/dartvel_example/pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);

      final content = pubspec.readAsStringSync();
      
      final requiredKeys = [
        'dartvel:',
        'backendHost:',
        'backendPort:',
        'pagesDir:',
        'backendDir:',
        'apiBasePath:',
      ];

      for (final key in requiredKeys) {
        expect(content.contains(key), isTrue,
          reason: 'Should have $key in config');
      }

      print('✅ Config validated');
    });

    test('environment variables are properly excluded', () {
      final envFile = File('examples/dartvel_example/lib/dartvel_client/env.g.dart');
      final content = envFile.readAsStringSync();

      // PUBLIC_ should be included
      expect(content.contains('PUBLIC_GREETING'), isTrue,
        reason: 'PUBLIC_ vars should be exposed');

      // Non-PUBLIC vars should NOT be in client code
      expect(content.contains('SECRET_'), isFalse,
        reason: 'SECRET_ vars should not be exposed to client');
      expect(content.contains('DATABASE_'), isFalse,
        reason: 'DATABASE_ vars should not be exposed to client');

      print('✅ Environment security validated');
    });

    test('generated code has no hardcoded secrets', () {
      final files = [
        'examples/dartvel_example/lib/dartvel_client/router.g.dart',
        'examples/dartvel_example/lib/dartvel_client/functions.g.dart',
      ];

      for (final filePath in files) {
        final content = File(filePath).readAsStringSync();

        // Check for common secret patterns
        expect(content.contains(RegExp(r'password\s*=\s*["\']')), isFalse,
          reason: 'Should not contain hardcoded passwords');
        expect(content.contains(RegExp(r'apiKey\s*=\s*["\']')), isFalse,
          reason: 'Should not contain hardcoded API keys');
        expect(content.contains(RegExp(r'secret\s*=\s*["\']')), isFalse,
          reason: 'Should not contain hardcoded secrets');
      }

      print('✅ Security scan passed - no hardcoded secrets');
    });
  });

  group('Code Quality Tests', () {
    test('generated code follows naming conventions', () {
      final routerFile = File('examples/dartvel_example/lib/dartvel_client/router.g.dart');
      final content = routerFile.readAsStringSync();

      // Check for proper naming
      expect(content.contains(RegExp(r'createDartvelRouter\(\)')), isTrue,
        reason: 'Function names should be camelCase');
      expect(content.contains(RegExp(r'class \w+Page')), isTrue,
        reason: 'Classes should be PascalCase');

      print('✅ Naming conventions validated');
    });

    test('generated code has proper imports', () {
      final routerFile = File('examples/dartvel_example/lib/dartvel_client/router.g.dart');
      final content = routerFile.readAsStringSync();

      expect(content.contains("import 'package:flutter/material.dart';"), isTrue);
      expect(content.contains("import 'package:go_router/go_router.dart';"), isTrue);
      expect(content.contains("import 'package:dartvel_flutter/dartvel_flutter.dart';"), isTrue);

      print('✅ Imports validated');
    });

    test('total lines of generated code is reasonable', () async {
      final result = await Process.run(
        'wc',
        ['-l', 'lib/dartvel_client/*.dart', '.dart_tool/dartvel_backend_routes.g.dart'],
        workingDirectory: 'examples/dartvel_example',
      );

      final output = result.stdout.toString();
      print('Generated code statistics:\n$output');

      // Parse total
      final lines = output.split('\n');
      final totalLine = lines.lastWhere((l) => l.contains('total'), orElse: () => '0 total');
      final total = int.tryParse(totalLine.trim().split(' ').first) ?? 0;

      expect(total, greaterThan(1500), reason: 'Should generate substantial code');
      expect(total, lessThan(5000), reason: 'Should not be excessively large');

      print('✅ Code size is reasonable: $total lines total');
    });
  });
}
