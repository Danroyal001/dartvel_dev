// dartvel build refuses a module whose declaration puts a real operation
// where nothing can carry it -- DV-BIND-005 when the binding kind cannot
// exist on the target, DV-BIND-007 when no carrier is built -- for the
// platforms being built and no others. A declaration the build can see
// is wrong should never reach a device and fail on the first call.
import 'dart:io';

import 'package:dartvel_cli/src/build/binding_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String project(String moduleBlock) {
  final Directory root = Directory.systemTemp.createTempSync('dv_bindcheck_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    vendor:
      source: { path: modules/dv_vendor_module }
      mount: /vendor
''');
  File(p.join(root.path, 'modules', 'dv_vendor_module', 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('name: dv_vendor_module\n'
        'dartvel:\n  module:\n    id: vendor\n$moduleBlock');
  return root.path;
}

void main() {
  test('an npm module declared for Android fails the Android build with '
      'DV-BIND-007 and leaves the web build alone', () {
    final String root = project('''
    kind: npm
    surface: VendorModule
    targets: [android]
    operations:
      slugify:
        native: real
        web: real
        backend: real
''');
    final DVBindingCheck android = DVBindingCheck.run(root, <String>['android']);
    expect(android.ok, isFalse);
    expect(android.lines.single,
        allOf(contains('DV-BIND-007'), contains('vendor'), contains('android')));
    expect(DVBindingCheck.run(root, <String>['web']).ok, isTrue);
    expect(DVBindingCheck.run(root, <String>['server']).ok, isTrue);
  });

  test('a JVM operation declared real in the browser fails the web build '
      'with DV-BIND-005, and only that build', () {
    final String root = project('''
    kind: jvm
    surface: VendorModule
    targets: [android]
    operations:
      scan:
        native: real
        web: real
        backend: unavailable
''');
    final DVBindingCheck web = DVBindingCheck.run(root, <String>['web']);
    expect(web.lines.single, contains('DV-BIND-005'));
    expect(DVBindingCheck.run(root, <String>['android']).ok, isTrue);
    // iOS is not a declared target: a call from there is DV-MODULE-014,
    // which the module call check reports, not a binding problem.
    expect(DVBindingCheck.run(root, <String>['ios']).ok, isTrue);
  });

  test('a JVM operation declared real on the backend fails the server build',
      () {
    final String root = project('''
    kind: jvm
    surface: VendorModule
    targets: [android]
    operations:
      scan:
        native: real
        web: unavailable
        backend: real
''');
    expect(DVBindingCheck.run(root, <String>['server']).lines.single,
        contains('DV-BIND-007'));
  });

  test('a module the matrix carries everywhere passes every build', () {
    final String root = project('''
    kind: ffi
    surface: VendorModule
    operations:
      crc32:
        native: real
        web: real
        backend: real
''');
    expect(
        DVBindingCheck.run(root,
            <String>['android', 'ios', 'linux', 'macos', 'windows', 'web', 'server']).ok,
        isTrue);
  });
}
