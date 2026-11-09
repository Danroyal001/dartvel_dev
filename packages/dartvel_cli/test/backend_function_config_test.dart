// @DVBackendFunction(authentication: ..., rateLimit: ...) on the generated
// backend.
//
// The Backend Function Request Lifecycle writes both as parameters of the
// function's own annotation, and the annotation had neither, so the sample the
// specification gives did not compile. This generates a real backend, starts
// it in a child process and calls each function over HTTP.
//
// The silent failures:
//  * a function declaring authentication: DVAuthentication.required running
//    for nobody, which reads as a working function until someone looks;
//  * a refusal for nobody that tells the client "forbidden" instead of asking
//    it to sign in;
//  * a declaration the generator cannot read being dropped, leaving the
//    function unguarded with a green build.
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
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port/api$path'));
    request.headers.set('x-tenant', 'acme');
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
    return <String, Object?>{
      'status': response.statusCode,
      'body': text,
      'json': json,
      'www': response.headers.value('www-authenticate'),
      'retryAfter': response.headers.value('retry-after'),
    };
  } finally {
    http.close(force: true);
  }
}

String tokenOf(Map<String, Object?> answer) =>
    (answer['json']! as Map)['token']! as String;

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final Map<String, Object?> out = <String, Object?>{};
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(provider: LocalAuthProvider()),
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  try {
    final String signedIn = tokenOf(await call(port, 'POST', '/auth/sign-up',
        body: <String, Object?>{'email': 'ada@acme.test', 'password': password}));
    out['anonymousAccount'] = await call(port, 'GET', '/account');
    out['signedInAccount'] = await call(port, 'GET', '/account', bearer: signedIn);
    out['anonymousOrder'] = await call(port, 'POST', '/order');
    out['signedInOrder'] = await call(port, 'POST', '/order', bearer: signedIn);
    out['anonymousBrowse'] = await call(port, 'GET', '/browse');
    out['anonymousCatalog'] = await call(port, 'GET', '/catalog');
    for (int i = 1; i <= 3; i++) {
      out['quote$i'] = await call(port, 'GET', '/quote');
    }
    out['quoteSignedIn'] = await call(port, 'GET', '/quote', bearer: signedIn);
    out['catalogAfterQuotes'] = await call(port, 'GET', '/catalog');
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

Future<ProcessResult> _generate(String packages, String project) {
  final String cliPackage = p.join(packages, 'dartvel_cli');
  return Process.run(
    Platform.resolvedExecutable,
    <String>[
      '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
      p.join(cliPackage, 'bin', 'routes.dart'),
    ],
    workingDirectory: project,
  );
}

Directory _project(String packages, Map<String, String> files) {
  final Directory project =
      Directory.systemTemp.createTempSync('dv_function_config_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: function_config_probe
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
  tenancy:
    source: header
''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  files.forEach(write);
  return project;
}

Future<void> _expectBuildStops(
  Map<String, String> files, {
  required String file,
  required String parameter,
}) async {
  final String packages = await packagesDirectory();
  final Directory project = _project(packages, files);
  addTearDown(() => project.deleteSync(recursive: true));
  final ProcessResult generated = await _generate(packages, project.path);
  final String output = '${generated.stdout}${generated.stderr}';
  expect(generated.exitCode, isNot(0), reason: output);
  expect(output, contains(file));
  expect(output, contains(parameter));
}

void main() {
  group('a generated backend with configured functions', () {
    late Directory project;
    late Map<String, Object?> r;

    setUpAll(() async {
      final String packages = await packagesDirectory();
      project = _project(packages, <String, String>{
        'lib/backend/functions/account.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(authentication: DVAuthentication.required)
Future<String> _account(DVContext context) async => 'account';
''',
        'lib/backend/functions/order.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(
  authentication: DVAuthentication.required,
)
Future<String> _order(String note) async => 'ordered';
''',
        'lib/backend/functions/browse.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(authentication: DVAuthentication.optional)
Future<String> _browse() async => 'browse';
''',
        'lib/backend/functions/catalog.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _catalog() async => 'catalog';
''',
        'lib/backend/functions/quote.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rateLimit: '2/minute')
Future<String> _quote() async => 'quote';
''',
        'bin/probe.dart': _probe,
      });
      final ProcessResult generated = await _generate(packages, project.path);
      if (generated.exitCode != 0) {
        throw StateError(
            'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
      }
      final ProcessResult resolved = await Process.run(
          Platform.resolvedExecutable, <String>['pub', 'get'],
          workingDirectory: project.path);
      if (resolved.exitCode != 0) {
        throw StateError('dart pub get failed:\n${resolved.stderr}');
      }
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'bin/probe.dart'],
        workingDirectory: project.path,
      ).timeout(const Duration(minutes: 4));
      final String? line = const LineSplitter()
          .convert('${result.stdout}')
          .where((String l) => l.startsWith('PROBE '))
          .firstOrNull;
      if (result.exitCode != 0 || line == null) {
        fail('the probe did not run (exit ${result.exitCode}):\n'
            '${result.stdout}\n${result.stderr}');
      }
      r = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    });

    tearDownAll(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });

    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    int status(String key) => at(key)['status']! as int;

    test('authentication: required refuses nobody with 401 and a sign-in '
        'challenge, before the function runs', () {
      for (final String key in <String>['anonymousAccount', 'anonymousOrder']) {
        expect(status(key), 401, reason: '$key: ${at(key)}');
        expect(at(key)['www'], 'Bearer', reason: key);
        expect(at(key)['body'], isNot(contains('account')), reason: key);
        expect(at(key)['body'], isNot(contains('ordered')), reason: key);
      }
    });

    test('authentication: required runs for a signed-in session', () {
      expect(status('signedInAccount'), 200, reason: '${at('signedInAccount')}');
      expect(at('signedInAccount')['body'], 'account');
      expect(status('signedInOrder'), 200, reason: '${at('signedInOrder')}');
      expect(at('signedInOrder')['body'], 'ordered');
    });

    test('authentication: optional, and no declaration, run for nobody', () {
      expect(status('anonymousBrowse'), 200, reason: '${at('anonymousBrowse')}');
      expect(at('anonymousBrowse')['body'], 'browse');
      expect(status('anonymousCatalog'), 200);
      expect(at('anonymousCatalog')['body'], 'catalog');
    });

    test('rateLimit: allows the declared number, then answers 429 with '
        'Retry-After without running the function', () {
      expect(status('quote1'), 200, reason: '${at('quote1')}');
      expect(status('quote2'), 200, reason: '${at('quote2')}');
      expect(status('quote3'), 429, reason: '${at('quote3')}');
      expect(at('quote3')['body'], isNot(contains('quote')));
      expect(int.parse(at('quote3')['retryAfter']! as String), greaterThan(0));
    });

    test('rateLimit: a signed-in caller has their own budget, and another '
        'function is not limited by it', () {
      expect(status('quoteSignedIn'), 200, reason: '${at('quoteSignedIn')}');
      expect(status('catalogAfterQuotes'), 200);
    });
  });

  test('a rateLimit the generator cannot read stops the build and names the '
      'file, rather than leaving the function unlimited', () async {
    await _expectBuildStops(<String, String>{
      'lib/backend/functions/search.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(rateLimit: '100 per hour')
Future<String> _search() async => 'found';
''',
    }, file: 'search.get.dart', parameter: 'rateLimit');
  });

  test('an authentication value the generator cannot read stops the build and '
      'names the file, rather than leaving the function unguarded', () async {
    await _expectBuildStops(<String, String>{
      'lib/backend/functions/payout.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

const DVAuthentication strict = DVAuthentication.required;

@DVBackendFunction(authentication: strict)
Future<String> _payout(DVContext context) async => 'paid';
''',
    }, file: 'payout.post.dart', parameter: 'authentication');
  });
}
