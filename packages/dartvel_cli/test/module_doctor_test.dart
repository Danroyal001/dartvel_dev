// dartvel doctor, on the modules a project declares.
//
// A declaration that says "mount store at /store" and a build that cannot is
// a log line during generation and an exit code of zero: the application
// ships without the section, green. A partner rotates a signing key, the
// manifest stops verifying, and nothing that watches a build notices.
//
// The kiosk policy has been checked this way for a while -- a declaration
// that cannot be honoured fails the check rather than being carried on from
// -- and mounting is the same kind of promise.
import 'dart:io';

import 'package:dartvel_cli/src/doctor/module_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

/// A project declaring one module, with whatever body the test wants.
Directory project(String modules, {bool withSource = true}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_moddoc_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
$modules
''');
  if (withSource) {
    final Directory module = Directory(p.join(root.path, 'modules', 'store'))
      ..createSync(recursive: true);
    File(p.join(module.path, 'pubspec.yaml'))
        .writeAsStringSync('name: store\ndartvel:\n  module:\n    id: store\n');
    File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_page);
  }
  return root;
}

void main() {
  test('a project with no modules has nothing to say about them', () {
    final DVModuleCheck check =
        DVModuleCheck.run(project('  modules: {}\n').path);

    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('a module that mounts is reported and passes', () {
    final DVModuleCheck check = DVModuleCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
''').path);

    expect(check.ok, isTrue);
    expect(check.lines.join('\n'), contains('store'));
    expect(check.lines.join('\n'), contains('/store'));
  });

  test('a module whose project is not there fails the check', () {
    // The declaration names a path, and there is nothing at it. Carried on
    // from, the application ships without the section.
    final DVModuleCheck check = DVModuleCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
''', withSource: false).path);

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('modules/store'));
  });

  test('a federated module with no manifest fails the check', () {
    // Nothing to verify, so nothing is mounted -- and a partner rotating a
    // signing key looks exactly like this.
    final DVModuleCheck check = DVModuleCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: federated
''').path);

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('manifest'));
  });

  test('a backend-only module contributes no pages and is not a failure', () {
    // It is declared to have none. A check that failed on an empty route
    // list would refuse the mode the specification defines.
    final DVModuleCheck check = DVModuleCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: backend-only
''').path);

    expect(check.ok, isTrue);
  });

  test('a mode nobody can honour is said, and does not fail the build', () {
    // The module still mounts; the mode fell back to the default. Worth
    // saying, not worth refusing to ship over.
    final DVModuleCheck check = DVModuleCheck.run(project('''
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      auth: whatever
''').path);

    expect(check.ok, isTrue);
    expect(check.lines.join('\n'), contains('whatever'));
  });
}
