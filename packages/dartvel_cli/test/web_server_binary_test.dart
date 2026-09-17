// `dartvel build web-server` is one file: the whole deployment.
//
// What it must be, end to end. A project made by `dartvel create` with a
// model and a backend function is built with the real command. Then only the
// binary is copied into an empty directory and started there, with no
// DATABASE_URL, and it has to:
//
//  * create its SQLite file on the first run, with the model's table in it;
//  * render a page on request, from a shell it carries inside itself;
//  * serve the web app's code, main.dart.js, from inside itself too;
//  * write through a backend function into that SQLite file;
//  * and after a stop and a second start, still have what was written.
//
// Every one of those can look done while being wrong: a binary that runs
// only beside build/web, a database that is in memory, a page answered with
// the bare shell. So each is asked of the running binary, never of the build
// output.
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVDatabaseAdapter,
        DVDatabaseConnection,
        DVDatabaseEngine,
        DVDatabaseSessionStore,
        DVIssuedSession,
        DVSessions,
        DVTenants;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<int> _freePort() async {
  final ServerSocket socket =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

bool _onPath(String executable) {
  final ProcessResult which = Process.runSync(
      Platform.isWindows ? 'where' : 'which', <String>[executable]);
  return which.exitCode == 0;
}

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
    Uri.parse('package:dartvel_cli/src/build/server_binary.dart'),
  )!;
  final String packages = p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
  final Object skip = !(Platform.isLinux && Platform.version.contains('x64'))
      ? 'the native server library a web-server binary embeds is prebuilt '
          'for linux-x64'
      : !File(p.join(packages, 'dartvel_shelf', 'lib', 'native', 'linux-x64',
                  'libdartvel_shelf.so'))
              .existsSync()
          ? 'no linux-x64 native server library has been built'
          : !_onPath('flutter')
              ? 'a web-server build runs flutter build web'
              : false;

  late Directory work;
  late File binary;
  late String buildOutput;

  setUpAll(() async {
    if (skip != false) return;
    work = Directory.systemTemp.createTempSync('dv_web_server_binary_');
    final ProcessResult created = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(packages, 'dartvel_cli', '.dart_tool', 'package_config.json')}',
        p.join(packages, 'dartvel_cli', 'bin', 'dartvel.dart'),
        'create',
        'shop',
      ],
      workingDirectory: work.path,
    );
    final Directory project = Directory(p.join(work.path, 'shop'));
    expect(File(p.join(project.path, 'pubspec.yaml')).existsSync(), isTrue,
        reason: '${created.stdout}\n${created.stderr}');

    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    // The framework from this checkout, where the scaffold names versions.
    write('pubspec_overrides.yaml', <String>[
      'dependency_overrides:',
      for (final String name in <String>[
        'dartvel_cli',
        'dartvel_core',
        'dartvel_flutter',
        'dartvel_shelf',
      ]) ...<String>['  $name:', '    path: ${p.join(packages, name)}'],
    ].join('\n'));
    write('lib/models/note.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String id;
  final String text;

  const _Note({required this.id, required this.text});
}
''');
    write('lib/backend/functions/add_note.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<int> _addNote(String text) async {
  await const DVDatabase().execute(
    'INSERT INTO notes (id, text) VALUES (?, ?)',
    <Object?>[DateTime.now().microsecondsSinceEpoch.toString(), text],
  );
  final List<Map<String, Object?>> rows =
      await const DVDatabase().query('SELECT id FROM notes');
  return rows.length;
}
''');
    write('lib/backend/functions/notes.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<List<String>> _notes() async => <String>[
      for (final Map<String, Object?> row
          in await const DVDatabase().query('SELECT text FROM notes'))
        '\${row['text']}',
    ];
