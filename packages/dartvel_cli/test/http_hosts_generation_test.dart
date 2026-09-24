// `dartvel.http.hosts` read at generation, and installed at startup.
//
// The block was documented, read by DVHttp.declareFromConfig, and passed to
// it by nothing: a project that declared its payment gateway in pubspec.yaml
// met DV-HTTP-001 on the first DV.Http.host('paystack') in a running app, on
// either side. So the generator checks the block before it writes anything
// and emits the declaration, and both the client runtime and every generated
// server role install it before application code can make a request.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _validHttp = r'''
  http:
    hosts:
      paystack:
        baseUrl: https://api.paystack.co
        auth: { bearer: PAYSTACK_SECRET_KEY }
        timeout: 10s
        retries: { attempts: 2, backoff: exponential, jitter: false }
        circuitBreaker: { failureRate: 0.5, window: 30s, cooldown: 60s }
        pool: { maxConcurrent: 8 }
      shipping:
        baseUrl: https://ship.example.com/v2
        headers: { x-note: "it's $5 'quoted' \\ ok" }
''';

Directory _project(String http) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_http_gen_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: http_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
$http''');
  final File page = File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'));
  page.parent.createSync(recursive: true);
  page.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
  return dir;
}

String _read(Directory project, String name) =>
    File(p.join(project.path, 'lib', 'dartvel_client', name))
        .readAsStringSync();

