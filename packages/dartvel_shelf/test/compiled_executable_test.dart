// The server in a program compiled with `dart compile exe`.
//
// serve() found the native library through Isolate.resolvePackageUri, which
// answers under `dart run` and answers null in a compiled executable, where
// there are no packages to resolve against. So a backend compiled to one
// binary -- the file dartvel infra's units start and dartvel deploy's image
// runs -- died on its first line with "Null check operator used on a null
// value", naming nothing.
//
// These compile a real executable, move it away from the package, run it and
// ask it for a page: once handed the library's bytes, which is how a single
// file carries its own server, and once without, where the failure has to say
// what is missing.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _program = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    embedNativeServerLibrary(File(arguments.first).readAsBytesSync());
  }
  try {
    final ServerHandle server = await serve(
      (Request request) async => Response.text('served by the binary'),
      host: '127.0.0.1',
      port: 0,
    );
    stdout.writeln('PORT ${server.port}');
    await stdin.transform(utf8.decoder).first;
    await server.stop();
    exit(0);
  } catch (error) {
    stdout.writeln('ERROR $error');
    exit(3);
  }
}
''';

void main() {
  final Uri? packaged = Isolate.resolvePackageUriSync(Uri.parse(
    'package:dartvel_shelf/native/linux-x64/libdartvel_shelf.so',
  ));
  final File? library = packaged == null ? null : File.fromUri(packaged);
  final Object skip = !Platform.isLinux
      ? 'the packaged library this embeds is linux-x64'
      : library == null || !library.existsSync()
          ? 'no linux-x64 native server library has been built'
          : false;
  late Directory work;
  late String executable;

  setUpAll(() async {
    if (skip != false) return;
    // lib/native/linux-x64/<library> -> the package root.
    final String package = p.dirname(p.dirname(p.dirname(p.dirname(library!.path))));
    work = Directory.systemTemp.createTempSync('dv_shelf_exe_');
    final File source = File(p.join(work.path, 'server.dart'))
      ..writeAsStringSync(_program);
    executable = p.join(work.path, 'bin', 'server');
    Directory(p.dirname(executable)).createSync();
    final ProcessResult compiled = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'compile',
        'exe',
        '--packages=${p.join(package, '.dart_tool', 'package_config.json')}',
        source.path,
        '-o',
        executable,
      ],
    );
    expect(compiled.exitCode, 0,
        reason: '${compiled.stdout}\n${compiled.stderr}');
  });

  tearDownAll(() {
    if (skip == false) work.deleteSync(recursive: true);
  });

  /// Starts the executable from a directory with nothing else in it, so a
  /// library found beside the package cannot be what answered.
  Future<({Process process, List<String> lines})> start(
    List<String> arguments,
  ) async {
    final Directory elsewhere = Directory(p.join(work.path, 'run'))
      ..createSync(recursive: true);
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: elsewhere.path,
    );
    final List<String> lines = <String>[];
    final Completer<void> first = Completer<void>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      lines.add(line);
      if (!first.isCompleted) first.complete();
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    await Future.any(<Future<void>>[
      first.future,
      process.exitCode.then((_) {}),
    ]).timeout(const Duration(seconds: 30));
    return (process: process, lines: lines);
  }

  test('a compiled executable handed the library serves a request', () async {
    final run = await start(<String>[library!.path]);
    addTearDown(() => run.process.kill());
    final String? announced =
        run.lines.where((String l) => l.startsWith('PORT ')).firstOrNull;
    expect(announced, isNotNull, reason: run.lines.join('\n'));

    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));
    final HttpClientResponse response = await (await client.getUrl(Uri.parse(
      'http://127.0.0.1:${announced!.substring(5)}/',
    )))
        .close();
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(),
        'served by the binary');
    run.process.stdin.writeln('stop');
    expect(await run.process.exitCode, 0);
  },
      skip: skip);

  test('without the library the executable says what is missing', () async {
    final run = await start(const <String>[]);
    expect(await run.process.exitCode, 3, reason: run.lines.join('\n'));
    final String output = run.lines.join('\n');
    expect(output, isNot(contains('Null check')));
    expect(output, contains('native server library'));
    expect(output, contains('dartvel build web-server'));
  },
      skip: skip);
}