''');
    // The admin, asked for. This is a release build, which carries a
    // dashboard only when the project says so.
    final File pubspec = File(p.join(project.path, 'pubspec.yaml'));
    final String declared = pubspec.readAsStringSync();
    expect(declared, contains('\ndartvel:\n'));
    pubspec.writeAsStringSync(declared.replaceFirst(
        '\ndartvel:\n', '\ndartvel:\n  admin:\n    enabled: true\n'));

    final ProcessResult resolved = await Process.run(
      'flutter',
      <String>['pub', 'get'],
      workingDirectory: project.path,
      runInShell: true,
    );
    expect(resolved.exitCode, 0,
        reason: '${resolved.stdout}\n${resolved.stderr}');

    final ProcessResult built = await Process.run(
      'dart',
      <String>[
        'run',
        'dartvel_cli:dartvel',
        'build',
        'web-server',
        '--no-auto-install',
      ],
      workingDirectory: project.path,
      runInShell: true,
    );
    buildOutput = '${built.stdout}\n${built.stderr}';
    expect(built.exitCode, 0, reason: buildOutput);
    final File output = File(p.join(project.path, 'build', 'server'));
    expect(output.existsSync(), isTrue, reason: buildOutput);

    // Alone. Nothing of the project, the build directory or this checkout.
    final Directory deploy = Directory(p.join(work.path, 'deploy'))
      ..createSync();
    binary = output.copySync(p.join(deploy.path, 'server'));
    await Process.run('chmod', <String>['755', binary.path]);
  });

  tearDownAll(() {
    if (skip == false) work.deleteSync(recursive: true);
  });

  /// Starts the binary with nothing configured, and returns once it answers.
  Future<({Process process, int port, StringBuffer output})> start() async {
    final int port = await _freePort();
    final Process process = await Process.start(
      binary.path,
      const <String>[],
      workingDirectory: binary.parent.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        'PATH': '/usr/bin:/bin',
        'DARTVEL_PORT': '$port',
      },
    );
    final StringBuffer output = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(output.write);
    process.stderr.transform(utf8.decoder).listen(output.write);
    int? exited;
    unawaited(process.exitCode.then((int code) => exited = code));
    final HttpClient client = HttpClient();
    try {
      final DateTime deadline = DateTime.now().add(const Duration(minutes: 1));
      while (DateTime.now().isBefore(deadline) && exited == null) {
        try {
          final HttpClientResponse response = await (await client
                  .getUrl(Uri.parse('http://127.0.0.1:$port/api/health')))
              .close();
          await response.drain<void>();
          return (process: process, port: port, output: output);
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    } finally {
      client.close(force: true);
    }
    process.kill();
    fail('the binary never answered (exit $exited):\n$output');
  }

  Future<({int status, String type, String body})> request(
    int port,
    String method,
    String path, {
    Object? json,
    String? bearer,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
      if (json != null) {
        request.headers.contentType = ContentType.json;
        // What the generated client sends with a POST.
        request.headers.set('x-dartvel-csrf-token', 'a' * 32);
        request.write(jsonEncode(json));
      }
      final HttpClientResponse response = await request.close();
      return (
        status: response.statusCode,
        type: response.headers.contentType?.mimeType ?? '',
        body: await response.transform(utf8.decoder).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  test('the copied binary creates its database, serves the app and keeps '
      'what it wrote across a restart', () async {
    final File database = File(p.join(binary.parent.path, 'dartvel_data', 'data.db'));
    expect(database.existsSync(), isFalse);

    final first = await start();
    try {
      expect(database.existsSync(), isTrue,
          reason: 'no SQLite file beside the binary:\n${first.output}');
      expect('${first.output}', contains('notes'),
          reason: 'the model table was not reported as created');

      final page = await request(first.port, 'GET', '/');
      expect(page.status, 200, reason: page.body);
      expect(page.type, 'text/html');
      expect(page.body, contains('<title>'),
          reason: 'the page is assembled per request, with its head');

      final script = await request(first.port, 'GET', '/main.dart.js');
      expect(script.status, 200);
      expect(script.body.length, greaterThan(10000),
          reason: 'the web app code, served from inside the binary');

      final written = await request(first.port, 'POST', '/api/add_note',
          json: <String, Object?>{'text': 'kept across restarts'});
      expect(written.status, 200, reason: '${written.body}\n${first.output}');
    } finally {
      first.process.kill();
      await first.process.exitCode;
    }

    final second = await start();
    try {
      expect('${second.output}', isNot(contains('creating')),
          reason: 'the second run reuses the file');
      final notes = await request(second.port, 'GET', '/api/notes');
      expect(notes.status, 200, reason: notes.body);
      expect(notes.body, contains('kept across restarts'));
    } finally {
      second.process.kill();
      await second.process.exitCode;
    }
  }, skip: skip);

  test('the copied binary serves the admin dashboard to a person granted '
      'Studio and to nobody else', () async {
    // Carried, and not among the web files the binary serves to anybody.
    final DVBinaryPayload? payload = DVBinaryPayload.read(binary.path);
    expect(payload?.names, contains('admin'), reason: buildOutput);
    expect(
        dvUnpackFiles(payload!.section('web'))
            .keys
            .where((String path) => path.startsWith('__admin/')),
        isEmpty);

    final run = await start();
    try {
      // No session: the mount answers as a path the application does not
      // serve, the same length so nothing can differ by it.
      final nowhere = await request(run.port, 'GET', '/__nowhr/');
      final hidden = await request(run.port, 'GET', '/__studio/');
      expect(hidden.status, nowhere.status);
      expect(hidden.type, nowhere.type);
      expect(hidden.body.replaceAll('/__studio/', '/__nowhr/'), nowhere.body);
      expect(hidden.body, isNot(contains('src="admin.js"')));
      final hiddenGraph = await request(run.port, 'GET', '/__studio/graph.json');
      expect(hiddenGraph.body, isNot(contains('"models"')));
      // And the dashboard's files are not web files under any path.
      final raw = await request(run.port, 'GET', '/__admin/graph.json');
      expect(raw.body, isNot(contains('"models"')));

      // A session of the application's own, issued in the binary's database
      // on the tenant the server resolves for its own requests -- by the
      // same resolver, rather than by assuming which one that is.
      final DateTime waitForLine =
          DateTime.now().add(const Duration(seconds: 10));
      RegExpMatch? listening;
      while ((listening = RegExp(r'listening on http://([^:/\s]+):')
                  .firstMatch('${run.output}')) ==
              null &&
          DateTime.now().isBefore(waitForLine)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(listening, isNotNull, reason: '${run.output}');
      final String tenant = const DVTenants()
              .resolve(Uri(scheme: 'http', host: listening!.group(1))) ??
          DVTenants.defaultTenant;
      final DVDatabaseAdapter database = DVDatabaseConnection(
        engine: DVDatabaseEngine.sqlite,
        database: p.join(binary.parent.path, 'dartvel_data', 'data.db'),
      ).open();
      final DVIssuedSession issued =
          await DVSessions(store: DVDatabaseSessionStore(database))
              .create('operator', tenant: tenant);

      // Signed in, and granted nothing: every customer of the application is
      // exactly this, and gets exactly what a path that does not exist gets.
      final signedIn =
          await request(run.port, 'GET', '/__studio/', bearer: issued.token);
      final signedInNowhere =
          await request(run.port, 'GET', '/__nowhr/', bearer: issued.token);
      expect(signedIn.status, signedInNowhere.status);
      expect(signedIn.type, signedInNowhere.type);
      expect(signedIn.body.replaceAll('/__studio/', '/__nowhr/'),
          signedInNowhere.body);
      expect(signedIn.body, isNot(contains('src="admin.js"')));
      final signedInGraph = await request(
          run.port, 'GET', '/__studio/graph.json',
          bearer: issued.token);
      expect(signedInGraph.body, isNot(contains('"models"')));

      // Granted, with the command an operator runs against the binary's own
      // database while it is serving.
      final ProcessResult granted = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          '--packages=${p.join(packages, 'dartvel_cli', '.dart_tool', 'package_config.json')}',
          p.join(packages, 'dartvel_cli', 'bin', 'dartvel.dart'),
          'admin',
          'grant',
          'operator',
          '--tenant',
          tenant,
          '--database',
          p.join(binary.parent.path, 'dartvel_data', 'data.db'),
        ],
      );
      expect(granted.exitCode, 0,
          reason: '${granted.stdout}\n${granted.stderr}');

      final page =
          await request(run.port, 'GET', '/__studio/', bearer: issued.token);
      expect(page.status, 200, reason: '${page.body}\n${run.output}');
      expect(page.type, 'text/html');
      expect(page.body, contains('src="admin.js"'),
          reason: 'the dashboard, not the site shell');
      final graph = await request(run.port, 'GET', '/__studio/graph.json',
          bearer: issued.token);
      expect(graph.status, 200);
      expect(graph.type, 'application/json');
      expect(jsonDecode(graph.body), isA<Map<String, Object?>>());

      // The control: a token that is not a live session is nobody.
      final forged = await request(run.port, 'GET', '/__studio/graph.json',
          bearer: 'dvs_not-a-session');
      expect(forged.body, isNot(contains('"models"')));
    } finally {
      run.process.kill();
      await run.process.exitCode;
    }
  }, skip: skip);
}
