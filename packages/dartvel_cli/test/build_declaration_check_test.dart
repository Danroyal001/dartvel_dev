// What a build refuses to start.
//
// "Never start a build that cannot finish" is the toolchain rule, and it was
// read as being about tools: the host, the SDK, the embedder. A declaration
// the build cannot honour is the same thing one layer up -- a kiosk policy
// that contradicts itself, a module whose project is not where it says --
// and both were checked by `dartvel doctor` alone. A pipeline that runs
// `dartvel build` and not `dartvel doctor` shipped them, green.
import 'dart:io';

import 'package:dartvel_cli/src/build/declaration_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory project(String dartvel) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_decl_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync('name: shopfront\ndartvel:\n$dartvel');
  return root;
}

void main() {
  test('a project that declares nothing has nothing to refuse', () {
    final DVDeclarationCheck check =
        DVDeclarationCheck.run(project('  pagesDir: lib/pages\n').path);

    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('a kiosk policy that cannot be honoured stops the build', () {
    // A literal PIN would be built into the artifact. doctor has refused
    // this for a while; the build went ahead.
    final DVDeclarationCheck check = DVDeclarationCheck.run(project('''
  kiosk:
    enabled: true
    exit:
      method: pin
      pin: "4821"
''').path);

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('pin'));
  });

  test('a module the build cannot mount stops it too', () {
    final DVDeclarationCheck check = DVDeclarationCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
''').path);

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('modules/store'));
  });

  test('a project whose declarations are sound goes ahead', () {
    final Directory root = project('''
  kiosk:
    enabled: true
    exit:
      method: pin
      pin: secret:KIOSK_PIN
''');

    expect(DVDeclarationCheck.run(root.path).ok, isTrue);
  });

  test('a pubspec that will not parse is not this check\'s to report', () {
    // The build has its own reading of the pubspec and its own message for
    // one it cannot read; a second, differently worded failure from here
    // would send somebody looking in the wrong place.
    final Directory root = Directory.systemTemp.createTempSync('dartvel_bad_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: [oops\n');

    expect(DVDeclarationCheck.run(root.path).ok, isTrue);
  });
}
