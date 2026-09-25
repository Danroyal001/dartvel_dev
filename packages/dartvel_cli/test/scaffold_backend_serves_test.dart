// The backend `dartvel create` scaffolds has to compile and answer.
//
// The two functions every new project starts with were written as
// `handler()` and `handler({name, email, message})`. The generator reads a
// function called handler as a raw handler and calls it with the request,
// so the generated backend called `f0.handler(req)` on functions that take no
// positional argument, and a new project's backend did not compile: not
// under `dartvel dev`, and not as a server binary.
//
// So this writes the scaffold's own function files into a project, generates
// the backend the way `dartvel routes` does, starts it, and calls both.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/templates/project_templates.dart';
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
    project = Directory.systemTemp.createTempSync('dv_scaffold_backend_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: scaffold_backend_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    // The paths init_command writes them to.
    write('lib/backend/functions/health.get.dart',
        ProjectTemplates.healthFunctionTemplate);
    write('lib/backend/functions/contact.dart',
        ProjectTemplates.contactFormTemplate);

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

  /// Retries until the backend is listening or has exited.
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
      fail('the scaffolded backend never answered (exit $exited):\n$output');
    } finally {
      client.close(force: true);
    }
  }

  test('GET /api/health answers with the scaffold function', () async {
    final result = await call('GET', '/api/health');
    expect(result.status, 200, reason: '${result.body}\n$output');
    expect(jsonDecode(result.body), containsPair('status', 'ok'));
  });

  test('POST /api/contact takes the form fields', () async {
    final result = await call('POST', '/api/contact', json: <String, Object?>{
      'name': 'Ada',
      'email': 'ada@example.com',
      'message': 'Hello',
    });
    expect(result.status, 200, reason: '${result.body}\n$output');
    expect(jsonDecode(result.body), containsPair('success', true));
  });
}
