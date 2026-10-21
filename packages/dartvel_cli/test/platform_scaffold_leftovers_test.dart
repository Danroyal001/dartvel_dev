// The ephemeral native folder, and nothing else.
//
// `flutter create --platforms=linux .` in an existing project also writes a
// counter-app test/widget_test.dart (whose MyApp does not exist, so the
// project's own analysis fails) and a .metadata file. A build that generates
// linux/ must leave the project as it found it apart from linux/.
import 'dart:io';

import 'package:dartvel_cli/src/build/platform_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv-scaffold-');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: desk\n');
    File(p.join(root.path, 'test', 'desk_test.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// mine');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> fakeFlutterCreate(String executable, List<String> arguments,
      {String? workingDirectory, bool runInShell = true}) async {
    File(p.join(root.path, 'linux', 'CMakeLists.txt')).createSync(recursive: true);
    File(p.join(root.path, 'test', 'widget_test.dart')).writeAsStringSync('MyApp');
    File(p.join(root.path, '.metadata')).writeAsStringSync('version');
    return ProcessResult(1, 0, '', '');
  }

  test('keeps the platform folder and removes what flutter create added besides', () async {
    final bool ok = await dvEnsurePlatformScaffold(
        root: root.path, platform: 'linux', processRun: fakeFlutterCreate);
    expect(ok, isTrue);
    expect(File(p.join(root.path, 'linux', 'CMakeLists.txt')).existsSync(), isTrue);
    expect(File(p.join(root.path, 'test', 'widget_test.dart')).existsSync(), isFalse);
    expect(File(p.join(root.path, '.metadata')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'test', 'desk_test.dart')).readAsStringSync(), '// mine');
  });

  test('a widget_test.dart the project already had is its own, and stays', () async {
    File(p.join(root.path, 'test', 'widget_test.dart')).writeAsStringSync('// mine too');
    await dvEnsurePlatformScaffold(root: root.path, platform: 'linux', processRun:
        (String executable, List<String> arguments, {String? workingDirectory, bool runInShell = true}) async {
      File(p.join(root.path, 'linux', 'CMakeLists.txt')).createSync(recursive: true);
      return ProcessResult(1, 0, '', '');
    });
    expect(File(p.join(root.path, 'test', 'widget_test.dart')).readAsStringSync(), '// mine too');
  });
}
