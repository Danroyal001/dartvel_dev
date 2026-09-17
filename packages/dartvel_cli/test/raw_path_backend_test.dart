// @DVBackendFunction(rawPath:) and (rawPathSuffix:), served and called.
//
// Raw HTTP exposure belongs on the backend function annotation, and the
// annotation had neither parameter, so the code `dartvel plugin add auth`
// wrote did not compile. This generates a backend with a raw path, a suffix
// and a plain function, serves it in a child process, asks each address over
// HTTP, and calls each function with the generated client under
// `flutter test`.
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _webhook = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rawPath: '/payments/webhook')
Future<String> _paymentWebhook(DVContext context) async => 'accepted';
''';

const String _catalog = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rawPathSuffix: '/public')
Future<String> _catalogItem(String id) async => 'item \$id';
''';

const String _hello = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _hello() async => 'hello';
''';

const String _notify = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rawPath: '/payments/notify')
Future<String> _paymentNotify(DVContext context) async => 'noted';
''';

const String _catalogHook = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rawPathSuffix: '/hook')
Future<String> _catalogHook() async => 'hooked';
''';

const String _greet = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _greet() async => 'greeted';
''';

/// The session cookie a browser attaches to a cross-site POST on its own,
/// naming a session the server never issued. A route that reads the cookie
/// refuses it; a route that does not never sees it.
const String _strayCookie =
    'dv_session=dvs_forged; __Host-dv_session=dvs_forged';

const String _serve = r'''
import 'dart:io';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  stdout.writeln('PORT ${handle.port}');
  await ProcessSignal.sigterm.watch().first;
  await handle.stop();
  exit(0);
}
''';

