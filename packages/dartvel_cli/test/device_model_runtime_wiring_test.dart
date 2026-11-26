// A device model needs no application code: dartvel routes writes it, the
// barrel exports it, and the runtime reads it before the first frame so
// context.global<Model>() has its value from the start.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dv_device_runtime_');
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: device_probe
publish_to: none
environment:
  sdk: ^3.13.0
dartvel:
  prodBackendHost: https://example.com
''');
    File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
    File(p.join(dir.path, 'lib', 'settings', 'reading.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
// ignore_for_file: unused_element
import 'package:dartvel_core/dartvel.dart';

@DVModel(storage: DVModelStorage.device)
class const _ReadingSettings({final bool serif = false});
''');
    await routes.generate(root_: dir.path);
  });

  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String client(String name) => File(p.join(dir.path, 'lib', 'dartvel_client', name)).readAsStringSync();

  test('the device model is generated, keyed <package>.<Model>', () {
    expect(client('device_models.g.dart'), contains('class const ReadingSettings({'));
    expect(client('device_models.g.dart'), contains("storageKey = 'device_probe.ReadingSettings'"));
  });

  test('the barrel exports it', () {
    expect(client('dartvel_client.dart'), contains("export 'device_models.g.dart';"));
  });

  test('the runtime reads every device model before the first frame', () {
    final String runtime = client('dartvel_runtime.dart');
    expect(runtime, contains("import 'device_models.g.dart' show registerDartvelDeviceModels;"));
    expect(runtime, contains('registerDartvelDeviceModels();'));
  });

  test('no database model, table or page is made for it', () {
    expect(client('models.g.dart'), isNot(contains('ReadingSettings')));
  });
}
