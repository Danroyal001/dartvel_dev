// The backend as one executable file, which `dartvel build web-server` writes.
//
// The specification's monolith is a single native backend binary, and every
// piece around it already assumed one: dartvel infra's units start
// /opt/<app>/server, and the image dartvel deploy writes copies build/ and
// runs /app/server. Nothing produced that file.
//
// So this generates a real project's backend, compiles it the way the
// web-server build does, then copies the one file into an empty directory,
// starts it there and asks it for a backend function.
// A binary that still needs the project beside it -- the package's
// native library, the generated sources -- passes a check on the file and
// fails this.
@Timeout(Duration(minutes: 15))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/build/admin_mount.dart';
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

/// The parent's search path, and on Windows the SystemRoot a process needs
/// to load a DLL and open a socket, and the TEMP the binary writes its
/// server library into.
Map<String, String> _serverEnvironment() => <String, String>{
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      if (Platform.isWindows)
        for (final String name in const <String>['SystemRoot', 'TEMP', 'TMP'])
          if (Platform.environment[name] != null)
            name: Platform.environment[name]!,
    };

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
    Uri.parse('package:dartvel_cli/src/build/server_binary.dart'),
  )!;
  // lib/src/build/server_binary.dart -> packages/
  final String packages = p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
  // The library for the host this runs on; CI runs it on each of them.
  final host = dvHostServerLibrary();
  final File library = File(p.join(
      packages, 'dartvel_shelf', 'lib', 'native', host.subdir, host.name));
  final Object skip = !library.existsSync()
      ? 'no ${host.subdir} native server library has been built'
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

  test('the compiled backend is one file that serves alone', () async {
    final ProcessResult generated = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'dartvel_cli:dartvel', 'routes'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 5));
    expect(generated.exitCode, 0,
        reason: '${generated.stdout}\n${generated.stderr}');

    final DVServerBinaryResult built = await dvBuildServerBinary(
      root: project.path,
      library: library,
      dart: Platform.resolvedExecutable,
      run: (String executable, List<String> arguments,
              {String? workingDirectory}) =>
          Process.run(executable, arguments,
              workingDirectory: workingDirectory),
    );
    expect(built.ok, isTrue, reason: built.lines.join('\n'));
    final File binary = File(p.join(
        project.path, dvServerBinaryPath(windows: Platform.isWindows)));
    expect(built.binary?.path, binary.path);
    expect(built.lines.first,
        contains(dvServerBinaryPath(windows: Platform.isWindows)));

    // Alone: an empty directory, with nothing of the project or the package.
    final Directory elsewhere =
        Directory.systemTemp.createTempSync('dv_server_binary_run_');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final File copy =
        binary.copySync(p.join(elsewhere.path, p.basename(binary.path)));
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['+x', copy.path]);
    }

    final int port = await _freePort();
    final Process server = await Process.start(
      copy.path,
      const <String>[],
      workingDirectory: elsewhere.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        ..._serverEnvironment(),
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

  group('the admin dashboard, served by the binary alone', () {
    /// Builds build/server carrying a web root and the dashboard at [mount],
    /// copies the one file somewhere empty, starts it and returns a way to
    /// ask it for a path.
    Future<
        Future<({int status, String type, String cache, String body})> Function(
            String path, {Map<String, String> headers})> serveAlone(
        DVAdminMount mount) async {
      final ProcessResult generated = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'dartvel_cli:dartvel', 'routes'],
        workingDirectory: project.path,
      ).timeout(const Duration(minutes: 5));
      expect(generated.exitCode, 0,
          reason: '${generated.stdout}\n${generated.stderr}');

      final Directory web = Directory(p.join(project.path, 'build', 'web'));
      if (web.existsSync()) web.deleteSync(recursive: true);
      File(p.join(web.path, 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<html><head><title>The site</title></head>'
            '<body></body></html>');
      // What the web-server build writes: the dashboard under __admin in the
      // web output, which the binary must not serve as a web file.
      final Map<String, String> dashboard = <String, String>{
        'index.html': '<html><title>Studio dashboard</title></html>',
        'admin.css': 'body { color: black; }',
        'admin.js': 'console.log("studio");',
        'graph.json': '{"models":[]}',
      };
      for (final MapEntry<String, String> file in dashboard.entries) {
        File(p.join(web.path, '__admin', file.key))
          ..createSync(recursive: true)
          ..writeAsStringSync(file.value);
      }

      final DVServerBinaryResult built = await dvBuildServerBinary(
        root: project.path,
        library: library,
        dart: Platform.resolvedExecutable,
        webRoot: web.path,
        admin: mount,
        adminRoot: p.join(web.path, '__admin'),
        run: (String executable, List<String> arguments,
                {String? workingDirectory}) =>
            Process.run(executable, arguments,
                workingDirectory: workingDirectory),
      );
      expect(built.ok, isTrue, reason: built.lines.join('\n'));
      // The project's build output goes, so nothing can be served from it.
      web.deleteSync(recursive: true);

      final Directory elsewhere =
          Directory.systemTemp.createTempSync('dv_server_binary_admin_');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      final File copy =
          built.binary!.copySync(
              p.join(elsewhere.path, p.basename(built.binary!.path)));
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['+x', copy.path]);
      }

      final int port = await _freePort();
      final Process server = await Process.start(
        copy.path,
        const <String>[],
        workingDirectory: elsewhere.path,
        includeParentEnvironment: false,
        environment: <String, String>{
          ..._serverEnvironment(),
          'DARTVEL_PORT': '$port',
        },
      );
      final StringBuffer output = StringBuffer();
      server.stdout.transform(utf8.decoder).listen(output.write);
      server.stderr.transform(utf8.decoder).listen(output.write);
      addTearDown(() => server.kill());

      Future<({int status, String type, String cache, String body})> get(
          String path,
          {Map<String, String> headers = const <String, String>{}}) async {
        final HttpClient client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final HttpClientRequest request =
              await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
          headers.forEach(request.headers.set);
          final HttpClientResponse response = await request.close();
          return (
            status: response.statusCode,
            type: response.headers.value('content-type') ?? '',
            cache: response.headers.value('cache-control') ?? '',
            body: await response.transform(utf8.decoder).join(),
          );
        } finally {
          client.close(force: true);
        }
      }

      final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
      while (true) {
        try {
          await get('/api/ping');
          break;
        } on SocketException {
          if (DateTime.now().isAfter(deadline)) {
            fail('the binary never answered:\n$output');
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return get;
    }

    test('serves the dashboard at its mount, each file as its own type',
        () async {
      final get = await serveAlone(const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false));

      for (final String path in <String>['/__studio', '/__studio/']) {
        final page = await get(path);
        expect(page.status, 200, reason: path);
        expect(page.type, 'text/html; charset=utf-8', reason: path);
        expect(page.body, contains('Studio dashboard'), reason: path);
      }
      final Map<String, String> types = <String, String>{
        '/__studio/admin.css': 'text/css; charset=utf-8',
        '/__studio/admin.js': 'text/javascript; charset=utf-8',
        '/__studio/graph.json': 'application/json; charset=utf-8',
      };
      for (final MapEntry<String, String> file in types.entries) {
        final answer = await get(file.key);
        expect(answer.status, 200, reason: file.key);
        expect(answer.type, file.value, reason: file.key);
        expect(answer.cache, contains('no-store'), reason: file.key);
      }

      // The web section carries none of it: the dashboard's files are not
      // web files, whatever path they are asked for by.
      final raw = await get('/__admin/index.html');
      expect(raw.body, isNot(contains('Studio dashboard')));
      // And the site is still the site.
      expect((await get('/')).body, contains('The site'));
    }, skip: skip);

    test('answers a caller with no session exactly as a route that does not '
        'exist', () async {
      final get = await serveAlone(const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true));

      // The same path length, so nothing about the answer can differ by it.
      final nowhere = await get('/__nowhr/');
      for (final String path in <String>[
        '/__studio/',
        '/__studio/graph.json',
      ]) {
        final hidden = await get(path);
        expect(hidden.body, isNot(contains('Studio dashboard')), reason: path);
        expect(hidden.body, isNot(contains('models')), reason: path);
      }
      final hidden = await get('/__studio/');
      expect(hidden.status, nowhere.status);
      expect(hidden.type, nowhere.type);
      expect(hidden.cache, nowhere.cache);
      expect(hidden.body.replaceAll('/__studio/', '/__nowhr/'), nowhere.body);

      // A session token that is not a live session gets what it gets on any
      // other route, and not the dashboard.
      const Map<String, String> forged = <String, String>{
        'authorization': 'Bearer dvs_not-a-session',
      };
      final forgedHidden = await get('/__studio/', headers: forged);
      final forgedNowhere = await get('/__nowhr/', headers: forged);
      expect(forgedHidden.status, forgedNowhere.status);
      expect(forgedHidden.body, isNot(contains('Studio dashboard')));
    }, skip: skip);
  });

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
