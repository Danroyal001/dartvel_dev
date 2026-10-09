// The generated backend's client-logs endpoint, served and posted to.
//
// With `dartvel.logging.ship.enabled`, devices send their warn-and-above
// records to the deployment's own backend, and the backend writes them into
// its own log stream. This generates a real backend, starts it, posts the way
// DVLogShipper does, and asserts on what the server answered and what it
// printed -- never on the generated text. The silent failures:
//
//  * a credential a client sent written through to the server's stdout;
//  * an install id that is really an identity accepted;
//  * an endpoint served by an application that never turned shipping on,
//    so devices could post logs nobody agreed to collect.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String secret = 'hunter2-not-for-logs';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String secret = 'hunter2-not-for-logs';

Future<int> post(int port, Object body) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .postUrl(Uri.parse('http://127.0.0.1:$port/api/_dartvel/client-logs'));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> batch(String install) => <String, Object?>{
      'install': install,
      'release': '2.0.0',
      'platform': 'android',
      'records': <Object?>[
        <String, Object?>{
          'time': '2026-10-09T11:00:00.000Z',
          'level': 'error',
          'message': 'payment declined CLIENT-LINE',
          'tag': 'checkout',
          'context': <String, Object?>{'orderId': 'o-9', 'password': secret},
        },
      ],
    };

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    out['stored'] = await post(port, batch('0123456789abcdef0123456789abcdef'));
    out['identity'] = await post(port, batch('person@example.com'));
  } finally {
    await handle.stop();
  }
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

Future<String> packagesDirectory() async {
  final Uri cli = (await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
  ))!;
  return p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

Future<Directory> backendProject(String packages, String logging) async {
  final Directory project =
      Directory.systemTemp.createTempSync('dv_client_logs_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: client_logs_probe
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
$logging
''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong';
''');
  write('bin/probe.dart', _probe);

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
  return project;
}

void main() {
  late Directory shipping;
  late Directory silent;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    shipping = await backendProject(packages, '''
  logging:
    ship:
      enabled: true
''');
    silent = await backendProject(packages, '  backendPort: 8089');
  });

  tearDownAll(() {
    for (final Directory project in <Directory>[shipping, silent]) {
      if (project.existsSync()) project.deleteSync(recursive: true);
    }
  });

  Future<(Map<String, Object?>, String)> probe(Directory project) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 3));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String candidate) => candidate.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    return (
      jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>,
      output,
    );
  }

  test('client records join the server stream, redacted, as the client',
      () async {
    final (Map<String, Object?> answers, String output) =
        await probe(shipping);

    expect(answers['stored'], 201);
    expect(answers['identity'], 400,
        reason: 'an install id is 32 hex characters, never an identity');
    final Map<String, Object?> written = const LineSplitter()
        .convert(output)
        .where((String line) => line.contains('CLIENT-LINE'))
        .map((String line) => jsonDecode(line) as Map<String, Object?>)
        .single;
    expect(written['tag'], 'checkout');
    expect(written['level'], 'error');
    expect((written['context']! as Map<String, Object?>)['client'],
        <String, Object?>{
          'install': '0123456789abcdef0123456789abcdef',
          'release': '2.0.0',
          'platform': 'android',
        });
    expect(output, isNot(contains(secret)));
  });

  test('an application that did not turn shipping on serves no endpoint',
      () async {
    final (Map<String, Object?> answers, String output) = await probe(silent);

    expect(answers['stored'], 404);
    expect(output, isNot(contains('CLIENT-LINE')));
  });
}
