// `dartvel create` names its project the way `flutter create` does.
//
// `dartvel create hello_dartvel` makes ./hello_dartvel and names the package
// after it; there is no --name. With no folder given, it asks whether the
// current folder is the one: Enter (or "y") uses it, and anything else typed
// is the folder to create. Where there is nobody to ask, the current folder is
// used, as it was before.
import 'package:args/command_runner.dart';
import 'dart:io';

import 'package:dartvel_cli/src/commands/adopt_command.dart';
import 'package:dartvel_cli/src/commands/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String cwd = p.join(p.separator, 'work', 'hello_dartvel');

  group('a folder on the command line', () {
    test('is created beside the current folder and names the project', () {
      final t = dvResolveCreateTarget(cwd: '/work', folder: 'hello_dartvel');
      expect(t.root, p.join('/work', 'hello_dartvel'));
      expect(t.projectName, 'hello_dartvel');
      expect(t.createsFolder, isTrue);
    });

    test('"." is the current folder, named after it', () {
      final t = dvResolveCreateTarget(cwd: cwd, folder: '.');
      expect(t.root, cwd);
      expect(t.projectName, 'hello_dartvel');
      expect(t.createsFolder, isFalse);
    });

    test('--project-name overrides the folder name, as in flutter create', () {
      final t = dvResolveCreateTarget(
          cwd: '/work', folder: 'Hello-App', projectName: 'hello_app');
      expect(t.root, p.join('/work', 'Hello-App'));
      expect(t.projectName, 'hello_app');
    });

    test('a folder that is not a valid package name is refused with a suggestion', () {
      expect(
        () => dvResolveCreateTarget(cwd: '/work', folder: 'Hello-App'),
        throwsA(isA<UsageException>().having(
            (e) => e.message, 'message', allOf(contains('hello_app'), contains('--project-name')))),
      );
    });
  });

  group('no folder on the command line', () {
    test('asks, and Enter uses the current folder', () {
      final List<String> asked = [];
      final t = dvResolveCreateTarget(
          cwd: cwd, interactive: true, ask: (q) { asked.add(q); return ''; });
      expect(asked.single, contains('hello_dartvel'),
          reason: 'the question names the folder it is offering');
      expect(t.root, cwd);
      expect(t.createsFolder, isFalse);
    });

    test('"y" also uses the current folder', () {
      final t = dvResolveCreateTarget(cwd: cwd, interactive: true, ask: (_) => 'Y');
      expect(t.root, cwd);
    });

    test('a typed name creates that folder and names the project after it', () {
      final t = dvResolveCreateTarget(cwd: cwd, interactive: true, ask: (_) => 'shop_app');
      expect(t.root, p.join(cwd, 'shop_app'));
      expect(t.projectName, 'shop_app');
      expect(t.createsFolder, isTrue);
    });

    test('"n" asks for the folder name, and does not create a folder called n', () {
      final answers = ['n', 'shop_app'];
      final t = dvResolveCreateTarget(cwd: cwd, interactive: true, ask: (_) => answers.removeAt(0));
      expect(t.root, p.join(cwd, 'shop_app'));
      expect(answers, isEmpty);
    });

    test('with nobody to ask, the current folder is used', () {
      final t = dvResolveCreateTarget(
          cwd: cwd, interactive: false, ask: (_) => fail('must not prompt without a terminal'));
      expect(t.root, cwd);
    });
  });

  test('--name is gone', () {
    expect(InitCommand().argParser.options.containsKey('name'), isFalse);
    expect(InitCommand().argParser.options.containsKey('project-name'), isTrue);
  });

  group('dartvel init', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dv_init_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('in a folder with no project, creates one, as create does', () {
      expect(dvInitCreatesProject(dir.path), isTrue);
    });

    test('in an existing project, adds Dartvel to it instead', () {
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: acme\n');
      expect(dvInitCreatesProject(dir.path), isFalse);
    });
  });
}
