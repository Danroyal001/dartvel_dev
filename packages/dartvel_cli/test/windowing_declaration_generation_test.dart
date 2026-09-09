// The three windowing settings reach the runtime, or they are decoration.
//
// `windowing.web.inPageViews`, `windowing.web.openInNewWindow` and
// `windowing.android.freeform` are in the specification and the build read
// none of them. The capability hard-coded what each platform can do, so a
// project that wrote `openInNewWindow: false` still reported multiWindow on
// web, still offered the control, and still opened a browser window.
//
// The import is asserted alongside the call because this generator has
// produced a file naming a type it did not import before: the condition for
// emitting the code and the condition for emitting its import were written
// twice and drifted.
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

/// A project whose pubspec carries [windowing] under `dartvel:`.
Future<String> runtimeFor(String windowing) async {
  final Directory root = Directory.systemTemp.createTempSync('dv_windowing_');
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
dartvel:
  pagesDir: lib/pages
$windowing
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
    webPrerender: false,
    ota: false,
    dv: dv,
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  test('a project that declares nothing gets no declaration', () async {
    final String runtime = await runtimeFor('');
    expect(runtime, isNot(contains('useWindowingDeclaration')));
    // And does not import a type it never names.
    expect(runtime, isNot(contains('DVWindowingDeclaration')));
  });

  test('openInNewWindow: false reaches the runtime, with its import',
      () async {
    final String runtime = await runtimeFor('''
  windowing:
    web:
      openInNewWindow: false
''');
    expect(runtime, contains('useWindowingDeclaration'));
    expect(runtime, contains('webOpenInNewWindow: false'));
    expect(runtime, contains('DVWindowingDeclaration'));
  });

  test('all three travel together', () async {
    final String runtime = await runtimeFor('''
  windowing:
    web:
      inPageViews: false
      openInNewWindow: true
    android:
      freeform: false
''');
    expect(runtime, contains('webInPageViews: false'));
    expect(runtime, contains('webOpenInNewWindow: true'));
    expect(runtime, contains('androidFreeform: false'));
  });

  // `auto` is the documented default and means the platform decides, which is
  // what declaring nothing already does. Emitting a third state nothing reads
  // would be worse than emitting none.
  test('freeform: auto emits nothing', () async {
    final String runtime = await runtimeFor('''
  windowing:
    android:
      freeform: auto
''');
    expect(runtime, isNot(contains('androidFreeform')));
  });
}
