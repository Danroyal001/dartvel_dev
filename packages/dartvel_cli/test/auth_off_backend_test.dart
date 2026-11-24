// An application with no accounts serves no auth API.
//
// `dartvel.auth.pages: false` took the account pages away and left every
// endpoint behind them: on an application with a database the generated
// server installs a database-backed provider for Studio, so a public
// `POST /api/auth/sign-up` opened an account on an application that has no
// accounts at all, and signed it in. `dartvel.auth: false` is the switch for
// that application: no page, and every `/api/auth/*` route answers 404.
// `dartvel.auth.signUp: false` closes sign-up alone, for an application whose
// accounts are made some other way. `pages: false` is unchanged, because an
// application with its own sign-up page calls the API those pages called.
//
// Driven over HTTP against the generated backend in a child process, the way
// the binary starts it, over a real SQLite file: the provider is installed in
// every case, so a 404 here is the route being absent, not a 503 for a
// missing provider.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String csrfToken = 'probe0csrf0token0that0is0long0enough';

Future<int> call(int port, String method, String path, {Object? body}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-dartvel-session-delivery', 'token');
    if (method != 'GET') {
      request.headers.set('x-dartvel-csrf-token', csrfToken);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body ?? <String, Object?>{}));
    }
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    http.close(force: true);
  }
}

Future<void> main() async {
  final List<Object?> paths =
      jsonDecode(Platform.environment['PROBE_PATHS']!) as List<Object?>;
  final String file = Platform.environment['PROBE_DATABASE']!;
  final dynamic handle = await gen.startBackend(
    host: '127.0.0.1',
    port: 0,
    defaultDatabase:
        DVDatabaseConnection(engine: DVDatabaseEngine.sqlite, database: file),
  );
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  final Map<String, Object?> credentials = <String, Object?>{
    'email': 'stranger@example.com',
    'password': 'correct horse battery staple',
  };
  try {
    for (final Object? path in paths) {
      out['GET $path'] = await call(port, 'GET', '/api$path');
      out['POST $path'] = await call(port, 'POST', '/api$path',
          body: path == '/auth/sign-up' || path == '/auth/sign-in'
              ? credentials
              : null);
    }
    out['installed'] = DVAuthEndpoints.installed;
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
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
}

/// A generated project whose pubspec's `dartvel.auth` is [auth].
Future<Directory> generateProject(String name, String auth) async {
  final String packages = await packagesDirectory();
  final Directory project = Directory.systemTemp.createTempSync('dv_$name');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: ${name}_probe
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
$auth
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
Future<String> _ping(DVContext context) async => 'pong';
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
    <String>['pub', 'get', '--offline'],
    workingDirectory: project.path,
  );
  if (resolved.exitCode != 0) {
    throw StateError('dart pub get failed:\n${resolved.stderr}');
  }
  return project;
}

Future<Map<String, Object?>> probe(Directory project) async {
  final String database = p.join(project.path, 'dartvel_data', 'data.db');
  Directory(p.dirname(database)).createSync(recursive: true);
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'bin/probe.dart'],
    workingDirectory: project.path,
    environment: <String, String>{
      'PROBE_PATHS': jsonEncode(BackendGenerator.dvReservedAuthPaths),
      'PROBE_DATABASE': database,
    },
  ).timeout(const Duration(minutes: 4));
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
  final Map<String, Directory> projects = <String, Directory>{};

  setUpAll(() async {
    projects['off'] = await generateProject('auth_off', '  auth: false');
    projects['closed'] =
        await generateProject('auth_closed', '  auth:\n    signUp: false');
    projects['own'] =
        await generateProject('auth_own', '  auth:\n    pages: false');
  });

  tearDownAll(() {
    for (final Directory project in projects.values) {
      if (project.existsSync()) project.deleteSync(recursive: true);
    }
  });

  test('auth: false answers 404 to every auth route, by either method',
      () async {
    final Map<String, Object?> r = await probe(projects['off']!);
    // The provider Studio signs in through is still there: the routes are
    // gone, not merely unconfigured.
    expect(r['installed'], isTrue);
    for (final String path in BackendGenerator.dvReservedAuthPaths) {
      for (final String method in <String>['GET', 'POST']) {
        expect(r['$method $path'], anyOf(404, 405), reason: '$method $path');
      }
    }
  });

  test('auth.signUp: false closes sign-up and keeps sign-in', () async {
    final Map<String, Object?> r = await probe(projects['closed']!);
    expect(r['POST /auth/sign-up'], anyOf(404, 405));
    // Reached, and refused for credentials nobody has (400,
    // invalid_credentials): not a missing route.
    expect(r['POST /auth/sign-in'], anyOf(400, 401));
    expect(r['GET /auth/session'], 401);
  });

  test('pages: false keeps the API an application\'s own pages call',
      () async {
    final Map<String, Object?> r = await probe(projects['own']!);
    expect(r['POST /auth/sign-up'], 200);
    expect(r['GET /auth/session'], 401);
  });
}
