// A call the build can see reaching an operation declared `unavailable`
// where it is being built for is refused, and so is a call to an operation
// that declares nothing there.
//
// DV-MODULE-013 and DV-MODULE-014. The runtime still throws
// DVModuleUnavailable for a call the build could not see; this is the one it
// can, which should never reach a device.
import 'dart:io';

import 'package:dartvel_cli/src/build/module_call_check.dart';
import 'package:dartvel_core/dartvel.dart' show DVModuleEnvironment;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String project({required String page, String backend = ''}) {
  final Directory root = Directory.systemTemp.createTempSync('dv_calls_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    paths:
      source: { path: modules/dv_paths_module }
      mount: /paths
''');
  File(p.join(root.path, 'modules', 'dv_paths_module', 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: dv_paths_module
dartvel:
  module:
    id: paths
    kind: dartPackage
    surface: PathsModule
    operations:
      separator:
        native: real
        web: unavailable
        backend: real
      isBlank:
        native: real
        web: real
        backend: real
      legacy:
        native: real
        backend: real
''');
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(page);
  if (backend.isNotEmpty) {
    File(p.join(root.path, 'lib', 'backend', 'tidy.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(backend);
  }
  return root.path;
}

void main() {
  test('a page calling an operation unavailable on the web fails the web '
      'build, and only the web build', () {
    final String root = project(
        page: "final s = DV.Modules.paths.separator();\n"
            "final b = DV.Modules.paths.isBlank('x');\n");

    final DVModuleCallCheck web =
        DVModuleCallCheck.run(root, <DVModuleEnvironment>{DVModuleEnvironment.web});
    expect(web.ok, isFalse);
    expect(web.lines.join('\n'), allOf(contains('DV-MODULE-013'),
        contains('paths.separator'), contains('lib/pages/index.page.dart:1')));
    expect(web.lines.join('\n'), isNot(contains('isBlank')));

    expect(
        DVModuleCallCheck.run(root,
            <DVModuleEnvironment>{DVModuleEnvironment.native}).ok,
        isTrue);
  });

  test('an operation that says nothing about an environment is DV-MODULE-014',
      () {
    final String root = project(page: 'final l = DV.Modules.paths.legacy();\n');
    final DVModuleCallCheck web =
        DVModuleCallCheck.run(root, <DVModuleEnvironment>{DVModuleEnvironment.web});
    expect(web.ok, isFalse);
    expect(web.lines.join('\n'), contains('DV-MODULE-014'));
  });

  test('backend functions are checked as the backend', () {
    final String root = project(
      page: '',
      backend: 'final s = DV.Modules.paths.separator();\n',
    );
    expect(
        DVModuleCallCheck.run(root,
            <DVModuleEnvironment>{DVModuleEnvironment.web}).ok,
        isTrue,
        reason: 'a backend function is not in the web build');
    expect(
        DVModuleCallCheck.run(root,
            <DVModuleEnvironment>{DVModuleEnvironment.backend}).ok,
        isTrue);
  });

  test('a comment is not a call', () {
    final String root =
        project(page: '// DV.Modules.paths.separator() is not for the web\n');
    expect(
        DVModuleCallCheck.run(root,
            <DVModuleEnvironment>{DVModuleEnvironment.web}).ok,
        isTrue);
  });
}
