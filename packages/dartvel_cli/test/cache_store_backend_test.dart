// dartvel.cache reaching the generated server.
//
// The store is configuration: an application names it in pubspec.yaml and
// never constructs an adapter or a Redis client. So this generates a real
// backend the way `dartvel routes` does, starts it as a process, and asserts
// on what the process did -- whether it started, and where a backend
// function's DV.Cache.set landed -- never on the generated text.
//
// The silent failure this guards is a server that believes it has a shared
// cache while each instance keeps its own: a url variable that is unset must
// stop the start, not fall back to memory.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  Object? error;
  Object? answered;
  Object? stored;
  final Completer<void> stop = Completer<void>();
  final Future<void> running;
  if (Platform.environment['PROBE_MODE'] == 'main') {
    running = gen
        .dartvelMain(arguments, until: stop.future)
        .catchError((Object e) => error = e);
  } else {
    running = Future<dynamic>.sync(
      () => gen.startBackend(host: '127.0.0.1', port: 0),
    ).then<void>((dynamic handle) async {
      final HttpClient client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(
            'http://127.0.0.1:${handle.port}/api/remember'));
        final response = await request.close();
        answered = await response.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }
      final DVRedisClient raw = await DVRedisClient.connect();
      stored = await raw.command(<String>['GET', 'cache_probe:visits']);
      await raw.command(<String>['DEL', 'cache_probe:visits']);
      await raw.close();
      await stop.future;
      await handle.stop();
    }).catchError((Object e) => error = e);
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  if (!stop.isCompleted) stop.complete();
  await running.timeout(const Duration(seconds: 20));
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'error': error?.toString(),
    'answered': answered,
    'stored': stored,
  })}');
  exit(0);
}
''';

Future<bool> _redisReachable() async {
  try {
    final Socket socket = await Socket.connect('127.0.0.1', 6379,
        timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  late Directory project;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );

    project = Directory.systemTemp.createTempSync('dv_cache_store_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: cache_probe
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
  cache:
    store: redis
    url: \${REDIS_URL}
    prefix: "cache_probe:"
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    // The backend function names no store: it writes through DV.Cache.
    write('lib/backend/functions/remember.get.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

@DVBackendFunction()
Future<String> _remember() async {
  await DV.Cache.set('visits', 1, ttl: const Duration(minutes: 1));
  return 'ok';
}
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
        'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}',
      );
    }
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
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> probe(Map<String, String> environment) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
        ...environment,
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

  test('an unset url variable stops the server before it serves', () async {
    final Map<String, Object?> r = await probe(const <String, String>{});
    expect(r['error'], allOf(contains('DV-CACHE-004'), contains('REDIS_URL')));
    expect(r['answered'], isNull);
  });

  test('a worker refuses the same way, before it works anything', () async {
    final Map<String, Object?> r = await probe(const <String, String>{
      'PROBE_MODE': 'main',
      'DARTVEL_ROLE': 'worker',
    });
    expect(r['error'], contains('DV-CACHE-004'));
  });

  test('a backend function\'s DV.Cache.set lands in the Redis REDIS_URL names',
      () async {
    if (!await _redisReachable()) {
      markTestSkipped('Start a local redis-server to run this.');
      return;
    }
    final Map<String, Object?> r = await probe(const <String, String>{
      'REDIS_URL': 'redis://127.0.0.1:6379/0',
    });
    expect(r['error'], isNull);
    expect(r['answered'], contains('ok'));
    expect(r['stored'], '{"v":1}');
  });
}
