import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/devclient/dev_client_project.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_plugin_free_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: example
dependencies:
  dartvel_flutter: any
''');
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  dartvel_flutter:
    version: "0.13.13"
''');
    File('${root.path}/runtime/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: dartvel_flutter\n');
    File('${root.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'example', 'rootUri': '../'},
          {'name': 'dartvel_flutter', 'rootUri': '../runtime/'},
        ],
      }));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a resolved plugin-free app builds a development manifest', () {
    final manifest = dvProjectDevClientManifest(root.path, 'android');
    expect(manifest.bindings, ['dartvel_flutter@0.13.13']);
    expect(manifest.target, 'android');
  });

  test('missing Flutter plugin metadata with a plugin still refuses', () {
    File('${root.path}/runtime/pubspec.yaml').writeAsStringSync('''
name: dartvel_flutter
flutter:
  plugin:
    platforms:
      android:
        package: dev.example
        pluginClass: NativePlugin
''');
    expect(
      () => dvProjectDevClientManifest(root.path, 'android'),
      throwsA(isA<DVDevClientProjectException>()),
    );
  });

  test('an unresolved new dependency cannot masquerade as plugin-free', () {
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: example
dependencies:
  dartvel_flutter: any
  camera: any
''');
    expect(
      () => dvProjectDevClientManifest(root.path, 'android'),
      throwsA(isA<DVDevClientProjectException>()),
    );
  });

  test('an unreadable package is not evidence of zero plugins', () {
    File('${root.path}/runtime/pubspec.yaml').deleteSync();
    expect(
      () => dvProjectDevClientManifest(root.path, 'android'),
      throwsA(isA<DVDevClientProjectException>()),
    );
  });

  test('without a resolved graph the existing refusal remains', () {
    File('${root.path}/.dart_tool/package_config.json').deleteSync();
    expect(
      () => dvProjectDevClientManifest(root.path, 'android'),
      throwsA(isA<DVDevClientProjectException>()),
    );
  });
}
