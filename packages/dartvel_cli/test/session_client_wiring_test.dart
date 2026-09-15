// The generated runtime handing DV.Auth to the application's own backend.
//
// The client signs in, seals the token and restores it, and none of that
// matters unless the generated runtime builds it: a runtime that never
// installed it leaves DV.Auth with no provider, and one that never handed the
// token to DartvelClient.setAuthToken signs a person in while every generated
// call still goes out anonymous -- a 401 from each route, blamed on the route.
// The behaviour is tested in dartvel_flutter; the whole generated client
// compiling is tested by generated_client_analyzes_test. This pins the three
// connections only the runtime can make.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _runtime() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_session_wiring_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget homePage(BuildContext context) => const SizedBox.shrink();
''');

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shop_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Shop',
    seoTitle: 'Shop',
    seoDesc: 'Shop',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap.wrap(const <String, Object?>{}),
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  test('the runtime installs the session client over the application backend '
      'and makes it DV.Auth\'s default provider', () async {
    final String runtime = await _runtime();
    expect(runtime, contains('api: DartvelRuntime.api,'));
    expect(runtime, contains('DVSessionClient.install(dartvelSessions);'));
    expect(runtime,
        contains('DVAuth.installDefaultProvider(DVSessionAuthProvider(dartvelSessions));'));
  });

  test('the session token reaches every generated call', () async {
    final String runtime = await _runtime();
    expect(runtime, contains("import 'functions.g.dart' show DartvelClient;"));
    expect(runtime,
        contains("onToken: (String? token) => DartvelClient.setAuthToken(token ?? ''),"));
  });

  test('a native token is sealed under the key dartvel key manages, and a '
      'browser keeps none', () async {
    final String runtime = await _runtime();
    expect(runtime,
        contains("tokens: kIsWeb ? null : dvSessionTokenStoreFor('shop_app'),"));
    expect(runtime, contains("dvAppKeyStoreFor('shop_app')"));
  });
}
