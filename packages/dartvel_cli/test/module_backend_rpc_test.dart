// Where a source cannot run in the calling environment but can on the
// backend, the call crosses to the backend: the placement matrix's carrier
// of last resort. A Dart package that needs dart:io is the first source it
// carries -- in the browser its asynchronous operations send the call to the
// application's backend, which runs the package and answers.
//
// Checked by running both halves on the VM with a transport that hands the
// request straight to the backend half, after a JSON round trip, which is
// everything the wire does to a value.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_package_module.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'dart_package_module_test.dart' show install, scratch, vendor;

const String _io = r'''
import 'dart:io';
import 'dart:typed_data';

/// The separator this platform's paths use. Synchronous, so it cannot wait
/// for a backend.
String separator() => Platform.pathSeparator;

/// Reads [name] from the directory the process runs in.
Future<String> readNote(String name, {String suffix = '.txt'}) =>
    File('$name$suffix').readAsString();

Future<List<String>> listNames(List<String> names) async =>
    <String>[for (final String n in names) n.toUpperCase()];

Future<Uint8List> bytesOf(String text) async =>
    Uint8List.fromList(text.codeUnits);

Future<double> half(int value) async => value / 2;

Future<void> touch(String name) => File(name).writeAsString('');
''';

DVForeignModuleSpec notesSpec(Directory root) => dvDartPackageModuleSpec(
      id: 'notes',
      source: 'path:notes',
      surface: dvScanDartPackage(vendor(root, 'notes', _io).path),
      dependency: '{path: ../notes}',
    );

void main() {
  test('a call the build can see reads {compat: backend} as compat', () {
    expect(DVModuleOutcome.parse(loadYaml('{compat: backend}')),
        DVModuleOutcome.compat);
    expect(DVModuleOutcome.parse(loadYaml('{compat: nowhere}')), isNull);
  });

  test('an asynchronous operation reaches the backend from the web; a '
      'synchronous one cannot wait for it', () {
    final Directory root = scratch();
    final DVForeignModuleSpec spec = notesSpec(root);
    final YamlMap ops = (loadYaml(dvWriteForeignModule(spec).files['pubspec.yaml']!)
        as YamlMap)['dartvel']['module']['operations'] as YamlMap;
    expect(ops['readNote']['web'], <String, String>{'compat': 'backend'});
    expect(ops['readNote']['native'], 'real');
    expect(ops['readNote']['backend'], 'real');
    expect(ops['separator']['web'], 'unavailable');
    expect(spec.outcomes['readNote']![DVModuleEnvironment.web],
        DVModuleOutcome.compat);
  });

  test('--elsewhere still opts out of the backend', () {
    final Directory root = scratch();
    final DVForeignModuleSpec spec = dvDartPackageModuleSpec(
      id: 'notes',
      source: 'path:notes',
      surface: dvScanDartPackage(vendor(root, 'notes', _io).path),
      dependency: '{path: ../notes}',
      elsewhere: DVModuleOutcome.unavailable,
    );
    expect(spec.outcomes['readNote']![DVModuleEnvironment.web],
        DVModuleOutcome.unavailable);
  });

  test('the web carrier sends the call and the backend half answers it',
      () async {
    final Directory root = scratch();
    final DVForeignModuleSpec spec = notesSpec(root);
    final DVGeneratedModule module = dvWriteForeignModule(spec);
    final Directory pkg = Directory(p.join(root.path, 'notes'));
    final String config = install(root, module, pkg);
    File(p.join(root.path, 'hello.md')).writeAsStringSync('from the server');
    final File probe = File(p.join(root.path, 'rpc_probe.dart'))
      ..writeAsStringSync('''
import 'dart:convert';
import 'package:dartvel_core/dartvel.dart';
import 'package:dv_notes_module/src/carrier_backend.dart' as backend;
import 'package:dv_notes_module/src/carrier_web.dart' as web;

Future<void> main() async {
  final List<String> paths = <String>[];
  DVModuleRpc.transport = (String path, Map<String, Object?> arguments) async {
    paths.add(path);
    final Object? sent = jsonDecode(jsonEncode(arguments));
    final String op = path.split('/').last;
    final Object? answer = await backend.dvModuleDispatch(
        op, (sent! as Map<String, Object?>));
    return jsonDecode(jsonEncode(answer));
  };
  print(await web.readNote('hello', suffix: '.md'));
  print(await web.listNames(<String>['a', 'b']));
  print((await web.bytesOf('hi')).runtimeType.toString().contains('Uint8List'));
  print(await web.half(5));
  await web.touch('touched');
  print(paths.first);
  try {
    web.separator();
  } on DVModuleUnavailable catch (e) {
    print(e.code);
  }
  try {
    await backend.dvModuleDispatch('separator', <String, Object?>{});
  } on DVModuleRpcRefused catch (e) {
    print(e.code);
  }
}
''');
    final ProcessResult run = await Process.run(Platform.resolvedExecutable,
        <String>['--packages=$config', probe.path],
        workingDirectory: root.path);
    expect('${run.stdout}${run.stderr}',
        'from the server\n[A, B]\ntrue\n2.5\n/_dv/modules/notes/readNote\n'
        'DV-MODULE-013\nDV-MODULE-021\n');
    expect(File(p.join(root.path, 'touched')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the browser bundle carries the call, not the package', () async {
    final Directory root = scratch();
    final DVGeneratedModule module = dvWriteForeignModule(notesSpec(root));
    final String config =
        install(root, module, Directory(p.join(root.path, 'notes')));
    final File probe = File(p.join(root.path, 'web_probe.dart'))
      ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart' show DVModuleRpc;
import 'package:dv_notes_module/dv_notes_module.dart';

Future<void> main() async {
  DVModuleRpc.transport = (String path, Map<String, Object?> a) async => path;
  print(await const NotesModule().readNote('x'));
}
''');
    final String out = p.join(root.path, 'out.js');
    final ProcessResult compiled = await Process.run(
        Platform.resolvedExecutable,
        <String>['compile', 'js', '--packages=$config', '-o', out, probe.path]);
    expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
    final String js = File(out).readAsStringSync();
    expect(js, contains('/_dv/modules/'));
    expect(js, isNot(contains('readAsString')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
