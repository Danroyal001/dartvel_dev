// Files carried inside a compiled executable, read back by the executable.
//
// `dartvel build web-server` ships one file. The native server library, the
// web app's shell and code assets have to travel inside it, and a Dart
// executable cannot simply have bytes appended: `dart compile exe` writes the
// runtime, then the snapshot, then a trailer naming where the snapshot starts,
// and the runtime reads that trailer from the end of its own file. Anything
// after it and the program no longer starts.
//
// So this compiles a real executable, splices sections in, runs the result
// from an empty directory and asks it what it carries -- and runs the
// unspliced one as the control, which must carry nothing and still start.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartvel_core/src/process/binary_payload.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _program = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/src/process/binary_payload.dart';

void main() {
  final DVBinaryPayload? payload =
      DVBinaryPayload.read(Platform.resolvedExecutable);
  if (payload == null) {
    stdout.writeln('NONE');
    return;
  }
  stdout.writeln('SECTIONS ${payload.names.join(',')}');
  stdout.writeln('GREETING ${utf8.decode(payload.section('greeting'))}');
  final Map<String, List<int>> files = dvUnpackFiles(payload.section('files'));
  for (final String path in files.keys.toList()..sort()) {
    stdout.writeln('FILE $path ${files[path]!.length}');
  }
}
''';

void main() {
  late Directory work;
  late File compiled;

  setUpAll(() async {
    final Uri library = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_core/src/process/binary_payload.dart'),
    ))!;
    // lib/src/process/binary_payload.dart -> the package root.
    final String package =
        p.dirname(p.dirname(p.dirname(p.dirname(library.toFilePath()))));
    work = Directory.systemTemp.createTempSync('dv_binary_payload_');
    final File source = File(p.join(work.path, 'program.dart'))
      ..writeAsStringSync(_program);
    compiled = File(p.join(work.path, 'program'));
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'compile',
        'exe',
        '--packages=${p.join(package, '.dart_tool', 'package_config.json')}',
        source.path,
        '-o',
        compiled.path,
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  tearDownAll(() => work.deleteSync(recursive: true));

  Future<List<String>> runAlone(File executable) async {
    final Directory empty = Directory(p.join(work.path, 'empty'))
      ..createSync(recursive: true);
    final File copy = executable.copySync(p.join(empty.path, 'app'));
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['+x', copy.path]);
    }
    final ProcessResult ran =
        await Process.run(copy.path, const <String>[], workingDirectory: empty.path);
    expect(ran.exitCode, 0, reason: '${ran.stdout}\n${ran.stderr}');
    return const LineSplitter().convert('${ran.stdout}');
  }

  test('an executable with nothing spliced in carries nothing, and runs',
      () async {
    expect(await runAlone(compiled), <String>['NONE']);
  });

  test('spliced sections are read back by the executable they are in',
      () async {
    final Uint8List spliced = DVBinaryPayload.splice(
      compiled.readAsBytesSync(),
      <String, List<int>>{
        'greeting': utf8.encode('hello from inside'),
        'files': dvPackFiles(<String, List<int>>{
          'index.html': utf8.encode('<!doctype html>'),
          'assets/big.bin': List<int>.generate(300000, (int i) => i % 256),
        }),
      },
    );
    final File out = File(p.join(work.path, 'spliced'))
      ..writeAsBytesSync(spliced);

    expect(await runAlone(out), <String>[
      'SECTIONS greeting,files',
      'GREETING hello from inside',
      'FILE assets/big.bin 300000',
      'FILE index.html 15',
    ]);
  }, skip: Platform.isMacOS
      ? 'a Mach-O executable is signed, and changing its bytes breaks the '
          'signature'
      : false);

  test('a file that is not a compiled Dart executable is refused', () {
    expect(
      () => DVBinaryPayload.splice(
        Uint8List.fromList(utf8.encode('#!/bin/sh\necho hi\n')),
        <String, List<int>>{'x': <int>[1]},
      ),
      throwsFormatException,
    );
  });

  test('packed files round-trip, empty files and nested paths included', () {
    final Map<String, List<int>> files = <String, List<int>>{
      'a/b/c.txt': utf8.encode('c'),
      'empty': <int>[],
    };
    final Map<String, List<int>> back = dvUnpackFiles(dvPackFiles(files));
    expect(back.keys, unorderedEquals(files.keys));
    expect(back['a/b/c.txt'], utf8.encode('c'));
    expect(back['empty'], isEmpty);
  });
  group('extracting packed files', () {
    late Directory into;
    setUp(() => into = Directory.systemTemp.createTempSync('dv_extract_'));
    tearDown(() => into.deleteSync(recursive: true));

    test('writes them once, and a second start reuses them', () {
      final Uint8List packed = dvPackFiles(<String, List<int>>{
        'index.html': utf8.encode('<!doctype html>'),
        'assets/app.js': utf8.encode('main()'),
      });
      final String first = dvExtractFiles(packed, into.path);
      expect(File(p.join(first, 'assets', 'app.js')).readAsStringSync(),
          'main()');
      final DateTime written =
          File(p.join(first, 'index.html')).lastModifiedSync();

      final String second = dvExtractFiles(packed, into.path);
      expect(second, first);
      expect(File(p.join(second, 'index.html')).lastModifiedSync(), written);
    });

    test('a new build replaces the files of the old one', () {
      final String old = dvExtractFiles(
          dvPackFiles(<String, List<int>>{'index.html': utf8.encode('old')}),
          into.path);
      final String current = dvExtractFiles(
          dvPackFiles(<String, List<int>>{'index.html': utf8.encode('new')}),
          into.path);
      expect(current, isNot(old));
      expect(File(p.join(current, 'index.html')).readAsStringSync(), 'new');
      expect(Directory(old).existsSync(), isFalse,
          reason: 'every upgrade would otherwise leave a copy of the app');
    });

    test('a path that climbs out of the directory is refused', () {
      expect(
        () => dvExtractFiles(
            dvPackFiles(<String, List<int>>{'../escape': <int>[1]}), into.path),
        throwsFormatException,
      );
    });
  });
}
