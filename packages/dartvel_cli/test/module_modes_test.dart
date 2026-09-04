// A module's shell, auth, theme and data modes.
//
// Four keys the specification defines per module and nothing read, so
// `auth: independent` and `theme: isolated` were comments. Reading them is
// half the job; the half that matters is refusing the combinations that
// cannot work, because those read perfectly and fail at run time in another
// deployment.
//
// A federated module runs in its own deployment. It cannot inherit the
// parent's DV.Auth -- there is no shared process to inherit it from, which is
// exactly why the specification gives federated auth its own mode -- and it
// cannot share the parent's database. A declaration that says it does is not
// a preference the build can honour; it is a mistake that shows up as a
// module that silently has no session.
import 'dart:io';

import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

Directory workspace(String modes, {String deployment = 'embedded'}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_modes_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: $deployment
$modes
''');
  final Directory module = Directory(p.join(root.path, 'modules', 'store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: store
dartvel:
  module:
    id: store
''');
  File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  return root;
}

DVModuleMount mountOf(String modes, {String deployment = 'embedded'}) =>
    dvDiscoverModuleMounts(workspace(modes, deployment: deployment).path).single;

void main() {
  group('what a module declares', () {
    test('an undeclared module inherits everything and shares data', () {
      final DVModuleMount mount = mountOf('');

      expect(mount.shell, 'inherit');
      expect(mount.auth, 'inherit');
      expect(mount.theme, 'inherit');
      expect(mount.data, 'shared');
      expect(mount.problems, isEmpty);
    });

    test('the declared modes are read', () {
      final DVModuleMount mount = mountOf('''
      shell: none
      auth: public
      theme: override
      data: schema-isolated
''');

      expect(mount.shell, 'none');
      expect(mount.auth, 'public');
      expect(mount.theme, 'override');
      expect(mount.data, 'schema-isolated');
      expect(mount.problems, isEmpty);
    });

    test('a mode that is not one of the modes is a problem, not a silent default', () {
      final DVModuleMount mount = mountOf('      auth: whatever\n');

      expect(mount.problems, isNotEmpty);
      expect(mount.problems.join(' '), contains('whatever'));
      expect(mount.auth, 'inherit', reason: 'and the default is what is used');
    });
  });

  group('combinations that cannot work', () {
    test('a federated module cannot inherit the parent\'s auth', () {
      // There is no shared process to inherit a session from, which is why
      // the specification gives federated auth a mode of its own. Left
      // unchecked, the module would run with no session and look like a
      // login bug.
      final DVModuleMount mount =
          mountOf('      auth: inherit\n', deployment: 'federated');

      expect(mount.problems.join(' '), contains('auth'));
      expect(mount.problems.join(' '), contains('federated'));
    });

    test('a federated module cannot share the parent\'s database', () {
      final DVModuleMount mount =
          mountOf('      data: shared\n', deployment: 'federated');

      expect(mount.problems.join(' '), contains('data'));
    });

    test('a federated module defaults to the modes its deployment can honour', () {
      // Not to inherit-and-refuse: defaulting to something impossible and
      // then complaining about it would make every federated module report
      // two problems nobody wrote.
      final DVModuleMount mount = mountOf('', deployment: 'federated');

      expect(mount.auth, 'federated');
      expect(mount.data, 'remote');
      expect(mount.theme, 'isolated');
      expect(mount.problems.where((String p) => p.contains('auth')), isEmpty);
    });

    test('a federated module may be independent, federated or public', () {
      for (final String auth in <String>['independent', 'federated', 'public']) {
        final DVModuleMount mount =
            mountOf('      auth: $auth\n      data: remote\n', deployment: 'federated');
        expect(mount.problems.where((String p) => p.contains('auth')), isEmpty,
            reason: 'auth: $auth was refused');
      }
    });

    test('an embedded module may inherit everything', () {
      final DVModuleMount mount = mountOf('''
      auth: inherit
      data: shared
      theme: inherit
''');

      expect(mount.problems, isEmpty);
    });

    test('a backend-only module has no shell or theme to speak of', () {
      // It contributes models and functions and no pages, so a theme mode is
      // a declaration about something that does not exist.
      final DVModuleMount mount =
          mountOf('      theme: override\n', deployment: 'backend-only');

      expect(mount.problems.join(' '), contains('theme'));
    });
  });
}
