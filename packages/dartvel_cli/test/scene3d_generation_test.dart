// dartvel.scene3d.enabled installs the Flutter Scene renderer, or the setting
// is decoration and every scene shows its poster. The import is asserted with
// the call: emitting one without the other is a generated file that does not
// compile.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

/// A project whose pubspec carries [scene3d] under `dartvel:`.
Future<String> runtimeFor(String scene3d) async {
  final Directory root = Directory.systemTemp.createTempSync('dv_scene3d_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
dartvel:
  pagesDir: lib/pages
$scene3d
''');
  final File page = File(p.join(root.path, 'lib', 'pages', 'index.page.dart'));
  page.parent.createSync(recursive: true);
  page.writeAsStringSync(_page);

  final YamlMap dv = loadYaml(
    File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
  )['dartvel'] as YamlMap;

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'app',
    buildId: 'test',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'app',
    seoTitle: 'app',
    seoDesc: 'app',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'none',
    durationMs: 200,
    curve: 'linear',
    normalizeTrailing: true,
    notFoundRedirect: '/',
    plugins: const <String>[],
    ota: false,
    dv: dv,
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  test('a project without scene3d neither imports nor installs the renderer', () async {
    final String runtime = await runtimeFor('');
    expect(runtime, isNot(contains('dartvel_scene')));
    expect(runtime, isNot(contains('DVFlutterScene')));
  });

  test('scene3d.enabled: false is the same as leaving it out', () async {
    final String runtime = await runtimeFor('  scene3d:\n    enabled: false');
    expect(runtime, isNot(contains('DVFlutterScene')));
  });

  test('scene3d.enabled: true installs Flutter Scene while configuring the runtime, with its import', () async {
    final String runtime = await runtimeFor('  scene3d:\n    enabled: true');
    expect(runtime, contains("import 'package:dartvel_scene/dartvel_scene.dart' show DVFlutterScene;"));
    final int configure = runtime.indexOf('void configureDartvelRuntime(');
    final int install = runtime.indexOf('DVFlutterScene.install();');
    expect(configure, greaterThan(-1));
    expect(install, greaterThan(configure));
  });
}
