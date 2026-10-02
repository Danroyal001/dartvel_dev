// dartvel.fileStorage reaches the runtime the generator writes.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

Directory project(String section) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_file_storage_config_');
  File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_indexPage);
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: file_storage_probe
version: 1.0.0
environment:
  sdk: ^3.13.0
dartvel:
$section
''');
  return dir;
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDown(() {
    for (final Directory dir in made) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    made.clear();
  });

  File runtimeFile(Directory dir) => File(p.join(dir.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'));

  test('the runtime declares DV.Platform.fileStorage with what pubspec says', () async {
    final Directory dir = project(
        '  fileStorage:\n    access: [photos, documents]\n    reason: Attach receipts.\n    shareAppFiles: true');
    made.add(dir);
    await routes.generate(root_: dir.path);
    final String runtime = runtimeFile(dir).readAsStringSync();
    expect(runtime, contains('DVDeviceStorage.declare('));
    // Named in the runtime's imports: the runtime shows only what it uses,
    // and a name it calls without importing fails the app's compile, not this.
    expect(RegExp(r"import 'package:dartvel_core/dartvel.dart' show [^;]*\bDVFileStorageConfig\b").hasMatch(runtime), isTrue);
    expect(RegExp(r"import 'package:dartvel_flutter/dartvel_flutter.dart' show [^;]*\bDVDeviceStorage\b").hasMatch(runtime), isTrue);
    expect(runtime, contains("appId: 'file_storage_probe'"));
    expect(runtime, contains("'photos'"));
    expect(runtime, contains("'documents'"));
    expect(runtime, contains("'Attach receipts.'"));
    expect(runtime, contains("'shareAppFiles': true"));
    // After the bindings: on Android the directory is the one they found.
    expect(runtime.indexOf('DVDeviceStorage.declare('), greaterThan(runtime.indexOf('registerPlatformBindings();')));
  });

  test('no section declares the app directory and nothing else', () async {
    final Directory dir = project('  crashes:\n    enabled: true');
    made.add(dir);
    await routes.generate(root_: dir.path);
    expect(runtimeFile(dir).readAsStringSync(), contains('DVFileStorageConfig.parse(<String, Object?>{})'));
  });

  test('a mistake refuses generation, naming the key, and leaves no runtime', () async {
    final Directory dir = project('  fileStorage:\n    access: [videos]');
    made.add(dir);
    await expectLater(
      routes.generate(root_: dir.path),
      throwsA(predicate((Object error) => '$error'.contains('"videos"'), 'names the kind')),
    );
    expect(runtimeFile(dir).existsSync(), isFalse);
  });
}
