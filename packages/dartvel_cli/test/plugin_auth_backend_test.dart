// The endpoints `dartvel plugin add auth` writes, served and called.
//
// The plugin's `/auth/me` decoded a base64 token and answered with whatever
// email was inside it, and `/auth/login` issued one for any address with any
// password, so anyone could be anyone. This adds the plugin to a project,
// serves its backend in a child process with the framework's own accounts
// installed, and proves a token only comes from a real sign-in and a forged
// one is refused.
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/plugin_command.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _serve = r'''
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(provider: LocalAuthProvider()),
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  stdout.writeln('PORT ${handle.port}');
  await ProcessSignal.sigterm.watch().first;
  await handle.stop();
  exit(0);
}
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

const String _email = 'owner@example.com';
const String _password = 'correct horse battery';

Future<String> repoRoot() async {
  final Uri? lib = await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/dartvel_cli.dart'),
  );
  return p.normalize(p.join(p.dirname(lib!.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

typedef Answer = ({int status, String body, String? cookie});

void main() {
  late Directory project;
  late Process server;
  late int port;
  final StringBuffer serverOutput = StringBuffer();

  Future<Answer> call(
    String method,
    String path, {
    Map<String, String> headers = const <String, String>{},
    Object? json,
  }) async {
    final HttpClient http = HttpClient();
    try {
      final HttpClientRequest request = await http.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      headers.forEach(request.headers.set);
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final HttpClientResponse response = await request.close();
      return (
        status: response.statusCode,
        body: await response.transform(utf8.decoder).join(),
        cookie: response.headers.value('set-cookie'),
      );
    } finally {
      http.close(force: true);
    }
  }

  const Map<String, String> tokenClient = <String, String>{
    'x-dartvel-session-delivery': 'token',
  };

  Future<String> login() async {
    final Answer answer = await call(
      'POST',
      '/auth/login',
      headers: tokenClient,
      json: <String, Object?>{'email': _email, 'password': _password},
    );
    expect(answer.status, 200, reason: '${answer.body}\n$serverOutput');
    return (jsonDecode(answer.body) as Map<String, Object?>)['token']!
        as String;
  }

  setUpAll(() async {
    final String root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_plugin_auth_');
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(p.join(project.path, 'bin', 'serve.dart'), _serve);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: plugin_auth_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
''');
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');
    await (CommandRunner<void>('dartvel', 'probe')
          ..addCommand(PluginCommand(root: project.path)))
        .run(<String>['plugin', 'add', 'auth']);
    await routes.generate(root_: project.path);
    final ProcessResult resolved = await Process.run('flutter', <String>[
      'pub',
      'get',
    ], workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    server = await Process.start(Platform.resolvedExecutable, <String>[
      'run',
      'bin/serve.dart',
    ], workingDirectory: project.path);
    server.stderr.transform(utf8.decoder).listen(serverOutput.write);
    final Completer<String> started = Completer<String>();
    server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String l) {
          if (l.startsWith('PORT ') && !started.isCompleted) {
            started.complete(l);
          }
        });
    unawaited(
      server.exitCode.then((int code) {
        if (!started.isCompleted) {
          started.completeError(
            StateError('the backend exited ($code):\n$serverOutput'),
          );
        }
      }),
    );
    final String portLine = await started.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        throw StateError('the backend did not start:\n$serverOutput');
      },
    );
    port = int.parse(portLine.substring('PORT '.length));

    // An account, made where a page makes one.
    final Answer signUp = await call(
      'POST',
      '/api/auth/sign-up',
      headers: <String, String>{
        ...tokenClient,
        'x-dartvel-csrf-token': 'a' * 32,
      },
      json: <String, Object?>{'email': _email, 'password': _password},
    );
    if (signUp.status != 200) {
      throw StateError(
        'sign-up failed (${signUp.status}): ${signUp.body}\n'
        '$serverOutput',
      );
    }
  });

  tearDownAll(() async {
    server.kill(ProcessSignal.sigterm);
    await server.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        server.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('login issues a session token for the right password', () async {
    expect(await login(), startsWith('dvs_'));
  });

  test(
    'login refuses a wrong password, and an account that does not exist',
    () async {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        <String, Object?>{'email': _email, 'password': 'wrong password!'},
        <String, Object?>{'email': 'nobody@example.com', 'password': _password},
      ]) {
        final Answer answer = await call(
          'POST',
          '/auth/login',
          headers: tokenClient,
          json: body,
        );
        expect(answer.status, isNot(200), reason: '$body');
        expect(answer.body, isNot(contains('dvs_')), reason: '$body');
      }
    },
  );

  test(
    'login from a page sets no cookie, because it checks no CSRF token',
    () async {
      final Answer answer = await call(
        'POST',
        '/auth/login',
        headers: <String, String>{'origin': 'https://attacker.example'},
        json: <String, Object?>{'email': _email, 'password': _password},
      );
      expect(answer.status, isNot(200));
      expect(answer.cookie, isNull);
      expect(answer.body, isNot(contains('dvs_')));
    },
  );

  test('me answers for the session the token names', () async {
    final String token = await login();
    final Answer answer = await call(
      'GET',
      '/auth/me',
      headers: <String, String>{'authorization': 'Bearer $token'},
    );
    expect(answer.status, 200, reason: answer.body);
    expect(answer.body, contains(_email));
  });

  test('me refuses a forged token', () async {
    // What the old plugin accepted: an unsigned claim anyone can write.
    final String forged = base64Url
        .encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'userId': 'u1',
              'email': 'victim@example.com',
              'issuedAt': DateTime.now().toIso8601String(),
            }),
          ),
        )
        .replaceAll('=', '');
    for (final (String path, Map<String, String> headers)
        in <(String, Map<String, String>)>[
          ('/auth/me?token=$forged', const <String, String>{}),
          ('/auth/me', <String, String>{'authorization': 'Bearer $forged'}),
          ('/auth/me', <String, String>{'authorization': 'Bearer dvs_$forged'}),
          ('/auth/me', const <String, String>{}),
        ]) {
      final Answer answer = await call('GET', path, headers: headers);
      expect(answer.status, 401, reason: '$path $headers: ${answer.body}');
      expect(answer.body, isNot(contains('victim@example.com')));
    }
  });

  test('logout revokes the session, and its token stops working', () async {
    final String token = await login();
    final Map<String, String> bearer = <String, String>{
      'authorization': 'Bearer $token',
    };
    final Answer out = await call('POST', '/auth/logout', headers: bearer);
    expect(out.status, lessThan(300), reason: out.body);
    expect((await call('GET', '/auth/me', headers: bearer)).status, 401);
  });
}
