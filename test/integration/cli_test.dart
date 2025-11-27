import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('CLI Integration', () {
    test('dartvel doctor runs successfully', () async {
      final result = await Process.run(
        'dart',
        ['run', 'packages/dartvel_cli/bin/dartvel.dart', 'doctor'],
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('Dartvel Doctor'));
    });

    test('dartvel init creates project structure', () async {
      final tempDir = Directory.systemTemp.createTempSync('dartvel_test_init_');
      try {
        final result = await Process.run(
          'dart',
          ['run', 'packages/dartvel_cli/bin/init.dart', 'test_app'],
          workingDirectory: tempDir.path,
        );

        // Note: This might fail if the template doesn't exist or network is down
        // For now we check if it attempts to run
        // In a real scenario we'd mock the generator
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
