// `dartvel upgrade --apply` carries out the project plan `--plan` shows.
//
// The Golden Path ends in Upgrade, and the plan listed what a project had to
// change and left every change to the developer: constraints edited by hand,
// migrate-code run separately, pub and the generator after that. Applying is
// the plan's own mechanical changes and nothing else. The silent failures are
// the ones to test: a write while something blocks, a half-applied project
// when one file moved under the plan, a third-party constraint quietly bumped,
// and a CLI upgrade riding along with a project one.
import 'dart:io';

import 'package:dartvel_cli/src/build/sdk_floor.dart';
import 'package:dartvel_cli/src/commands/upgrade_command.dart';
import 'package:dartvel_cli/src/generators/generate_check.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:dartvel_cli/src/upgrade/upgrade_plan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _target = dartvelPackageVersion;

const String _oldApp = '''
name: shop
# The comments and the order survive an upgrade.
environment:
  sdk: ">=3.4.0 <3.10.0"
dependencies:
  flutter:
    sdk: flutter
  dartvel_core: ^0.4.0 # pinned for the launch
  dartvel_flutter: ^0.4.0
  http: ^1.2.0
dev_dependencies:
  dartvel_cli: ^$_target
''';

void main() {
  late Directory root;
  late List<String> steps;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_upgrade_apply_');
    steps = <String>[];
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String rel, String content) {
    File(p.join(root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String read(String rel) => File(p.join(root.path, rel)).readAsStringSync();

  Map<String, String> snapshot() => <String, String>{
        for (final FileSystemEntity e
            in root.listSync(recursive: true, followLinks: false))
          if (e is File)
            p.relative(e.path, from: root.path): e.readAsStringSync(),
      };

  Future<int> apply({
    DVToolchainVersions toolchain =
        const DVToolchainVersions(dart: '3.13.4', flutter: '3.47.5'),
    Future<void> Function()? beforeWrite,
    List<String>? out,
  }) =>
      dvRunUpgrade(
        root.path,
        plan: false,
        apply: true,
        out: (out ?? <String>[]).add,
        selfUpgrade: () async => steps.add('cli'),
        probe: () async => toolchain,
        generatedCheck: (String _) async =>
            const DVGenerateCheckResult(stale: <String>[], unstable: <String>[]),
        pubUpgrade: (List<String> packages) async =>
            steps.add('pub upgrade ${packages.join(' ')}'),
        generate: () async => steps.add('generate'),
        beforeWrite: beforeWrite,
      );

  test('it moves the constraints the plan said to move, and only those',
      () async {
    write('pubspec.yaml', _oldApp);

    expect(await apply(), 0);

    final String pubspec = read('pubspec.yaml');
    expect(pubspec, contains('sdk: ">=$dvDartFloor <4.0.0"'));
    expect(pubspec, contains('dartvel_core: ^$_target # pinned for the launch'));
    expect(pubspec, contains('dartvel_flutter: ^$_target'));
    expect(pubspec, contains('http: ^1.2.0'),
        reason: 'a package that is not Dartvel\'s is the application\'s call');
    expect(pubspec, contains('# The comments and the order survive'));
  });

  test('it rewrites the deprecated names, then resolves, then generates',
      () async {
    write('pubspec.yaml', _oldApp);
    write('lib/pages/home.dart', 'void f() => DV.Storage.get("a");\n');

    expect(await apply(), 0);

    expect(read('lib/pages/home.dart'), contains('DV.FileStorage.get'));
    expect(steps, <String>[
      'pub upgrade dartvel_core dartvel_flutter dartvel_cli',
      'generate',
    ]);
  });

  test('it does not upgrade the CLI', () async {
    write('pubspec.yaml', _oldApp);
    await apply();
    expect(steps, isNot(contains('cli')));
  });

  test('anything blocked writes nothing and runs nothing', () async {
    // An installed Dart below the floor is not a file the plan can edit.
    write('pubspec.yaml', _oldApp);
    write('lib/pages/home.dart', 'void f() => DV.Storage.get("a");\n');
    final Map<String, String> before = snapshot();
    final List<String> out = <String>[];

    final int code = await apply(
      toolchain: const DVToolchainVersions(dart: '3.4.0', flutter: '3.22.0'),
      out: out,
    );

    expect(code, 1);
    expect(snapshot(), before);
    expect(steps, isEmpty);
    expect(out.join('\n'), contains('blocked'));
  });

  test('a third-party constraint that blocks is left to the application',
      () async {
    // go_router as a dependency the target cannot accept.
    write('pubspec.yaml', _oldApp.replaceFirst(
        '  http: ^1.2.0\n', '  http: ^1.2.0\n  go_router: ^13.0.0\n'));
    final Map<String, String> before = snapshot();

    expect(await apply(), 1);
    expect(snapshot(), before);
  });

  test('a file that moved after the plan was made stops the whole apply',
      () async {
    write('pubspec.yaml', _oldApp);
    write('lib/pages/home.dart', 'void f() => DV.Storage.get("a");\n');

    final int code = await apply(beforeWrite: () async {
      write('lib/pages/home.dart', 'void f() => DV.Storage.get("b");\n');
    });

    expect(code, 1);
    expect(read('pubspec.yaml'), _oldApp,
        reason: 'half a project upgraded is a state nobody chose');
    expect(steps, isEmpty);
  });

  test('a project already on the target has nothing to apply', () async {
    write('pubspec.yaml', '''
name: shop
environment:
  sdk: ">=$dvDartFloor <4.0.0"
dependencies:
  dartvel_core: ^$_target
''');
    final List<String> out = <String>[];

    expect(await apply(out: out), 0);
    expect(steps, isEmpty);
    expect(out.join('\n'), contains('Nothing to apply'));
  });
}
