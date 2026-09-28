// `dartvel inspect modules --json`: what each module is, where it came from,
// what each operation does in each environment, and whether the generated
// wrapper is still the one the lock pinned.
//
// A wrapper edited by hand is DV-MODULE-016: the edit is lost on the next
// refresh, and the hash the lock pinned no longer describes what is
// installed. That is only visible by hashing what is on disk, which is what
// this does rather than trusting the lock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/commands/inspect_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_inspect_mod_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.13.0
dartvel:
  app:
    name: Shop
''');
  final Directory pkg = Directory(p.join(root.path, 'vendor', 'textkit'))
    ..createSync(recursive: true);
  File(p.join(pkg.path, 'pubspec.yaml'))
      .writeAsStringSync('name: textkit\nversion: 0.3.0\n');
  File(p.join(pkg.path, 'lib', 'textkit.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("import 'dart:io';\n"
        'String slug(String text) => text;\n');
  return root.path;
}

Future<List<Object?>> inspect(String root) async {
  final List<String> out = <String>[];
  await runZoned(() async {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(InspectCommand(root: root));
    await runner.run(<String>['inspect', 'modules', '--json']);
  }, zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
          out.add(line)));
  return jsonDecode(out.join()) as List<Object?>;
}

void main() {
  test('a generated module reports its source, outcomes and pin', () async {
    final String root = project();
    final CommandRunner<void> add = CommandRunner<void>('dartvel', 'test')
      ..addCommand(AddCommand(root: root));
    await add.run(<String>['add', 'path:vendor/textkit']);

    final Map<String, Object?> module =
        (await inspect(root)).single! as Map<String, Object?>;
    expect(module['id'], 'textkit');
    expect(module['kind'], 'dartPackage');
    expect(module['surface'], 'TextkitModule');
    expect(module['operations'], <String, Object?>{
      'slug': <String, Object?>{
        'native': 'real',
        'web': 'unavailable',
        'backend': 'real',
      },
    });
    expect((module['pin']! as Map<String, Object?>)['source'],
        'path:vendor/textkit');
    expect(module['wrapperIntact'], isTrue);
    expect(module['problems'], isNull);
  });

  test('a hand-edited wrapper is DV-MODULE-016', () async {
    final String root = project();
    final CommandRunner<void> add = CommandRunner<void>('dartvel', 'test')
      ..addCommand(AddCommand(root: root));
    await add.run(<String>['add', 'path:vendor/textkit']);
    final File surface = File(p.join(root, 'modules', 'dv_textkit_module',
        'lib', 'dv_textkit_module.dart'));
    surface.writeAsStringSync('${surface.readAsStringSync()}\n// patched\n');

    final Map<String, Object?> module =
        (await inspect(root)).single! as Map<String, Object?>;
    expect(module['wrapperIntact'], isFalse);
    expect(module['problems'].toString(), contains('DV-MODULE-016'));
  });
}
