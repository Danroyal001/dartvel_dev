// The generated backend's crash endpoint, served and posted to.
//
// `sink: dartvel` sends reports to the deployment's own backend, and the
// generated backend is what has to be there to receive them. This generates a
// real backend, starts it, and posts reports the way DVCrashSink.dartvel
// does, asserting on what the server answered and what it wrote -- never on
// the generated text. The silent failures:
//
//  * a payload logged: the endpoint that refused it, or the store that failed
//    to keep it and quoted the values in its error;
//  * a resend stored twice;
//  * one install's crash loop filling the table;
//  * an endpoint served by an application that declared no sink, accepting
//    reports nothing will read.
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String secret = 'CARD-4111111111111111';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String secret = 'CARD-4111111111111111';

/// A database that is down, and says so with the values it was given.
class Broken implements DVDatabaseAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('database down while writing $secret');
}

Future<Map<String, Object?>> post(int port, List<int> bytes,
    [Map<String, String> headers = const <String, String>{}]) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .postUrl(Uri.parse('http://127.0.0.1:$port/api/_dartvel/crashes'));
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.add(bytes);
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
    };
  } finally {
    client.close(force: true);
  }
}

List<int> report(String id, String installId, String message) =>
    utf8.encode(jsonEncode(DVCrashReport(
      id: id,
      kind: DVCrashKind.fatal,
      errorType: 'StateError',
      message: message,
      frames: const <DVCrashFrame>[DVCrashFrame(function: 'main')],
      fingerprint: 'f',
      context: DVCrashContext(release: '1.0.0', installId: installId),
      occurredAt: DateTime.utc(2026, 9, 14),
    ).toJson()));

Future<void> main() async {
  final String mode = Platform.environment['PROBE_DB'] ?? 'memory';
  const DVDatabase().configure(
    mode == 'broken' ? Broken() : MemoryDVDatabaseAdapter(),
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    out['stored'] = await post(port, report('a', 'install-1', 'paid with $secret'));
    if (mode == 'memory') {
      out['duplicate'] = await post(port, report('a', 'install-1', 'paid with $secret'));
      out['second'] = await post(port, report('b', 'install-1', 'again'));
      out['limited'] = await post(port, report('c', 'install-1', 'again'));
      out['otherInstall'] = await post(port, report('d', 'install-2', 'other'));
      // A new install id, from the same address, past the source budget.
      out['sourceLimited'] =
          await post(port, report('f', 'install-4', 'rotated $secret'));
      // 127.0.0.1 is a trusted proxy here, reporting another client: that
      // client is another source, with its own budget. Were the endpoint to
      // count every report in one bucket, this would be refused too.
      out['otherSource'] = await post(port, report('g', 'install-5', 'elsewhere'),
          <String, String>{'x-forwarded-for': '203.0.113.50'});
      out['malformed'] = await post(port, utf8.encode('{"message": "$secret"'));
      // The server answers 413 and closes without reading the rest of the
      // body, so the client can still be writing when the connection goes:
      // 20 of 300 posts here lost the answer to a broken pipe. That is the
      // refusal arriving early, not a different answer, so the post is
      // repeated until one reads the status the server sent.
      for (int attempt = 1;; attempt++) {
        try {
          out['tooLarge'] =
              await post(port, report('e', 'install-3', 'x' * 8000));
          break;
        } on HttpException {
          if (attempt == 10) rethrow;
        } on SocketException {
          if (attempt == 10) rethrow;
        }
      }
      out['rows'] =
          (await const DVDatabase().query('SELECT * FROM dv_crash_reports'))
              .length;
    }
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
  return p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

Future<Directory> backendProject(String packages, String crashes) async {
  final Directory project =
      Directory.systemTemp.createTempSync('dv_crash_ingest_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: ingest_probe
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
$crashes
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
  late Directory declared;
  late Directory undeclared;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    declared = await backendProject(packages, '''
  crashes:
    sink: dartvel
    ingest:
      perInstallPerHour: 2
      perSourcePerHour: 3
      maxBytes: 4096
  server:
    trustedProxies: ["127.0.0.1/32"]
''');
    undeclared = await backendProject(packages, '  backendPort: 8089');
  });

  tearDownAll(() {
    for (final Directory d in <Directory>[declared, undeclared]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Map<String, String> inherited() => <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
      };

  Future<(Map<String, Object?>, String)> probe(
    Directory project, [
    Map<String, String> environment = const <String, String>{},
  ]) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{...inherited(), ...environment},
    ).timeout(const Duration(minutes: 3));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    return (
      jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>,
      output,
    );
  }

  int status(Map<String, Object?> r, String key) =>
      (r[key]! as Map<String, Object?>)['status']! as int;

  test('reports are validated, stored once, and limited per install and per '
      'source', () async {
    final (Map<String, Object?> r, String output) = await probe(declared);

    expect(status(r, 'stored'), 201);
    expect(status(r, 'duplicate'), 200);
    expect(status(r, 'second'), 201);
    expect(status(r, 'limited'), 202);
    expect(status(r, 'otherInstall'), 201);
    // Three stored from 127.0.0.1 is the source's budget: a fourth install id
    // does not buy a fourth row.
    expect(status(r, 'sourceLimited'), 429);
    expect(status(r, 'otherSource'), 201);
    expect(status(r, 'malformed'), 400);
    expect(status(r, 'tooLarge'), 413);
    expect(r['rows'], 4);
    // The report said it; nothing the server printed or answered may.
    expect(output, isNot(contains(secret)));
    expect(jsonEncode(r), isNot(contains(secret)));
  });

  test('a store that fails answers 503 and logs nothing of the report or '
      'the error', () async {
    final (Map<String, Object?> r, String output) =
        await probe(declared, const <String, String>{'PROBE_DB': 'broken'});

    expect(status(r, 'stored'), 503);
    expect(output, isNot(contains(secret)));
    expect(jsonEncode(r), isNot(contains(secret)));
  });

  test('an application that declares no Dartvel sink serves no endpoint',
      () async {
    final (Map<String, Object?> r, String _) = await probe(
      undeclared,
      const <String, String>{'PROBE_DB': 'single'},
    );

    expect(status(r, 'stored'), 404);
  });
}
