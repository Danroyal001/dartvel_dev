// One session across an application's hosts, through the generated backend.
//
// An application whose dartvel.hosts serves app.example.test and
// *.tools.example.test is one application, and the session cookie was
// __Host-dv_session, which a browser locks to the host that set it: signed in
// on app.example.test, signed out on x.tools.example.test. This generates a
// real backend from a pubspec declaring those hosts, starts it in a child
// process and drives it over HTTP with the Host and Origin headers a browser
// sends -- asserting on what the server answered, never on generated text.
//
// The silent failures:
//  * the shared cookie set for a public suffix, or for "the last two labels";
//  * a redirecting host, or a host on another registrable domain, handed the
//    shared cookie;
//  * a state-changing request from a sibling the application does not serve
//    accepted as its own -- or one from its own sibling refused;
//  * the upgrade signing out everybody on the old __Host- cookie;
//  * sign-out on one host leaving the person signed in on another;
//  * a configuration naming a public suffix accepted at build time.
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

Future<Map<String, Object?>> call(
  int port,
  String method,
  String path, {
  required String host,
  String? origin,
  String? cookie,
  Object? body,
}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.host = host;
    request.headers.set('x-forwarded-proto', 'https');
    // What a browser sends on a fetch, and a script cannot suppress.
    request.headers.set('origin', origin ?? 'https://$host');
    request.headers.set('sec-fetch-mode', 'cors');
    if (cookie != null) request.headers.set('cookie', cookie);
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
      'setCookies': response.headers[HttpHeaders.setCookieHeader] ?? <String>[],
      'cacheControl': response.headers.value('cache-control'),
    };
  } finally {
    http.close(force: true);
  }
}

