// A server compiled in loading units, and carried as one file.
//
// Libraries a program reaches only through `import ... deferred as` compile
// to units of their own (gen_snapshot --loading_unit_manifest). The standalone
// runtime looks for unit N in a file beside the program; a web-server binary
// is one file, so its units ride inside it and the native server library
// maps each from there the first time an isolate asks for it.
//
// This compiles a real program that way, splices its units into it, copies
// the one file somewhere empty and runs it: the deferred code has to run on
// the main isolate and on a helper isolate (where the image resizer runs), and
// must not be in the root unit the runtime maps at start.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_cli/src/build/server_compile.dart';
import 'package:dartvel_core/binary_payload.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _marker = 'only-in-the-deferred-unit-5b1e';

const String _program = r'''
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' show embedNativeServerLibraryAt;
import 'package:dartvel_shelf/loading_units.dart';

import 'rare.dart' deferred as rare;

Future<void> main(List<String> args) async {
  final DVBinaryPayload payload = DVBinaryPayload.read(Platform.resolvedExecutable)!;
  final ({int offset, int length}) native = payload.locate('native')!;
  embedNativeServerLibraryAt(payload.path, offset: native.offset, length: native.length);
  stdout.writeln('UNITS ${await dvInstallLoadingUnits(payload)}');
  stdout.writeln('LOADED ${dvLoadedUnitCount()}');
  await rare.loadLibrary();
  stdout.writeln('MAIN ${rare.greet(2)}');
  stdout.writeln('HELPER ${await Isolate.run(() async {
    await rare.loadLibrary();
    return rare.greet(3);
  })}');
  stdout.writeln('LOADED ${dvLoadedUnitCount()}');
}
''';

const String _rare = '''
String greet(int n) => List<String>.filled(n, '$_marker').join('+');
''';

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
      Uri.parse('package:dartvel_cli/src/build/server_compile.dart'))!;
  final String packages =
      p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
  final host = dvHostServerLibrary();
  final File library =
      File(p.join(packages, 'dartvel_shelf', 'lib', 'native', host.subdir, host.name));
  final DVAotToolchain? toolchain = DVAotToolchain.find(Platform.resolvedExecutable);
  final Object skip = !Platform.isLinux
      ? 'loading units are carried in Linux binaries'
      : toolchain == null
          ? 'this SDK has no gen_snapshot'
          : !library.existsSync()
              ? 'no ${host.subdir} native server library'
              : false;

  late Directory project;

  setUpAll(() async {
    if (skip != false) return;
    project = Directory.systemTemp.createTempSync('dv_server_compile_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: units_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
''');
    File(p.join(project.path, 'bin', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_program);
    File(p.join(project.path, 'bin', 'rare.dart')).writeAsStringSync(_rare);
    // The same program with an ordinary import: one unit.
    File(p.join(project.path, 'bin', 'plain.dart')).writeAsStringSync(
        _program
            .replaceFirst("import 'rare.dart' deferred as rare;", "import 'rare.dart' as rare;")
            .replaceAll('await rare.loadLibrary();', ''));
    final ProcessResult got = await Process.run(
        Platform.resolvedExecutable, <String>['pub', 'get', '--offline'],
        workingDirectory: project.path);
    expect(got.exitCode, 0, reason: '${got.stdout}\n${got.stderr}');
  });

  tearDownAll(() {
    if (skip == false) project.deleteSync(recursive: true);
  });

  Future<DVCompiledServer> compile({required bool units, String entry = 'main.dart'}) => dvCompileServer(
        root: project.path,
        entry: p.join(project.path, 'bin', entry),
        dart: Platform.resolvedExecutable,
        units: units,
        run: (String executable, List<String> arguments, {String? workingDirectory}) =>
            Process.run(executable, arguments, workingDirectory: workingDirectory),
      );

  test('deferred code is a unit of its own, carried inside the one file and '
      'loaded from there on any isolate', () async {
    final DVCompiledServer compiled = await compile(units: true);
    expect(compiled.ok, isTrue, reason: compiled.lines.join('\n'));
    expect(compiled.units, isNotEmpty);
    bool has(Uint8List bytes) => latin1.decode(bytes).contains(_marker);
    expect(has(compiled.executable!), isFalse,
        reason: 'the deferred library is in the root unit the runtime maps at start');
    expect(compiled.units.values.any(has), isTrue);

    final Uint8List binary = DVBinaryPayload.splice(
      compiled.executable!,
      <String, List<int>>{
        'native': library.readAsBytesSync(),
        for (final MapEntry<int, Uint8List> unit in compiled.units.entries)
          'unit.${unit.key}': unit.value,
      },
      aligned: <String>{for (final int id in compiled.units.keys) 'unit.$id'},
    );
    final Directory alone = Directory.systemTemp.createTempSync('dv_units_alone_');
    addTearDown(() => alone.deleteSync(recursive: true));
    final File file = File(p.join(alone.path, 'server'))..writeAsBytesSync(binary);
    await Process.run('chmod', <String>['+x', file.path]);
    final ProcessResult ran = await Process.run(file.path, const <String>[], workingDirectory: alone.path);
    expect(ran.exitCode, 0, reason: '${ran.stdout}\n${ran.stderr}');
    expect(const LineSplitter().convert('${ran.stdout}'), <String>[
      'UNITS ${compiled.units.length}',
      'LOADED 0',
      'MAIN $_marker+$_marker',
      'HELPER $_marker+$_marker+$_marker',
      'LOADED 1',
    ]);
    // Nothing was written beside it: no <program>-N.part.so.
    expect(alone.listSync().map((FileSystemEntity e) => p.basename(e.path)), <String>['server']);
  }, skip: skip);

  test('without a deferred import it is one unit, and runs the same', () async {
    final DVCompiledServer compiled = await compile(units: true, entry: 'plain.dart');
    expect(compiled.ok, isTrue, reason: compiled.lines.join('\n'));
    expect(compiled.units, isEmpty);
    final Uint8List binary = DVBinaryPayload.splice(
        compiled.executable!, <String, List<int>>{'native': library.readAsBytesSync()});
    final Directory alone = Directory.systemTemp.createTempSync('dv_units_one_');
    addTearDown(() => alone.deleteSync(recursive: true));
    final File file = File(p.join(alone.path, 'server'))..writeAsBytesSync(binary);
    await Process.run('chmod', <String>['+x', file.path]);
    final ProcessResult ran = await Process.run(file.path, const <String>[], workingDirectory: alone.path);
    expect(ran.exitCode, 0, reason: '${ran.stdout}\n${ran.stderr}');
    expect('${ran.stdout}', contains('UNITS 0'));
    expect('${ran.stdout}', contains('HELPER $_marker+$_marker+$_marker'));
  }, skip: skip);

  test('an SDK without gen_snapshot is no toolchain', () {
    final Directory fake = Directory.systemTemp.createTempSync('dv_fake_sdk_');
    addTearDown(() => fake.deleteSync(recursive: true));
    File(p.join(fake.path, 'bin', 'dart')).createSync(recursive: true);
    expect(DVAotToolchain.find(p.join(fake.path, 'bin', 'dart')), isNull);
  });
}
