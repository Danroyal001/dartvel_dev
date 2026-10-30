// A module's tests are the parent's tests.
//
// Testing: "a module's tests run in the parent's suite under the module's own
// id, so a failure names which module it came from." `dartvel test` ran the
// parent's test/ and nothing else, so a module's generated tests ran only if
// somebody went into its directory and ran them by hand.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory root;

void module(String id, String dir, {bool tests = true, bool flutter = false}) {
  final Directory home = Directory(p.join(root.path, dir))..createSync(recursive: true);
  File(p.join(home.path, 'pubspec.yaml')).writeAsStringSync(
    'name: dv_${id}_module\n'
    '${flutter ? 'dependencies:\n  flutter:\n    sdk: flutter\n' : ''}'
    'dartvel:\n  module:\n    id: $id\n',
  );
  if (tests) {
    File(p.join(home.path, 'test', '${id}_test.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
  }
}

void parent(String modules) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: shop\n'
    'dartvel:\n'
    '  modules:\n'
    '$modules',
  );
  File(p.join(root.path, 'test', 'shop_test.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('void main() {}\n');
}

String mount(String id, String path) =>
    '    $id:\n      source:\n        path: $path\n      mount: /$id\n';

Future<String> dryRun(List<String> args) async {
  final StringBuffer out = StringBuffer();
  await IOOverrides.runZoned(
    () async {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(TestCommand(root: root.path));
      await runner.run(<String>['test', ...args, '--dry-run']);
    },
    stdout: () => _Capture(out),
  );
  return out.toString();
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('dv_module_suites_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('each mounted module with tests is a suite of the parent, by id', () {
    module('slugify', 'modules/dv_slugify_module');
    module('maps', 'modules/dv_maps_module', flutter: true);
    parent(mount('slugify', 'modules/dv_slugify_module') + mount('maps', 'modules/dv_maps_module'));

    final List<DartvelModuleSuite> suites = DartvelModuleSuite.find(root);
    expect(suites.map((DartvelModuleSuite s) => s.id), <String>['maps', 'slugify']);
    final DartvelModuleSuite slugify = suites.last;
    expect(slugify.directory, p.join(root.path, 'modules', 'dv_slugify_module'));
    expect(slugify.executable, 'dart');
    expect(suites.first.executable, 'flutter', reason: 'a Flutter module runs under flutter test');
  });

  test('a module with no tests, or not on disk, is not a suite', () {
    module('quiet', 'modules/dv_quiet_module', tests: false);
    parent(mount('quiet', 'modules/dv_quiet_module') +
        '    remote:\n      source:\n        git: https://example.test/remote.git\n      mount: /remote\n');
    expect(DartvelModuleSuite.find(root), isEmpty);
  });

  test('dartvel test runs the parent and then each module, naming it', () async {
    module('slugify', 'modules/dv_slugify_module');
    parent(mount('slugify', 'modules/dv_slugify_module'));

    final String out = await dryRun(const <String>[]);
    expect(out, contains('dart test test'));
    expect(out, contains('module slugify: dart test (in modules/dv_slugify_module)'));
  });

  test('a narrower run -- a mode, or files named -- leaves the modules out', () async {
    module('slugify', 'modules/dv_slugify_module');
    parent(mount('slugify', 'modules/dv_slugify_module'));
    Directory(p.join(root.path, 'test', 'golden')).createSync(recursive: true);

    expect(await dryRun(const <String>['golden']), isNot(contains('module slugify')));
    expect(await dryRun(const <String>['unit', 'test/shop_test.dart']), isNot(contains('module slugify')));
  });
}

class _Capture implements Stdout {
  _Capture(this.buffer);

  final StringBuffer buffer;

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void write(Object? object) => buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
