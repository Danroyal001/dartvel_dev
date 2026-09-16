// A backend function's body keeps the imports it was written against.
//
// A private @DVBackendFunction is lowered: its body is moved out of the file
// it was written in, because nothing outside that file can call a private
// function. Names the file itself declares were qualified through its import.
// Names it imported were not carried at all, so the first `jsonEncode`, the
// first relative helper import and the first `as` prefix in a body broke the
// whole generated backend with "Method not found", and a function that only
// read its own arguments was the only kind that compiled.
//
// This writes functions that use each kind of import, generates the backend
// the way `dartvel routes` does, starts it and calls them. One source also
// imports the generated client, which exports Flutter and which a server
// cannot compile, without using it: a function that compiled before this
// must still compile.
@Timeout(Duration(minutes: 10))
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

void main() {
  late Directory project;
  late Process server;
  late int port;
  final StringBuffer output = StringBuffer();
  int? exited;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/templates/project_templates.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    project = Directory.systemTemp.createTempSync('dv_fn_imports_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    final String deps = '''
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''';
    write('pubspec.yaml', '''
name: fn_imports_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
$deps
dartvel:
  backendHost: 127.0.0.1
''');
    write('pubspec_overrides.yaml', 'dependency_overrides:\n$deps');
    write('lib/backend/greeting.dart', '''
String greet(String name) => 'hello \$name';
''');
    write('lib/backend/functions/encode.dart', '''
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';

import '../greeting.dart';

@DVBackendFunction()
Future<String> _encode(String name) async =>
    jsonEncode(<String, Object?>{'greeting': greet(name), 'max': math.max(2, 3)});
''');
    write('lib/backend/functions/plain.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVBackendFunction()
Future<String> _plain() async => 'plain';
''');

    final String cliPackage = p.join(packages, 'dartvel_cli');
    final ProcessResult generated = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: project.path,
    );
    if (generated.exitCode != 0) {
      throw StateError(
          'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
    }
    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }

    port = await _freePort();
    server = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '.dart_tool/dartvel_server.dart'],
      workingDirectory: project.path,
      environment: <String, String>{'DARTVEL_PORT': '$port'},
    );
    server.stdout.transform(utf8.decoder).listen(output.write);
    server.stderr.transform(utf8.decoder).listen(output.write);
    unawaited(server.exitCode.then((int code) => exited = code));
  });

  tearDownAll(() {
    server.kill();
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<({int status, String body})> call(
    String method,
    String path, {
    Map<String, Object?>? json,
  }) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final DateTime deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline) && exited == null) {
        try {
          final HttpClientRequest request = await client.openUrl(
              method, Uri.parse('http://127.0.0.1:$port$path'));
          if (json != null) {
            request.headers.contentType = ContentType.json;
            // What the generated client sends: a POST without it is refused
            // as a cross-site request.
            request.headers.set('x-dartvel-csrf-token', 'a' * 32);
            request.write(jsonEncode(json));
          }
          final HttpClientResponse response = await request.close();
          return (
            status: response.statusCode,
            body: await response.transform(utf8.decoder).join(),
          );
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      fail('the backend never answered (exit $exited):\n$output');
    } finally {
      client.close(force: true);
    }
  }

  test('a body uses dart:, prefixed and relative imports', () async {
    final result =
        await call('POST', '/api/encode', json: <String, Object?>{'name': 'Ada'});
    expect(result.status, 200, reason: '${result.body}\n$output');
    expect(result.body, contains('hello Ada'));
    expect(result.body, contains('3'));
  });

  test('an unused import of the Flutter client does not break the server',
      () async {
    final result = await call('GET', '/api/plain');
    expect(result.status, 200, reason: '${result.body}\n$output');
    expect(result.body, contains('plain'));
  });
}