const String _read = r'''
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:raw_path_probe/dartvel_client/dartvel_client.dart';

void main() {
  test('read', () async {
    print('PROBE ${jsonEncode(<String, Object?>{
      'webhook': await paymentWebhook(),
      'item': await catalogItem(id: '7'),
      'hello': await hello(),
    })}');
  });
}
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

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

void main() {
  late Directory project;
  late Map<String, Object?> received;
  final Map<String, (int, String)> answers = <String, (int, String)>{};

  setUpAll(() async {
    final String root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_raw_path_');
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(
      p.join(
        project.path,
        'lib',
        'backend',
        'functions',
        'payments',
        'webhook.get.dart',
      ),
      _webhook,
    );
    write(
      p.join(project.path, 'lib', 'backend', 'functions', 'catalog.get.dart'),
      _catalog,
    );
    write(
      p.join(project.path, 'lib', 'backend', 'functions', 'hello.get.dart'),
      _hello,
    );
    write(
      p.join(
        project.path,
        'lib',
        'backend',
        'functions',
        'payments',
        'notify.post.dart',
      ),
      _notify,
    );
    write(
      p.join(
        project.path,
        'lib',
        'backend',
        'functions',
        'catalog_hook.post.dart',
      ),
      _catalogHook,
    );
    write(
      p.join(project.path, 'lib', 'backend', 'functions', 'greet.post.dart'),
      _greet,
    );
    write(p.join(project.path, 'bin', 'serve.dart'), _serve);
    write(p.join(project.path, 'test', 'read_test.dart'), _read);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: raw_path_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
dev_dependencies:
  flutter_test:
    sdk: flutter
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
    await routes.generate(root_: project.path);
    final ProcessResult resolved = await Process.run('flutter', <String>[
      'pub',
      'get',
    ], workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }

    final Process server = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', 'bin/serve.dart'],
      workingDirectory: project.path,
    );
    final StringBuffer serverOutput = StringBuffer();
    server.stderr.transform(utf8.decoder).listen(serverOutput.write);
    try {
      // Read to the end rather than to the port line: the server logs every
      // request to stdout, and a pipe nobody reads fails its next write.
      final Completer<String> started = Completer<String>();
      server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String l) {
            if (l.startsWith('PORT ') && !started.isCompleted)
              started.complete(l);
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
      final int port = int.parse(portLine.substring('PORT '.length));
      final String csrf = 'a' * 32;
      const Map<String, String> none = <String, String>{};
      for (final (
            String name,
            String method,
            String path,
            Map<String, String> headers,
          )
          in <(String, String, String, Map<String, String>)>[
            ('/payments/webhook', 'GET', '/payments/webhook', none),
            ('/api/payments/webhook', 'GET', '/api/payments/webhook', none),
            (
              '/api/catalog/public?id=7',
              'GET',
              '/api/catalog/public?id=7',
              none,
            ),
            ('/api/catalog?id=7', 'GET', '/api/catalog?id=7', none),
            ('/api/hello', 'GET', '/api/hello', none),
            // A webhook sender has no CSRF token and no session.
            ('raw POST', 'POST', '/payments/notify', none),
            ('suffix POST', 'POST', '/api/catalog_hook/hook', none),
            (
              'raw POST with a cookie',
              'POST',
              '/payments/notify',
              <String, String>{'cookie': _strayCookie},
            ),
            (
              'function POST with a cookie',
              'POST',
              '/api/greet',
              <String, String>{
                'cookie': _strayCookie,
                'x-dartvel-csrf-token': csrf,
              },
            ),
            (
              'raw POST with a bearer',
              'POST',
              '/payments/notify',
              <String, String>{'authorization': 'Bearer dvs_forged'},
            ),
            ('function POST without a token', 'POST', '/api/greet', none),
            (
              'function POST with a token',
              'POST',
              '/api/greet',
              <String, String>{'x-dartvel-csrf-token': csrf},
            ),
          ]) {
        final HttpClient http = HttpClient();
        try {
          final HttpClientRequest request = await http.openUrl(
            method,
            Uri.parse('http://127.0.0.1:$port$path'),
          );
          headers.forEach(request.headers.set);
          final HttpClientResponse response = await request.close();
          answers[name] = (
            response.statusCode,
            await response.transform(utf8.decoder).join(),
          );
        } finally {
          http.close(force: true);
        }
      }
      final ProcessResult result = await Process.run('flutter', <String>[
        'test',
        'test/read_test.dart',
        '--dart-define=DARTVEL_BACKEND_URL=http://127.0.0.1:$port',
      ], workingDirectory: project.path).timeout(const Duration(minutes: 8));
      final String? line = const LineSplitter()
          .convert('${result.stdout}')
          .map((String l) => l.trim())
          .where((String l) => l.startsWith('PROBE '))
          .firstOrNull;
      if (result.exitCode != 0 || line == null) {
        fail(
          'the client did not call the functions (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}\nserver:\n$serverOutput',
        );
      }
      received =
          jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    } finally {
      server.kill(ProcessSignal.sigterm);
      await server.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          server.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('rawPath serves the function at exactly that path, and only there', () {
    expect(answers['/payments/webhook'], (200, 'accepted'));
    expect(answers['/api/payments/webhook']!.$1, 404);
  });

  test('rawPathSuffix adds to the generated path instead of replacing it', () {
    expect(answers['/api/catalog/public?id=7'], (200, 'item 7'));
    expect(answers['/api/catalog?id=7']!.$1, 404);
  });

  test('a function with neither keeps its generated path', () {
    expect(answers['/api/hello'], (200, 'hello'));
  });

  test('a POST to a raw path needs no CSRF token', () {
    expect(answers['raw POST'], (200, 'noted'));
    expect(answers['suffix POST'], (200, 'hooked'));
  });

  test('a raw path does not read the session cookie', () {
    // So a forged cross-site POST has no session to borrow, which is what
    // CSRF protection is for.
    expect(answers['raw POST with a cookie'], (200, 'noted'));
    // The control: the same cookie is read, and refused, on a function.
    expect(answers['function POST with a cookie']!.$1, 401);
  });

  test('a raw path still judges a bearer credential', () {
    expect(answers['raw POST with a bearer']!.$1, 401);
  });

  test('a function POST without a CSRF token is still refused', () {
    expect(answers['function POST without a token']!.$1, 403);
    expect(answers['function POST with a token'], (200, 'greeted'));
  });

  test('the generated client calls each function where it is served', () {
    expect(received, <String, Object?>{
      'webhook': 'accepted',
      'item': 'item 7',
      'hello': 'hello',
    });
  });
}
