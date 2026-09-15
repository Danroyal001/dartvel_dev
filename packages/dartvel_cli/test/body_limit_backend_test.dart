// The generated backend's body limits, served and sent to.
//
// The native server reads a request body before any Dart runs. Every limit
// the generated backend declared -- bodyLimit, uploadLimit, the crash
// endpoint's maxBytes -- was checked in Dart after that read, and the read
// itself had no limit. This generates a real backend with
// `dartvel.server.maxBodyBytes`, starts it, and sends bodies to its routes,
// asserting on what the server answered -- never on the generated text. The
// silent failures:
//
//  * the pubspec's limit emitted and never applied, so a route that declared
//    nothing reads any size;
//  * an upload route capped at the server limit, because the native side was
//    never told the route's own;
//  * a route limit Dart checks only after the native side has buffered the
//    whole body;
//  * the crash endpoint refused below the maxBytes it was configured with.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart' show dvTooLargeMessage;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String secret = 'BODY-SECRET-5e1f';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String secret = 'BODY-SECRET-5e1f';
const String csrf = 'probe0csrf0token0that0is0long0enough';

/// Sends only a head declaring [length] bytes and reads what comes back. An
/// answer can only come from the header: none of the body is ever sent.
Future<Map<String, Object?>> declared(int port, String path, int length) async {
  final Socket socket = await Socket.connect('127.0.0.1', port);
  final List<int> received = <int>[];
  final Completer<void> closed = Completer<void>();
  socket.listen(received.addAll,
      onDone: () { if (!closed.isCompleted) closed.complete(); },
      onError: (Object _) { if (!closed.isCompleted) closed.complete(); });
  socket.add(ascii.encode('POST $path HTTP/1.1\r\nHost: localhost\r\n'
      'Content-Type: application/json\r\nX-Dartvel-Csrf-Token: $csrf\r\n'
      'X-Secret: $secret\r\nContent-Length: $length\r\n\r\n'));
  final Stopwatch clock = Stopwatch()..start();
  await closed.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  socket.destroy();
  final String text = latin1.decode(received);
  final RegExpMatch? match = RegExp(r'^HTTP/1\.1 (\d{3})').firstMatch(text);
  return <String, Object?>{
    'status': match == null ? null : int.parse(match.group(1)!),
    'ms': clock.elapsedMilliseconds,
    'text': text,
  };
}

Future<Map<String, Object?>> post(int port, String path, List<int> body) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.contentType = ContentType.json;
    request.headers.set('x-dartvel-csrf-token', csrf);
    request.contentLength = body.length;
    request.add(body);
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'type': response.headers.contentType?.mimeType,
      'text': await response.transform(utf8.decoder).join(),
    };
  } finally {
    client.close(force: true);
  }
}

/// A JSON body of about [size] bytes.
List<int> named(int size) =>
    utf8.encode(jsonEncode(<String, String>{'name': 'x' * size}));

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  // Before the backend starts, which is when a route's limit is read.
  DVBodyLimits.body = 8192;
  DVBodyLimits.upload = 200 * 1024;
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    out['note'] = await declared(port, '/api/note', 100 * 1024);
    out['noteSmall'] = await post(port, '/api/note', named(1024));
    out['upload'] = await post(port, '/api/upload', named(150 * 1024));
    out['uploadOver'] = await declared(port, '/api/upload', 300 * 1024);
    out['small'] = await declared(port, '/api/small', 16 * 1024);
    out['crash'] = await post(
        port,
        '/api/_dartvel/crashes',
        utf8.encode(jsonEncode(DVCrashReport(
          id: 'a',
          kind: DVCrashKind.fatal,
          errorType: 'StateError',
          message: 'x' * (100 * 1024),
          frames: const <DVCrashFrame>[DVCrashFrame(function: 'main')],
          fingerprint: 'f',
          context: const DVCrashContext(release: '1.0.0', installId: 'install-1'),
          occurredAt: DateTime.utc(2026, 9, 15),
        ).toJson())));
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

Future<Directory> backendProject(String packages) async {
  final Directory project = Directory.systemTemp.createTempSync('dv_body_limit_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: body_limit_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
  server:
    maxBodyBytes: 65536
  crashes:
    sink: dartvel
    ingest:
      maxBytes: 131072
''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  write('lib/backend/functions/note.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<int> _note(String name) async => name.length;
''');
  write('lib/backend/functions/upload.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@DVUseMiddleware([DVMiddlewares.uploadLimit])
Future<int> _upload(String name) async => name.length;
''');
  write('lib/backend/functions/small.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@DVUseMiddleware([DVMiddlewares.bodyLimit])
Future<int> _small(String name) async => name.length;
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
  late Directory project;

  setUpAll(() async {
    project = await backendProject(await packagesDirectory());
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('every route is held to its own limit by the server, and the pubspec '
      'limit holds the rest', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null) key: Platform.environment[key]!,
      },
    ).timeout(const Duration(minutes: 3));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    final Map<String, Object?> r =
        jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;

    // A route that declared nothing: dartvel.server.maxBodyBytes, refused
    // from the header alone. Waiting for a body that never comes is no answer.
    expect(at('note')['status'], 413, reason: '${at('note')}');
    expect(at('note')['text'], contains(dvTooLargeMessage(65536)));
    expect(at('noteSmall')['status'], 200, reason: '${at('noteSmall')}');

    // uploadLimit reads past the server limit, up to its own.
    expect(at('upload')['status'], 200, reason: '${at('upload')}');
    expect(at('uploadOver')['status'], 413, reason: '${at('uploadOver')}');
    expect(at('uploadOver')['text'], contains(dvTooLargeMessage(200 * 1024)));

    // bodyLimit below the server limit is refused by its own number, before
    // the body is read.
    expect(at('small')['status'], 413, reason: '${at('small')}');
    expect(at('small')['text'], contains(dvTooLargeMessage(8192)));

    // The crash endpoint answers a report above the server limit and under
    // its own maxBytes itself, rather than the server refusing it first.
    expect(at('crash')['status'], isNot(413), reason: '${at('crash')}');
    expect(at('crash')['type'], 'application/json', reason: '${at('crash')}');

    expect(jsonEncode(r), isNot(contains(secret)));
  });
}
