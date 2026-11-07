// The backend compile of a web-server build, started early and reused.
//
// Compiling the backend into one executable took three minutes of a cold
// sample build, after everything else had finished, and the same three
// minutes again on a build where nothing had changed. Its inputs are the
// backend's Dart sources and the build's defines -- none of the web output --
// so it now starts beside Flutter's build, and a compile whose inputs are
// unchanged is taken from the build cache.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_cli/src/build/server_compile.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  void write(String relative, String content) {
    final File file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_server_reuse_');
    write('pubspec.yaml', 'name: probe\n');
    write('pubspec.lock', 'packages: {}\n');
    write('.dart_tool/package_config.json', '{"configVersion":2,"packages":[]}');
    write('.dart_tool/dartvel_backend_routes.g.dart', '// routes\n');
    write('.dart_tool/dartvel_backend_fn0.g.dart', '// fn0\n');
    write('lib/backend/functions/health.get.dart', 'String health() => "ok";\n');
    write('build/web/index.html', '<html>one</html>');
  });
  tearDown(() => root.deleteSync(recursive: true));

  String key({Map<String, String> defines = const <String, String>{'dartvel.studio': 'false'}, bool units = true}) =>
      dvServerCompileKey(root: root.path, defines: defines, units: units, dartVersion: 'Dart 3.13.0');

  group('what the compile depends on', () {
    test('nothing changed is the same key', () {
      expect(key(), key());
    });

    test('the web output is not an input', () {
      final String before = key();
      write('build/web/index.html', '<html>two</html>');
      write('build/web/main.dart.js', 'changed');
      expect(key(), before);
    });

    test('a backend source, a generated backend file or the lock is', () {
      final String before = key();
      write('lib/backend/functions/health.get.dart', 'String health() => "changed";\n');
      final String afterSource = key();
      expect(afterSource, isNot(before));
      write('.dart_tool/dartvel_backend_fn0.g.dart', '// fn0 changed\n');
      final String afterGenerated = key();
      expect(afterGenerated, isNot(afterSource));
      write('pubspec.lock', 'packages: {changed: true}\n');
      expect(key(), isNot(afterGenerated));
    });

    test('a define, the unit split and the Dart SDK are', () {
      expect(key(defines: <String, String>{'dartvel.studio': 'true'}), isNot(key()));
      expect(key(units: false), isNot(key()));
      expect(
          dvServerCompileKey(
              root: root.path,
              defines: const <String, String>{'dartvel.studio': 'false'},
              units: true,
              dartVersion: 'Dart 3.14.0'),
          isNot(key()));
    });
  });

  test('a compiled backend kept in a directory comes back byte for byte', () {
    final DVCompiledServer compiled = DVCompiledServer(
      ok: true,
      lines: const <String>[],
      executable: Uint8List.fromList(<int>[1, 2, 3, 0, 255]),
      units: <int, Uint8List>{
        2: Uint8List.fromList(<int>[9, 8, 7]),
        3: Uint8List.fromList(<int>[6]),
      },
    );
    final Directory kept = Directory(p.join(root.path, 'kept'));
    dvWriteCompiledServer(compiled, kept);
    final DVCompiledServer? back = dvReadCompiledServer(kept);
    expect(back, isNotNull);
    expect(back!.ok, isTrue);
    expect(back.executable, compiled.executable);
    expect(back.units.keys, unorderedEquals(<int>[2, 3]));
    expect(back.units[2], compiled.units[2]);
    expect(back.units[3], compiled.units[3]);
    expect(dvReadCompiledServer(Directory(p.join(root.path, 'none'))), isNull);
  });

  test('a compile begun earlier is the one the binary is built from', () async {
    bool ran = false;
    final DVServerBinaryResult result = await dvBuildServerBinary(
      root: root.path,
      library: File(p.join(root.path, 'libnative.so'))..writeAsStringSync('native'),
      run: (String executable, List<String> arguments, {String? workingDirectory}) async {
        ran = true;
        return ProcessResult(0, 0, '', '');
      },
      compiling: Future<DVCompiledServer>.value(const DVCompiledServer(
          ok: false, lines: <String>['the early compile failed'])),
    );
    expect(ran, isFalse, reason: 'not compiled a second time');
    expect(result.ok, isFalse);
    expect(result.lines, contains('the early compile failed'));
  });
}
