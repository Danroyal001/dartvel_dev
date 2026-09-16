// The Shorebird patch source, served by the application's own backend.
//
// A project whose shorebird.yaml points base_url somewhere other than
// Shorebird's hosted service is saying its patches come from its own server,
// and the web-server binary is that server. This generates a real backend,
// starts it, and asks it what a device and `dartvel updates patch
// --patch-source` ask -- asserting on what the server answered:
//
//  * a patch larger than the server's body limit is published, under the
//    path base_url names, with the token the server was started with;
//  * the updater's check offers it with a download URL on the host the
//    device used, and the download is the bytes published;
//  * publishing without the token stores nothing;
//  * a project with no shorebird.yaml has no patch source at all, so the
//    same check is the application's 404.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<Map<String, Object?>> send(String method, int port, String path,
    {List<int> body = const <int>[], Map<String, String> headers = const {}}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    // The address the device used, which the download URL must be built on.
    request.headers.host = 'phone-sees-this.test';
    request.headers.port = 8443;
    headers.forEach(request.headers.set);
    request.contentLength = body.length;
    request.add(body);
    final HttpClientResponse response = await request.close();
    final List<int> bytes =
        await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    return <String, Object?>{
      'status': response.statusCode,
      'length': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'text': response.headers.contentType?.mimeType == 'application/json'
          ? utf8.decode(bytes)
          : '',
    };
  } on IOException catch (error) {
    // A server that refuses a body it will not read closes the connection
    // while it is still being sent.
    return <String, Object?>{'status': -1, 'text': '$error'};
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final String store = args.first;
  final dynamic handle = await gen.startBackend(
      host: '127.0.0.1', port: 0, updatesRoot: store);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  // Three megabytes: past the server's default one-megabyte body limit.
  final List<int> patch = List<int>.generate(3 * 1024 * 1024, (int i) => i % 251);
  final String hash = sha256.convert(<int>[9, 9, 9]).toString();
  final String query = '?app_id=probe-app&release_version=1.0.0%2B1'
      '&platform=android&arch=x86_64&hash=$hash';
  try {
    out['unauthorized'] = await send('POST', port,
        '/updates/_dartvel/publish$query', body: <int>[1, 2, 3]);
    out['published'] = await send('POST', port,
        '/updates/_dartvel/publish$query',
        body: patch,
        headers: <String, String>{
          'authorization': 'Bearer ${Platform.environment['DARTVEL_UPDATES_TOKEN']}',
        });
    out['check'] = await send('POST', port, '/updates/api/v1/patches/check',
        body: utf8.encode(jsonEncode(<String, Object?>{
          'app_id': 'probe-app',
          'channel': 'stable',
          'release_version': '1.0.0+1',
          'platform': 'android',
          'arch': 'x86_64',
        })),
        headers: <String, String>{'content-type': 'application/json'});
    out['download'] = await send('GET', port,
        '/updates/patches/probe-app/1.0.0+1/android/x86_64/1');
    out['patchSha256'] = sha256.convert(patch).toString();
  } finally {
    await handle.stop();
  }
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

Future<String> _packagesDirectory() async {
  final Uri cli = (await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
  ))!;
  return p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

Future<void> _generate(String packages, Directory project) async {
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
}

Future<Directory> _project(String packages) async {
  final Directory project =
      Directory.systemTemp.createTempSync('dv_patch_source_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: patch_source_probe
version: 1.0.0+1
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  crypto: ^3.0.7
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
  write('shorebird.yaml', '''
app_id: probe-app
base_url: https://updates.example.test/updates
auto_update: false
''');
  write('lib/backend/functions/note.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<int> _note(String name) async => name.length;
''');
  write('bin/probe.dart', _probe);
  await _generate(packages, project);
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

Future<Map<String, Object?>> _runProbe(Directory project, Directory store) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'bin/probe.dart', store.path],
    workingDirectory: project.path,
    includeParentEnvironment: false,
    environment: <String, String>{
      for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
        if (Platform.environment[key] != null) key: Platform.environment[key]!,
      'DARTVEL_UPDATES_TOKEN': 'probe-token-5b1c2e',
    },
  ).timeout(const Duration(minutes: 3));
  final String? line = const LineSplitter()
      .convert('${result.stdout}')
      .where((String l) => l.startsWith('PROBE '))
      .firstOrNull;
  if (result.exitCode != 0 || line == null) {
    fail('the probe did not run (exit ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}');
  }
  return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
}

void main() {
  late String packages;
  late Directory project;
  late Directory store;

  setUpAll(() async {
    packages = await _packagesDirectory();
    project = await _project(packages);
  });

  setUp(() {
    store = Directory.systemTemp.createTempSync('dv_patch_store_');
  });

  tearDown(() {
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('a project whose shorebird.yaml names its own server serves and '
      'publishes patches at the path base_url names', () async {
    final Map<String, Object?> r = await _runProbe(project, store);
    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;

    expect(at('unauthorized')['status'], 401, reason: '${at('unauthorized')}');
    expect(at('published')['status'], 201, reason: '${at('published')}');

    expect(at('check')['status'], 200, reason: '${at('check')}');
    final Map<String, Object?> answer =
        jsonDecode(at('check')['text']! as String) as Map<String, Object?>;
    expect(answer['patch_available'], isTrue);
    final Map<String, Object?> patch = answer['patch']! as Map<String, Object?>;
    expect(patch['number'], 1);
    expect(
      patch['download_url'],
      'http://phone-sees-this.test:8443/updates/patches/probe-app/1.0.0+1/'
      'android/x86_64/1',
    );

    expect(at('download')['status'], 200);
    expect(at('download')['sha256'], r['patchSha256']);
    // On disk where the server was told to keep patches.
    expect(
      File(p.join(store.path, 'probe-app', '1.0.0+1', 'android', 'x86_64', '1',
              'patch.bin'))
          .lengthSync(),
      3 * 1024 * 1024,
    );
  });

  test('a project with no shorebird.yaml serves no patch source', () async {
    File(p.join(project.path, 'shorebird.yaml')).deleteSync();
    await _generate(packages, project);
    final Map<String, Object?> r = await _runProbe(project, store);
    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    expect(at('published')['status'], isNot(201));
    expect(at('check')['status'], 404, reason: '${at('check')}');
    expect(store.listSync(), isEmpty);
  });
}
