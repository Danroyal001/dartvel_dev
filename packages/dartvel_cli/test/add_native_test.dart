// `dartvel add` for a C library or a Rust crate beside the project: what is
// in the directory decides, the sources are copied into the module the
// hook builds from, and the tree is pinned.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_add_native_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: shop\nenvironment:\n  sdk: ^3.13.0\ndartvel:\n  app:\n    name: Shop\n');
  final Directory c = Directory(p.join(root.path, 'vendor', 'mathkit'))
    ..createSync(recursive: true);
  File(p.join(c.path, 'mathkit.h'))
      .writeAsStringSync('int mk_add(int a, int b);\n');
  File(p.join(c.path, 'mathkit.c'))
      .writeAsStringSync('int mk_add(int a, int b) { return a + b; }\n');
  final Directory crate = Directory(p.join(root.path, 'vendor', 'fastmath', 'src'))
    ..createSync(recursive: true);
  File(p.join(crate.parent.path, 'Cargo.toml'))
      .writeAsStringSync('[package]\nname = "fastmath"\nversion = "0.1.0"\n');
  File(p.join(crate.path, 'lib.rs')).writeAsStringSync(
      '#[no_mangle]\npub extern "C" fn fm_mul(a: i64, b: i64) -> i64 { a * b }\n');
  return root.path;
}

Future<int> run(String root, List<String> args) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root));
  try {
    await runner.run(<String>['add', ...args]);
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

void main() {
  test('a directory of C is wrapped, with its sources and a hook', () async {
    final String root = project();
    expect(await run(root, <String>['vendor/mathkit']), 0);
    final String module = p.join(root, 'modules', 'dv_mathkit_module');
    expect(File(p.join(module, 'native', 'mathkit.c')).existsSync(), isTrue);
    expect(File(p.join(module, 'hook', 'build.dart')).readAsStringSync(),
        contains('CBuilder.library'));
    final YamlMap pubspec =
        loadYaml(File(p.join(module, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(pubspec['dartvel']['module']['kind'], 'ffi');
    expect(pubspec['dartvel']['module']['operations']['mkAdd']['web'], 'unavailable');
    expect(DVModuleLock.read(root).pins['dv_mathkit_module']!.source,
        'c:vendor/mathkit');
  });

  test('a crate is wrapped and built by cargo in its hook', () async {
    final String root = project();
    expect(await run(root, <String>['vendor/fastmath', '--as', 'fast']), 0);
    final String module = p.join(root, 'modules', 'dv_fast_module');
    expect(File(p.join(module, 'native', 'rust', 'src', 'lib.rs')).existsSync(),
        isTrue);
    expect(File(p.join(module, 'hook', 'build.dart')).readAsStringSync(),
        contains("'cargo'"));
    expect(DVModuleLock.read(root).pins['dv_fast_module']!.source,
        'cargo:vendor/fastmath');
  });
}
