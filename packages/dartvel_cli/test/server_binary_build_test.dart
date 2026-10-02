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
import 'package:dartvel_core/binary_payload.dart';
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
  sdk: ^3.13.0
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
      units: true,
      run: (String executable, List<String> arguments,
              {String? workingDirectory}) =>
          Process.run(executable, arguments,
              workingDirectory: workingDirectory),
    );
    expect(built.ok, isTrue, reason: built.lines.join('\n'));
    if (Platform.isLinux) {
      // The image resizer, which nothing here asks for, is a unit of its own
      // inside the file and is never mapped.
      expect(DVBinaryPayload.read(built.binary!.path)!.names.where((String n) => n.startsWith('unit.')),
          isNotEmpty, reason: built.lines.join('\n'));
    }
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
    // Stopped and waited for: on Windows a running executable cannot be
    // deleted, and the directory holding it is removed right after this.
    addTearDown(() async {
      server.kill();
      await server.exitCode;
    });

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

  group('Studio, served by the binary alone', () {
    /// Builds build/server carrying a web root and Studio at [mount],
    /// copies the one file somewhere empty, starts it and returns a way to
    /// ask it for a path.
    Future<
        Future<({int status, String type, String cache, String location, String body})> Function(
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
            '<body><script src="flutter_bootstrap.js" async></script>'
            '</body></html>');
      // A code asset big enough to be worth compressing.
      final String script =
          List<String>.generate(2000, (int i) => 'function f$i(){return $i}').join('\n');
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync(script);
      // What an older build left in the web output: a separately built
      // Studio. The binary never carries it as a web file.
      File(p.join(web.path, '__admin', 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<html><title>OLD STUDIO APP</title></html>');
      // What the web-server build writes for Studio, apart from the web root:
      // its data, and its code.
      final Directory studio =
          Directory(p.join(project.path, 'build', 'studio'));
      if (studio.existsSync()) studio.deleteSync(recursive: true);
      File(p.join(studio.path, 'data', 'graph.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"models":[]}');
      File(p.join(studio.path, 'parts', 'main.dart.js_7.part.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('/* Studio screens */');

      final DVServerBinaryResult built = await dvBuildServerBinary(
        root: project.path,
        library: library,
        dart: Platform.resolvedExecutable,
        webRoot: web.path,
        admin: mount,
        adminRoot: p.join(studio.path, 'data'),
        studioPartsRoot: p.join(studio.path, 'parts'),
        units: true,
        run: (String executable, List<String> arguments,
                {String? workingDirectory}) =>
            Process.run(executable, arguments,
                workingDirectory: workingDirectory),
      );
      expect(built.ok, isTrue, reason: built.lines.join('\n'));
      // The project's build output goes, so nothing can be served from it.
      web.deleteSync(recursive: true);
      studio.deleteSync(recursive: true);

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
      addTearDown(() async {
        server.kill();
        await server.exitCode;
      });

      Future<({int status, String type, String cache, String location, String body})> get(
          String path,
          {Map<String, String> headers = const <String, String>{}}) async {
        final HttpClient client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final HttpClientRequest request =
              await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
          request.followRedirects = false;
          headers.forEach(request.headers.set);
          final HttpClientResponse response = await request.close();
          return (
            status: response.statusCode,
            type: response.headers.value('content-type') ?? '',
            cache: response.headers.value('cache-control') ?? '',
            location: response.headers.value('location') ?? '',
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

      // The web app is read from the binary, in the encoding it was kept
      // in, and nothing of it was written beside the binary.
      final HttpClient raw = HttpClient()..autoUncompress = false;
      try {
        final HttpClientRequest request =
            await raw.getUrl(Uri.parse('http://127.0.0.1:$port/main.dart.js'));
        request.headers
          ..removeAll(HttpHeaders.acceptEncodingHeader)
          ..set(HttpHeaders.acceptEncodingHeader, 'br');
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 200);
        expect(response.headers.value('content-encoding'), 'br');
        expect(response.headers.value('etag'), isNotNull);
        expect(response.headers.value('cache-control'), 'public, no-cache');
        final String plain = await get('/main.dart.js').then((r) => r.body);
        expect(plain, script);
      } finally {
        raw.close(force: true);
      }
      final List<String> kept = <String>[
        for (final FileSystemEntity e
            in Directory(p.join(elsewhere.path, 'dartvel_data')).listSync())
          p.basename(e.path),
      ];
      expect(kept, isNot(contains('.web')));
      expect(kept, isNot(contains('.admin')));
      return get;
    }

    test('serves Studio at its mount as a page of the application, and its '
        'code from memory', () async {
      final get = await serveAlone(const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false));

      for (final String path in <String>['/__studio', '/__studio/']) {
        final page = await get(path);
        expect(page.status, 200, reason: path);
        expect(page.type, 'text/html; charset=utf-8', reason: path);
        // The application's own shell, rendered for Studio's route.
        expect(page.body, contains('<title>Studio · server_binary_probe</title>'),
            reason: path);
        expect(page.body, contains('flutter_bootstrap.js'), reason: path);
        expect(page.body,
            contains('<meta name="robots" content="noindex, nofollow">'),
            reason: path);
        expect(page.cache, contains('no-store'), reason: path);
      }
      // Nothing under the mount is a file: the application answers each of
      // these as it answers any path it does not serve.
      for (final String path in <String>[
        '/__studio/admin.css',
        '/__studio/index.html',
        '/__studio/graph.json',
      ]) {
        final answer = await get(path);
        final nowhere = await get(path.replaceFirst('/__studio/', '/__nowhr/'));
        expect(answer.status, nowhere.status, reason: path);
        expect(answer.body, nowhere.body, reason: path);
        expect(answer.body, isNot(contains('"models"')), reason: path);
        expect(answer.body, isNot(contains('<title>Studio')), reason: path);
      }
      // The project graph is data, through the API.
      final graph = await get('/__studio/api/graph');
      expect(graph.status, 200);
      expect(graph.body, contains('"models"'));
      // Studio's code, from memory, from the site root.
      final part = await get('/main.dart.js_7.part.js');
      expect(part.status, 200);
      expect(part.type, 'text/javascript; charset=utf-8');
      expect(part.cache, contains('no-store'));
      expect(part.body, '/* Studio screens */');

      // The web section carries nothing of Studio, whatever path it is asked
      // for by.
      final raw = await get('/__admin/index.html');
      expect(raw.body, isNot(contains('OLD STUDIO APP')));
      // And the site is still the site.
      expect((await get('/')).body, contains('The site'));
      expect((await get('/main.dart.js')).body, '// the site');
    }, skip: skip);

    test('sends an ungranted page request to the sign-in, and hides Studio\'s '
        'data and code exactly as a missing path', () async {
      final get = await serveAlone(const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true));

      // Inspect the first response: following it sees the public sign-in.
      for (final headers in <Map<String, String>>[
        const {},
        const {'authorization': 'Bearer dvs_not-a-session'},
      ]) {
        for (final path in [
          '/__studio',
          '/__studio/',
          '/__studio/index.html',
          '/__studio/anything',
        ]) {
          final page = await get(path, headers: headers);
          expect(page.status, 302, reason: path);
          expect(page.location,
              '/__studio/login?from=${Uri.encodeQueryComponent(path)}');
          expect(page.cache, contains('no-store'));
          expect(page.body, isEmpty);
        }
        for (final (String hiddenPath, String nowherePath) in <(String, String)>[
          ('/__studio/graph.json', '/__nowhr/graph.json'),
          ('/__studio/api/graph', '/__nowhr/api/graph'),
          ('/main.dart.js_7.part.js', '/main.dart.js_8.part.js'),
        ]) {
          final hidden = await get(hiddenPath, headers: headers);
          final nowhere = await get(nowherePath, headers: headers);
          expect(hidden.status, nowhere.status, reason: hiddenPath);
          expect(hidden.type, nowhere.type, reason: hiddenPath);
          expect(hidden.cache, nowhere.cache, reason: hiddenPath);
          expect(hidden.body.replaceAll('/__studio/', '/__nowhr/'),
              nowhere.body.replaceAll('main.dart.js_8', 'main.dart.js_7'),
              reason: hiddenPath);
          expect(hidden.body, isNot(contains('"models"')));
          expect(hidden.body, isNot(contains('Studio screens')));
        }
      }
      // The sign-in is a page of the application, for anybody.
      final login = await get('/__studio/login');
      expect(login.status, 200);
      expect(login.cache, contains('no-store'));
      expect(login.body, contains('<title>Studio · server_binary_probe</title>'));
      expect(login.body, contains('flutter_bootstrap.js'));
    }, skip: skip);
  });

  group('Studio turned off', () {
    // A release build that serves no Studio compiles none of it: the
    // generated backend puts every Studio reference behind dartvelStudio, and
    // the build passes -Ddartvel.studio=false, so AOT drops the dashboard,
    // its API and its grants. Its files are not carried, and its mount is a
    // path like any other the application does not serve.
    Future<File> buildWith({required bool studio}) async {
      final ProcessResult generated = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'dartvel_cli:dartvel', 'routes'],
        workingDirectory: project.path,
      ).timeout(const Duration(minutes: 5));
      expect(generated.exitCode, 0, reason: '${generated.stdout}\n${generated.stderr}');
      final Directory web = Directory(p.join(project.path, 'build', 'web'));
      if (web.existsSync()) web.deleteSync(recursive: true);
      File(p.join(web.path, 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<html><head><title>The site</title></head><body></body></html>');
      File(p.join(web.path, '__admin', 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<html><title>Studio dashboard 7c1d</title></html>');
      const DVAdminMount mount = DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);
      final DVServerBinaryResult built = await dvBuildServerBinary(
        root: project.path,
        library: library,
        dart: Platform.resolvedExecutable,
        webRoot: web.path,
        admin: studio ? mount : null,
        adminRoot: p.join(web.path, '__admin'),
        units: true,
        defines: <String, String>{'dartvel.studio': '$studio'},
        run: (String executable, List<String> arguments, {String? workingDirectory}) =>
            Process.run(executable, arguments, workingDirectory: workingDirectory),
      );
      expect(built.ok, isTrue, reason: built.lines.join('\n'));
      final File kept = File(p.join(project.path, 'build', studio ? 'server-on' : 'server-off'));
      built.binary!.copySync(kept.path);
      return kept;
    }

    test('carries no Studio code or files, and is smaller for it', () async {
      final File on = await buildWith(studio: true);
      final File off = await buildWith(studio: false);
      // What only Studio's server has: its class names, which an AOT
      // snapshot keeps, and its own messages.
      const List<String> studioOnly = <String>['DVAdminServer', 'DVStudioApi', 'DVStudioGrants', 'Missing CSRF header.'];
      bool carries(File binary, String text) => latin1.decode(binary.readAsBytesSync()).contains(text);
      for (final String marker in studioOnly) {
        expect(carries(on, marker), isTrue, reason: 'a Studio build carries $marker');
        expect(carries(off, marker), isFalse, reason: 'a build without Studio carries $marker');
      }
      final DVBinaryPayload payload = DVBinaryPayload.read(off.path)!;
      expect(payload.names, isNot(contains('admin.mount')));
      final ({int offset, int length}) at = payload.locate('assets')!;
      final DVAssetPack pack = DVAssetPack.open(off.path, offset: at.offset, length: at.length)!;
      expect(pack.paths.where((String path) => path.startsWith('admin/')), isEmpty);
      expect(off.lengthSync(), lessThan(on.lengthSync()));
    }, skip: skip);

    test('answers its mount as a path nobody serves', () async {
      final File off = await buildWith(studio: false);
      final Directory elsewhere = Directory.systemTemp.createTempSync('dv_server_binary_nostudio_');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      final File copy = off.copySync(p.join(elsewhere.path, 'server'));
      await Process.run('chmod', <String>['+x', copy.path]);
      final int port = await _freePort();
      final Process server = await Process.start(copy.path, const <String>[],
          workingDirectory: elsewhere.path,
          includeParentEnvironment: false,
          environment: <String, String>{..._serverEnvironment(), 'DARTVEL_PORT': '$port'});
      final StringBuffer output = StringBuffer();
      server.stdout.transform(utf8.decoder).listen(output.write);
      server.stderr.transform(utf8.decoder).listen(output.write);
      addTearDown(() async {
        server.kill();
        await server.exitCode;
      });
      final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      addTearDown(() => client.close(force: true));
      Future<(int, String)> get(String path) async {
        final HttpClientRequest request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
        request.followRedirects = false;
        final HttpClientResponse response = await request.close();
        return (response.statusCode, await response.transform(utf8.decoder).join());
      }
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
      while (true) {
        try {
          await get('/api/ping');
          break;
        } on SocketException {
          if (DateTime.now().isAfter(deadline)) fail('the binary never answered:\n$output');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      for (final String path in <String>['/__studio', '/__studio/', '/__studio/login', '/__studio/api/access']) {
        final (int status, String body) = await get(path);
        final (int nowhereStatus, String nowhereBody) = await get(path.replaceFirst('__studio', '__nowhr'));
        expect(status, nowhereStatus, reason: path);
        expect(body.replaceAll('/__studio', '/__nowhr'), nowhereBody, reason: path);
        expect(body, isNot(contains('Studio dashboard 7c1d')), reason: path);
      }
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
