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
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
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
}
