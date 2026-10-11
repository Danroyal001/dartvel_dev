// dartvel.push where the client is generated: the runtime starts the push
// provider for the declared targets and for nothing else.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_core/dartvel.dart' show dvWebPushBase64Encode;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

final String key = dvWebPushBase64Encode(<int>[4, ...List<int>.filled(64, 3)]);

void main() {
  final List<Directory> made = <Directory>[];
  tearDown(() {
    for (final Directory directory in made) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    made.clear();
  });

  Future<String> runtime(String dartvelSection) async {
    final Directory directory =
        Directory.systemTemp.createTempSync('dv_push_generation_');
    made.add(directory);
    File(p.join(directory.path, 'lib', 'pages', 'index.page.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_indexPage);
    File(p.join(directory.path, 'pubspec.yaml')).writeAsStringSync('''
name: push_probe
version: 1.0.0
environment:
  sdk: ^3.13.0
dartvel:
$dartvelSection
''');
    await routes.generate(root_: directory.path);
    return File(p.join(
            directory.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
        .readAsStringSync();
  }

  test('no push declared: the runtime never mentions push', () async {
    final String source = await runtime('  pwa:\n    name: Probe');
    expect(source, isNot(contains('startDartvelPush')));
    expect(source, isNot(contains('DVDevicePushProvider')));
  });

  test('web and android declared: the runtime starts the provider after the bindings',
      () async {
    final String source = await runtime('''
  push:
    web:
      vapidPublicKey: $key
    android:
      fcm:
        projectId: probe
        appId: "1:1:android:a"
        apiKey: AIzaKey
        senderId: "1"
''');
    expect(source, contains('startDartvelPush();'));
    expect(source, contains('void startDartvelPush() {'));
    expect(source, contains("vapidPublicKey: '$key'"));
    expect(source, contains('PushNotifications, DVDevicePushProvider'));
    // Registered bindings first: the provider polls only a queue that exists.
    expect(source.indexOf('  registerPlatformBindings();'),
        lessThan(source.indexOf('  startDartvelPush();')));
  });

  test('a declaration the build would refuse leaves the runtime without push',
      () async {
    final String source = await runtime('  push:\n    web: true');
    expect(source, isNot(contains('startDartvelPush')));
  });
}
