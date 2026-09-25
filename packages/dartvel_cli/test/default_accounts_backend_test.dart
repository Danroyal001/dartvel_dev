// A generated server with a database can sign people up and in, and the
// accounts survive a restart.
//
// The server authenticated sessions and served sign-up and sign-in, and
// installed no provider behind them: every call answered 503 until the
// application ran DVAuthEndpoints.install before startBackend. A web-server
// binary runs no application code before startBackend, so on the one binary
// Deployment describes nobody could sign up or sign in -- and so nobody could
// ever open the Studio mount that `dartvel admin grant` opens. The test that
// covered granting forged its session by writing it into the database.
//
// Driven over HTTP against the generated backend in a child process, twice
// over one SQLite file, the way the binary starts it. The silent failures:
//  * accounts kept in memory, which work until the first restart;
//  * the framework's provider replacing one the application installed;
//  * a provider over nothing, where there is no database to keep accounts in.
@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String csrfToken = 'probe0csrf0token0that0is0long0enough';
const String password = 'correct horse battery staple';

Future<Map<String, Object?>> call(int port, String method, String path,
    {String? bearer, Object? body}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-dartvel-session-delivery', 'token');
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (method != 'GET') {
      request.headers.set('x-dartvel-csrf-token', csrfToken);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body ?? <String, Object?>{}));
    }
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    return <String, Object?>{'status': response.statusCode, 'body': text, 'json': json};
  } finally {
    http.close(force: true);
  }
}

String? tokenOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  return json is Map ? json['token'] as String? : null;
}

String? userIdOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  final Object? user = json is Map ? json['user'] : null;
  return user is Map ? user['id'] as String? : null;
}

Future<void> main() async {
  final String mode = Platform.environment['PROBE_MODE']!;
  final String? file = Platform.environment['PROBE_DATABASE'];
  final Map<String, Object?> out = <String, Object?>{};
  LocalAuthProvider? own;
  if (mode == 'own') {
    own = LocalAuthProvider();
    await own.signUp('own@example.com', password);
    DVAuthEndpoints.install(credentials: DVCredentialGuard(provider: own));
  }
  final dynamic handle = await gen.startBackend(
    host: '127.0.0.1',
    port: 0,
    defaultDatabase: file == null
        ? null
        : DVDatabaseConnection(engine: DVDatabaseEngine.sqlite, database: file),
  );
  final int port = handle.port as int;
  Map<String, Object?> credentials(String email, [String secret = password]) =>
      <String, Object?>{'email': email, 'password': secret};
  try {
    switch (mode) {
      case 'first':
        final Map<String, Object?> up = await call(port, 'POST', '/api/auth/sign-up',
            body: credentials('owner@example.com'));
        out['signUp'] = up;
        out['userId'] = userIdOf(up);
        out['again'] = await call(port, 'POST', '/api/auth/sign-up',
            body: credentials('OWNER@example.com', 'another passphrase'));
        out['whoami'] = await call(port, 'GET', '/api/whoami', bearer: tokenOf(up));
      case 'second':
        final Map<String, Object?> signIn = await call(port, 'POST', '/api/auth/sign-in',
            body: credentials('owner@example.com'));
        out['signIn'] = signIn;
        out['userId'] = userIdOf(signIn);
        out['wrong'] = await call(port, 'POST', '/api/auth/sign-in',
            body: credentials('owner@example.com', 'not the passphrase'));
        out['whoami'] = await call(port, 'GET', '/api/whoami', bearer: tokenOf(signIn));
      case 'own':
        out['signIn'] = await call(port, 'POST', '/api/auth/sign-in',
            body: credentials('own@example.com'));
        out['signUp'] = await call(port, 'POST', '/api/auth/sign-up',
            body: credentials('new@example.com'));
        out['ownAccounts'] = own!.accounts;
      case 'none':
        out['signUp'] = await call(port, 'POST', '/api/auth/sign-up',
            body: credentials('owner@example.com'));
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
  return p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
}

void main() {
  late Directory project;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_default_accounts_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: default_accounts_probe
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
    write('lib/backend/functions/whoami.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

String describeCaller(DVContext context) =>
    context.session?.userId ?? 'anonymous';

@DVBackendFunction()
Future<String> _whoami(DVContext context) async => describeCaller(context);
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
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> probe(String mode, {String? database}) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      environment: <String, String>{
        'PROBE_MODE': mode,
        'PROBE_DATABASE': ?database,
      },
    ).timeout(const Duration(minutes: 4));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  int status(Map<String, Object?> r, String key) =>
      (r[key]! as Map<String, Object?>)['status']! as int;

  test('an account made on one run signs in on the next', () async {
    final String database = p.join(project.path, 'dartvel_data', 'data.db');
    Directory(p.dirname(database)).createSync(recursive: true);

    final Map<String, Object?> first = await probe('first', database: database);
    expect(status(first, 'signUp'), 200, reason: '${first['signUp']}');
    expect(first['userId'], isA<String>());
    // The session it was given authenticates.
    expect((first['whoami']! as Map<String, Object?>)['body'],
        contains('${first['userId']}'));
    // The same address, written differently, is the same account.
    expect(status(first, 'again'), isNot(200), reason: '${first['again']}');

    final Map<String, Object?> second = await probe('second', database: database);
    expect(status(second, 'signIn'), 200, reason: '${second['signIn']}');
    expect(second['userId'], first['userId']);
    // The endpoint's refusal for a wrong password, which says nothing more.
    expect((second['wrong']! as Map<String, Object?>)['body'],
        contains('"error":"invalid_credentials"'));
    expect((second['whoami']! as Map<String, Object?>)['body'],
        contains('${first['userId']}'));
  });

  test('a provider the application installed is the one used', () async {
    final String database = p.join(project.path, 'own', 'data.db');
    Directory(p.dirname(database)).createSync(recursive: true);

    final Map<String, Object?> r = await probe('own', database: database);

    expect(status(r, 'signIn'), 200, reason: '${r['signIn']}');
    expect(status(r, 'signUp'), 200, reason: '${r['signUp']}');
    expect(r['ownAccounts'], containsAll(<String>['own@example.com', 'new@example.com']));
  });

  test('with no database there is nowhere to keep an account', () async {
    final Map<String, Object?> r = await probe('none');

    expect(status(r, 'signUp'), 503, reason: '${r['signUp']}');
    expect((r['signUp']! as Map<String, Object?>)['body'],
        contains('DVAuthEndpoints.install'));
  });
}
