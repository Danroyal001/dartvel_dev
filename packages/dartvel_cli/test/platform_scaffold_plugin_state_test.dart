import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/platform_scaffold.dart';
import 'package:test/test.dart';

void main() {
  test('scaffolding keeps resolved plugin state but removes counter-app files', () async {
    final root = Directory.systemTemp.createTempSync('dv_scaffold_plugins_');
    addTearDown(() => root.deleteSync(recursive: true));
    await dvGeneratePlatformScaffold(
      root: root.path,
      directory: 'android',
      create: () async {
        File('${root.path}/android/app/build.gradle')
          ..createSync(recursive: true)
          ..writeAsStringSync('// generated platform');
        File('${root.path}/.flutter-plugins-dependencies').writeAsStringSync(
          jsonEncode({
            'plugins': {
              'android': [
                {'name': 'jni', 'native_build': true},
              ],
            },
          }),
        );
        File('${root.path}/test/widget_test.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('// unwanted counter app');
        File('${root.path}/.metadata').writeAsStringSync('generated IDE state');
        return 0;
      },
    );
    final metadata = File('${root.path}/.flutter-plugins-dependencies');
    expect(metadata.existsSync(), isTrue,
        reason: 'the development shell must know the native plugins Flutter resolved');
    final plugins = (jsonDecode(metadata.readAsStringSync()) as Map)['plugins'] as Map;
    expect((plugins['android'] as List).single['name'], 'jni');
    expect(File('${root.path}/android/app/build.gradle').existsSync(), isTrue);
    expect(File('${root.path}/test/widget_test.dart').existsSync(), isFalse);
    expect(File('${root.path}/.metadata').existsSync(), isFalse);
  });
}