/// Runs the generated http.g.dart in a fresh isolate against the real
/// dartvel_core, calls what the runtime calls, and returns what was declared.
Future<String> _installAndDescribe(Directory project) async {
  final File probe = File(p.join(project.path, 'probe.dart'));
  final String generated = p.toUri(
          p.join(project.path, 'lib', 'dartvel_client', 'http.g.dart'))
      .toString();
  probe.writeAsStringSync('''
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart';
import '$generated';

void main(List<String> args, SendPort out) {
  configureDartvelHttp();
  final DVHttpHostConfig paystack = const DVHttp().host('paystack').config;
  final DVHttpHostConfig shipping = const DVHttp().host('shipping').config;
  out.send(<String>[
    paystack.baseUrl,
    '\${paystack.bearerSecret}',
    '\${paystack.timeout.inSeconds}',
    '\${paystack.retries.attempts}',
    '\${paystack.retries.jitter}',
    '\${paystack.breaker!.cooldown.inSeconds}',
    '\${paystack.maxConcurrent}',
    shipping.baseUrl,
    '\${shipping.headers['x-note']}',
  ].join('|'));
}
''');
  final ReceivePort port = ReceivePort();
  final ReceivePort errors = ReceivePort();
  await Isolate.spawnUri(
    probe.uri,
    const <String>[],
    port.sendPort,
    packageConfig: await Isolate.packageConfig,
    onError: errors.sendPort,
  );
  final Object? result = await Future.any(<Future<Object?>>[
    port.first,
    errors.first.then((Object? e) => throw StateError('$e')),
  ]);
  port.close();
  errors.close();
  return '$result';
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDownAll(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Directory project(String http) {
    final Directory d = _project(http);
    made.add(d);
    return d;
  }

  group('a declared hosts block', () {
    late Directory dir;
    setUpAll(() async {
      dir = project(_validHttp);
      await routes.generate(root_: dir.path);
    });

    test('installs, in a running process, exactly the hosts the pubspec states',
        () async {
      expect(
        await _installAndDescribe(dir),
        'https://api.paystack.co|PAYSTACK_SECRET_KEY|10|2|false|60|8|'
        "https://ship.example.com/v2|it's \$5 'quoted' \\ ok",
      );
    });

    test('is exported from the barrel', () {
      expect(_read(dir, 'dartvel_client.dart'), contains("export 'http.g.dart';"));
    });

    test('imports nothing but dartvel_core, so the server can import it', () {
      final String generated = _read(dir, 'http.g.dart');
      expect(generated, isNot(contains('flutter')));
    });

    test('is installed by the client runtime before the application runs', () {
      final String runtime = _read(dir, 'dartvel_runtime.dart');
      expect(runtime, contains("import 'http.g.dart' show configureDartvelHttp;"));
      final int installed = runtime.indexOf('configureDartvelHttp();');
      expect(installed, greaterThan(-1));
      // Before the session client restores a stored session and before the
      // launch arguments are handled -- the first things that can call out.
      expect(installed, lessThan(runtime.indexOf('startDartvelLaunch(arguments);')));
    });

    test('is installed by every server role before it does any work', () {
      final String server = File(
              p.join(dir.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
          .readAsStringSync();
      expect(
          server,
          contains("import 'package:http_probe/dartvel_client/http.g.dart' "
              'show configureDartvelHttp;'));
      // startBackend, the worker and the cron process each start from their
      // own crash installation; the hosts go in right behind it in all three.
      final List<int> crashes = RegExp(r'_dartvelInstallServerCrashes\((processConfiguration\.role|process\.role)\);\n(?:\s*//[^\n]*\n)*\s*configureDartvelHttp\(\);')
          .allMatches(server)
          .map((Match m) => m.start)
          .toList();
      expect(crashes, hasLength(3), reason: 'web, worker and cron');
    });
  });

  test('a project that declares no hosts installs none, and still generates',
      () async {
    final Directory dir = project('');
    await routes.generate(root_: dir.path);
    final String generated = _read(dir, 'http.g.dart');
    expect(generated, contains('void configureDartvelHttp() {}'));
  });

  diagnosticsMain(project);

  group('a hosts block the reader does not understand stops the build', () {
    final Map<String, (String, String)> cases = <String, (String, String)>{
      'a misspelt host key': (
        _validHttp.replaceFirst('retries:', 'retry:'),
        'dartvel.http.hosts.paystack.retry',
      ),
      'a misspelt nested key': (
        _validHttp.replaceFirst('cooldown:', 'cooldwn:'),
        'dartvel.http.hosts.paystack.circuitBreaker.cooldwn',
      ),
      'a key beside hosts': (
        '$_validHttp    timeout: 5s\n',
        'dartvel.http.timeout',
      ),
      'a backoff nobody implements': (
        _validHttp.replaceFirst('backoff: exponential', 'backoff: linear'),
        'dartvel.http.hosts.paystack.retries.backoff',
      ),
      'a base URL that is not absolute': (
        _validHttp.replaceFirst('https://ship.example.com/v2', 'ship.example.com'),
        'dartvel.http.hosts.shipping.baseUrl',
      ),
    };

    for (final MapEntry<String, (String, String)> c in cases.entries) {
      test(c.key, () async {
        final Directory dir = project(c.value.$1);
        await expectLater(
          routes.generate(root_: dir.path),
          throwsA(isA<StateError>().having(
              (StateError e) => e.message, 'message', contains(c.value.$2))),
        );
        expect(
            Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
            isFalse,
            reason: 'a build that fails must not leave half a client behind');
      });
    }
  });
}

void _write(Directory project, String path, String source) {
  File(p.join(project.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);
}

// Declared outside main so the diagnostics group reads as its own section.
void diagnosticsMain(Directory Function(String) project) {
  group('outbound HTTP the build can see is wrong stops it', () {
    test('DV-HTTP-001: a backend function calling a host nobody declared',
        () async {
      final Directory dir = project(_validHttp);
      _write(dir, 'lib/backend/functions/charge.dart', '''
Future<void> handler() async {
  await DV.Http.post('https://api.paystak.co/charge', json: <String, Object?>{});
}
''');
      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
            allOf(contains('DV-HTTP-001'),
                contains('lib/backend/functions/charge.dart:2')))),
      );
      expect(Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
          isFalse);
    });

    test('DV-HTTP-005: a page using a host with a backend-scoped credential',
        () async {
      final Directory dir = project('''
  secrets:
    PAYSTACK_SECRET_KEY:
      scope: backend
$_validHttp''');
      _write(dir, 'lib/pages/pay.page.dart', '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Pay')
Widget _payPage(BuildContext context) {
  DV.Http.host('paystack').get('/balance');
  return const DVText('Pay');
}
''');
      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
            allOf(contains('DV-HTTP-005'), contains('lib/pages/pay.page.dart:7')))),
      );
      expect(Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
          isFalse);
    });

    test('the same call from a backend function builds', () async {
      final Directory dir = project(_validHttp);
      _write(dir, 'lib/backend/functions/balance.dart', '''
Future<int> handler() async {
  await DV.Http.host('paystack').get('/balance');
  await DV.Http.get('https://ship.example.com/v2/quote');
  return 1;
}
''');
      await routes.generate(root_: dir.path);
      expect(_read(dir, 'http.g.dart'), contains('configureDartvelHttp'));
    });
  });

  group('a mounted module declares its own hosts', () {
    // A module generated from an OpenAPI document or a GraphQL schema
    // carries the host its calls go to in its own pubspec. Nothing read it,
    // so every call that module made met DV-HTTP-001 in a running
    // application: the module was generated, mounted, imported and could not
    // make one request.
    void writeModule(Directory dir, String id, String host, String url) {
      final File pubspec =
          File(p.join(dir.path, 'modules', id, 'pubspec.yaml'));
      pubspec.parent.createSync(recursive: true);
      pubspec.writeAsStringSync('''
name: $id
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  module:
    id: $id
    kind: describedApi
  http:
    hosts:
      $host:
        baseUrl: $url
''');
    }

    void mount(Directory dir, List<String> ids) {
      final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      final StringBuffer entries = StringBuffer('  modules:\n');
      for (final String id in ids) {
        entries.write('    $id:\n'
            '      source:\n'
            '        path: modules/$id\n'
            '      mount: /$id\n');
      }
      pubspec.writeAsStringSync(
          '${pubspec.readAsStringSync().trimRight()}\n$entries');
    }

    test('and the generated client installs them beside the parent\'s',
        () async {
      final Directory dir = project(_validHttp);
      writeModule(dir, 'vendor', 'vendor', 'https://api.vendor.com');
      mount(dir, <String>['vendor']);

      await routes.generate(root_: dir.path);

      final String generated = _read(dir, 'http.g.dart');
      expect(generated, contains('paystack'));
      expect(generated, contains('vendor'));
      expect(generated, contains('https://api.vendor.com'));
    });

    test('a module whose host name the parent already uses stops the build',
        () async {
      // A host name decides a base URL and a credential. One quietly
      // winning would send the parent's bearer token to the module's
      // service, or the module's calls to the parent's.
      final Directory dir = project(_validHttp);
      writeModule(dir, 'vendor', 'paystack', 'https://api.vendor.com');
      mount(dir, <String>['vendor']);

      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', allOf(contains('paystack'), contains('vendor')))),
      );
    });

    test('two modules claiming one host name stop the build', () async {
      final Directory dir = project(_validHttp);
      writeModule(dir, 'alpha', 'shared', 'https://alpha.example.com');
      writeModule(dir, 'beta', 'shared', 'https://beta.example.com');
      mount(dir, <String>['alpha', 'beta']);

      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', allOf(contains('shared'), contains('beta')))),
      );
    });
  });
}
