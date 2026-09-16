// The generated runtime names its own backend's origin for credentials in a
// browser.
//
// What naming an origin does -- and refuses -- is dartvel_core's
// http_credentialed_origins_test. The runtime is a Flutter library, which a VM
// test cannot run, so this pins the one thing that test cannot: that a web
// build calls it with the backend URL every generated call is sent to, before
// the session client makes its first request. Without the call a web build on
// another origin than its API is signed out on every request, and nothing
// fails: the calls answer 401 and look like an expired session.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String runtime;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dv_web_credentials_');
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: web_credentials_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
  prodBackendHost: https://api.example.com
''');
    final File page = File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'));
    page.parent.createSync(recursive: true);
    page.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
    await routes.generate(root_: dir.path);
    runtime = File(p.join(dir.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
        .readAsStringSync();
  });

  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a web build names the backend it calls, and only on the web', () {
    expect(runtime, contains('DVCredentialedOrigins'));
    expect(
      runtime,
      contains('if (kIsWeb) {\n'
          '    final String? credentials = '
          'DVCredentialedOrigins.allowBackend(DartvelRuntime.baseUrl);'),
    );
  });

  test('before the session client is made', () {
    final int named = runtime.indexOf('DVCredentialedOrigins.allowBackend(');
    final int sessions = runtime.indexOf('DVSessionClient(');
    expect(named, isNonNegative);
    expect(named, lessThan(sessions));
  });
}
