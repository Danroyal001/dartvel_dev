// `dartvel build server`: the backend as one executable file.
//
// The specification's monolith is a single native backend binary, and every
// piece around it already assumed one: dartvel infra's units start
// /opt/<app>/server, and the image dartvel deploy writes copies build/ and
// runs /app/server. Nothing produced that file. `dartvel deploy --target
// server` asked `dartvel build --platform server`, which was not a platform.
//
// So this runs the real command on a real project, then copies the one file
// it wrote into an empty directory, starts it there and asks it for a backend
// function. A binary that still needs the project beside it -- the package's
// native library, the generated sources -- passes a check on the file and
// fails this.
@Timeout(Duration(minutes: 15))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<int> _freePort() async {
  final ServerSocket socket =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
    Uri.parse('package:dartvel_cli/src/build/server_binary.dart'),
  )!;
  // lib/src/build/server_binary.dart -> packages/
  final String packages = p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
  final File library = File(p.join(packages, 'dartvel_shelf', 'lib', 'native',
      'linux-x64', 'libdartvel_shelf.so'));
  final Object skip = !(Platform.isLinux && Platform.version.contains('x64'))
      ? 'the library a server build embeds is prebuilt for linux-x64'
      : !library.existsSync()
          ? 'no linux-x64 native server library has been built'
          : false;

  late Directory project;

  setUpAll(() async {
    if (skip != false) return;
    project = Directory.systemTemp.createTempSync('dv_server_binary_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    final String overrides = <String>[
      'dartvel_cli',
      'dartvel_core',
      'dartvel_shelf',
    ].map((String name) => '  $name:\n    path: ${p.join(packages, name)}').join('\n');
    write('pubspec.yaml', '''
name: server_binary_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dev_dependencies:
  dartvel_cli:
    path: ${p.join(packages, 'dartvel_cli')}
dartvel:
  backendHost: 127.0.0.1
''');
    write('pubspec_overrides.yaml', 'dependency_overrides:\n$overrides\n');
    write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong from one file';
''');
    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() {
    if (skip == false && project.existsSync()) {
      project.deleteSync(recursive: true);
    }
  });

  test('dartvel build server writes one file that serves the backend alone',
      () async {
    final ProcessResult built = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'run',
        'dartvel_cli:dartvel',
        'build',
        'server',
        '--no-auto-install',
      ],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 10));
    expect(built.exitCode, 0, reason: '${built.stdout}\n${built.stderr}');

    final File binary = File(p.join(project.path, 'build', 'server'));
    expect(binary.existsSync(), isTrue, reason: '${built.stdout}');
    expect('${built.stdout}', contains('build/server'));

    // Alone: an empty directory, with nothing of the project or the package.
    final Directory elsewhere =
        Directory.systemTemp.createTempSync('dv_server_binary_run_');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final File copy = binary.copySync(p.join(elsewhere.path, 'server'));
    await Process.run('chmod', <String>['+x', copy.path]);

    final int port = await _freePort();
    final Process server = await Process.start(
      copy.path,
      const <String>[],
      workingDirectory: elsewhere.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'DARTVEL_PORT': '$port',
      },
    );
    final StringBuffer output = StringBuffer();
    server.stdout.transform(utf8.decoder).listen(output.write);
    server.stderr.transform(utf8.decoder).listen(output.write);
    addTearDown(() => server.kill());

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    addTearDown(() => client.close(force: true));
    String? body;
    int? status;
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final HttpClientResponse response = await (await client
                .getUrl(Uri.parse('http://127.0.0.1:$port/api/ping')))
            .close();
        status = response.statusCode;
        body = await response.transform(utf8.decoder).join();
        break;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    expect(status, 200, reason: 'the binary never answered:\n$output');
    expect(body, contains('pong from one file'));
  }, skip: skip);

  group('the native library a server build embeds', () {
    test('is found through the project package configuration', () {
      final Directory root =
          Directory.systemTemp.createTempSync('dv_server_binary_lib_');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory shelf = Directory(p.join(root.path, 'shelf'))
        ..createSync();
      File(p.join(shelf.path, 'lib', 'native', 'linux-x64', 'libdartvel_shelf.so'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);
      File(p.join(root.path, 'app', '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{
              'name': 'dartvel_shelf',
              'rootUri': '../../shelf',
              'packageUri': 'lib/',
            },
          ],
        }));

      final DVServerLibraryLookup found = dvLocateServerLibrary(
        p.join(root.path, 'app'),
        subdir: 'linux-x64',
        name: 'libdartvel_shelf.so',
      );
      expect(found.file?.readAsBytesSync(), <int>[1, 2, 3]);

      // The control: a host the package ships nothing for is refused by
      // name, before a build starts that could only fail at its first
      // request.
      final DVServerLibraryLookup missing = dvLocateServerLibrary(
        p.join(root.path, 'app'),
        subdir: 'linux-arm64',
        name: 'libdartvel_shelf.so',
      );
      expect(missing.file, isNull);
      expect(missing.problem, contains('linux-arm64'));
    });

    test('is refused when the project does not resolve dartvel_shelf', () {
      final Directory root =
          Directory.systemTemp.createTempSync('dv_server_binary_nolib_');
      addTearDown(() => root.deleteSync(recursive: true));
      final DVServerLibraryLookup lookup = dvLocateServerLibrary(
        root.path,
        subdir: 'linux-x64',
        name: 'libdartvel_shelf.so',
      );
      expect(lookup.file, isNull);
      expect(lookup.problem, contains('dartvel_shelf'));
    });
  });
}
