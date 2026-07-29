import 'dart:io';

import 'package:dartvel_cli/src/utils/build_runner.dart';
import 'package:test/test.dart';

void main() {
  test('detects build_runner in declared dependency sections', () {
    final directory = Directory.systemTemp.createTempSync('dartvel_build_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: sample
dev_dependencies:
  build_runner: ^2.0.0
''');

    expect(hasBuildRunnerDependency(directory.path), isTrue);
    expect(hasPubDependency(directory.path, 'build_runner'), isTrue);
  });

  test('does not enable build_runner when it is not declared', () {
    final directory = Directory.systemTemp.createTempSync('dartvel_build_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: sample
dependencies:
  flutter:
    sdk: flutter
''');

    expect(hasBuildRunnerDependency(directory.path), isFalse);
    expect(hasPubDependency(directory.path, 'build_runner'), isFalse);
  });

  test('detects arbitrary package dependencies', () {
    final directory = Directory.systemTemp.createTempSync('dartvel_build_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: sample
dependencies:
  flutter_vscode: ^0.0.1
''');

    expect(hasPubDependency(directory.path, 'flutter_vscode'), isTrue);
  });
}
