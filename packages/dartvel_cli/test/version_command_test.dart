import 'dart:io';

import 'package:dartvel_cli/src/commands/version_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('readDartvelCliVersion', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel_version_');
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('reads version from nearest dartvel_cli pubspec', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: dartvel_cli
version: 9.8.7
''');
      Directory(p.join(root.path, 'bin')).createSync();
      expect(
        readDartvelCliVersion(from: Directory(p.join(root.path, 'bin'))),
        '9.8.7',
      );
    });

    test('ignores non-cli pubspec files while walking upward', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: dartvel_cli
version: 1.2.3
''');
      final nested = Directory(p.join(root.path, 'example'));
      nested.createSync();
      File(p.join(nested.path, 'pubspec.yaml')).writeAsStringSync('''
name: example_app
version: 0.0.1
''');
      expect(readDartvelCliVersion(from: nested), '1.2.3');
    });
  });
}