/// The name=value of the first Set-Cookie carrying a session token.
String? cookieOf(Map<String, Object?> answer) {
  for (final Object? set in answer['setCookies']! as List<Object?>) {
    final String pair = '$set'.split(';').first.trim();
    if (pair.contains('dvs_')) return pair;
  }
  return null;
}

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final Map<String, Object?> out = <String, Object?>{};
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Map<String, Object?> credentials(String email) =>
      <String, Object?>{'email': email, 'password': password};
  try {
    final Map<String, Object?> up = await call(port, 'POST', '/api/auth/sign-up',
        host: 'app.example.test', body: credentials('ada@example.test'));
    out['signUp'] = up;
    final String shared = cookieOf(up)!;
    out['whoamiSibling'] = await call(port, 'GET', '/api/whoami',
        host: 'x.tools.example.test', cookie: shared);
    out['sessionSibling'] = await call(port, 'GET', '/api/auth/session',
        host: 'x.tools.example.test', cookie: shared);
    out['sessionNobody'] = await call(port, 'GET', '/api/auth/session',
        host: 'x.tools.example.test');
    out['postFromForeignSibling'] = await call(
        port, 'POST', '/api/auth/sessions/revoke-others',
        host: 'app.example.test',
        origin: 'https://evil.example.test',
        cookie: shared);
    out['postFromRedirectHost'] = await call(
        port, 'POST', '/api/auth/sessions/revoke-others',
        host: 'app.example.test',
        origin: 'https://old.example.test',
        cookie: shared);
    out['postFromOwnSibling'] = await call(
        port, 'POST', '/api/auth/sessions/revoke-others',
        host: 'app.example.test',
        origin: 'https://x.tools.example.test',
        cookie: shared);

    // Another registrable domain keeps a host-only cookie of its own.
    out['signInOtherDomain'] = await call(port, 'POST', '/api/auth/sign-in',
        host: 'shop.example.net', body: credentials('ada@example.test'));

    // Somebody signed in before the upgrade, on the old cookie.
    final String token = shared.substring(shared.indexOf('=') + 1);
    out['whoamiLegacy'] = await call(port, 'GET', '/api/whoami',
        host: 'app.example.test', cookie: '__Host-dv_session=$token');

    // Signing out on one host signs out on every one.
    out['signOut'] = await call(port, 'POST', '/api/auth/sign-out',
        host: 'x.tools.example.test',
        cookie: '$shared; __Host-dv_session=$token');
    out['whoamiAfterSignOut'] = await call(port, 'GET', '/api/whoami',
        host: 'app.example.test', cookie: shared);
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

Future<(Directory, ProcessResult)> generate(String dartvelSection) async {
  final String packages = await packagesDirectory();
  final Directory project =
      Directory.systemTemp.createTempSync('dv_multi_host_session_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: multi_host_probe
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
$dartvelSection
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

@DVBackendFunction()
Future<String> _whoami(DVContext context) async =>
    context.session?.userId ?? 'anonymous';
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
  return (project, generated);
}

void main() {
  group('an application whose hosts share a registrable domain', () {
    late Directory project;
    late Map<String, Object?> r;

    setUpAll(() async {
      final ProcessResult generated;
      (project, generated) = await generate('''
  hosts:
    app.example.test:
      siteUrl: https://app.example.test
    '*.tools.example.test':
      mount: /tools/{label}
      siteUrl: 'https://{label}.tools.example.test'
    shop.example.net:
      mount: /shop
      siteUrl: https://shop.example.net
    old.example.test:
      redirect: https://app.example.test/
''');
      if (generated.exitCode != 0) {
        fail('dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
      }
      final ProcessResult resolved = await Process.run(
        Platform.resolvedExecutable,
        <String>['pub', 'get'],
        workingDirectory: project.path,
      );
      if (resolved.exitCode != 0) fail('pub get failed:\n${resolved.stderr}');
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
    List<String> setCookies(String key) => <String>[
          for (final Object? c in at(key)['setCookies']! as List<Object?>) '$c',
        ];

    test('signing in sets one cookie for the registrable domain', () {
      expect(status('signUp'), 200, reason: '${at('signUp')}');
      final List<String> cookies = setCookies('signUp');
      final String session =
          cookies.firstWhere((String c) => c.contains('dvs_'));
      expect(session, startsWith('__Secure-dv_session=dvs_'));
      expect(
        session.split('; '),
        containsAll(<String>[
          'Domain=example.test',
          'Path=/',
          'HttpOnly',
          'Secure',
          'SameSite=Lax',
        ]),
      );
    });

    test('a sibling host is signed in with it, and says who', () {
      expect(status('whoamiSibling'), 200, reason: '${at('whoamiSibling')}');
      expect(at('whoamiSibling')['body'], isNot(contains('anonymous')));
      expect(status('sessionSibling'), 200);
      final Map<String, Object?> json =
          at('sessionSibling')['json']! as Map<String, Object?>;
      expect((json['user']! as Map<String, Object?>)['email'],
          'ada@example.test');
      expect(status('sessionNobody'), 401);
    });

    test('a request from a sibling the application does not serve is '
        'refused, and its own sibling is not', () {
      expect(status('postFromForeignSibling'), 403);
      expect(status('postFromRedirectHost'), 403);
      expect(status('postFromOwnSibling'), 200,
          reason: '${at('postFromOwnSibling')}');
    });

    test('a host on another registrable domain keeps a host-only cookie', () {
      expect(status('signInOtherDomain'), 200);
      final String session = setCookies('signInOtherDomain')
          .firstWhere((String c) => c.contains('dvs_'));
      expect(session, startsWith('__Host-dv_session=dvs_'));
      expect(session, isNot(contains('Domain=')));
    });

    test('the old __Host- cookie still signs in, and moves to the new one', () {
      expect(status('whoamiLegacy'), 200, reason: '${at('whoamiLegacy')}');
      expect(at('whoamiLegacy')['body'], isNot(contains('anonymous')));
      final List<String> cookies = setCookies('whoamiLegacy');
      expect(cookies.any((String c) =>
              c.startsWith('__Secure-dv_session=dvs_') &&
              c.contains('Domain=example.test')),
          isTrue,
          reason: '$cookies');
      expect(cookies.any((String c) =>
              c.startsWith('__Host-dv_session=;') && c.contains('Max-Age=0')),
          isTrue,
          reason: '$cookies');
      // The response carries the session token, so no cache may keep it.
      expect(at('whoamiLegacy')['cacheControl'], 'no-store');
    });

    test('signing out on one host clears both cookies and every host', () {
      expect(status('signOut'), 204);
      final List<String> cookies = setCookies('signOut');
      expect(cookies.any((String c) =>
              c.startsWith('__Secure-dv_session=;') &&
              c.contains('Domain=example.test') &&
              c.contains('Max-Age=0')),
          isTrue,
          reason: '$cookies');
      expect(cookies.any((String c) =>
              c.startsWith('__Host-dv_session=;') && c.contains('Max-Age=0')),
          isTrue,
          reason: '$cookies');
      expect(status('whoamiAfterSignOut'), 401);
    });
  });

  test('a session domain that is a public suffix is refused at build time, '
      'naming why', () async {
    final (Directory project, ProcessResult generated) = await generate('''
  hosts:
    shop.co.uk:
      siteUrl: https://shop.co.uk
    admin.shop.co.uk:
      mount: /admin
      siteUrl: https://admin.shop.co.uk
  auth:
    sessionDomain: co.uk
''');
    try {
      expect(generated.exitCode, isNot(0));
      final String said = '${generated.stdout}\n${generated.stderr}';
      expect(said, contains('dartvel.auth.sessionDomain'));
      expect(said, contains('public suffix'));
    } finally {
      project.deleteSync(recursive: true);
    }
  });
}
