import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `dartvel create` and `dartvel init` are one command: in a folder with a
/// project that Dartvel did not make, both adopt it (plan first, nothing
/// overwritten) instead of one adopting and the other refusing.
void main() {
  test('create in an existing Flutter project adopts it, keeping its files',
      () async {
    final Directory project = Directory.systemTemp.createTempSync('dartvel_create_is_init_');
    addTearDown(() => project.deleteSync(recursive: true));
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: existing_app
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(project.path, 'README.md')).writeAsStringSync('# Ours\n');
    File(p.join(project.path, 'lib', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
        p.join(Directory.current.path, 'bin', 'dartvel.dart'),
        'create',
        '--yes',
      ],
      workingDirectory: project.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}', isNot(contains('refusing to scaffold')));
    expect(File(p.join(project.path, 'pubspec.yaml')).readAsStringSync(), contains('dartvel:'));
    expect(File(p.join(project.path, 'README.md')).readAsStringSync(), '# Ours\n');
    expect(File(p.join(project.path, 'lib', 'main.dart')).readAsStringSync(), 'void main() {}\n');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
