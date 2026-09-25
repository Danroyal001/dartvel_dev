// @DVBackendFunction(mfa: ...) on the generated backend.
//
// DVMfa could say what a route needs and nothing generated asked it: a
// function declaring a second factor answered a password-only session like
// any other, which is the worst shape an authorization bug takes -- the
// declaration a developer ticked off is the one that does nothing. This
// generates a real backend, starts it in a child process and calls guarded
// and unguarded functions over HTTP with sessions at each strength.
//
// The silent failures:
//  * an mfa-required function running for a password-only session, or one
//    still waiting for its second factor;
//  * a recent-factor function running once the factor has gone stale;
//  * a refusal that reads as "sign in again" -- the client then discards a
//    live session -- instead of RFC 9470's step-up challenge;
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
  final LocalAuthProvider provider = LocalAuthProvider();
  final DVSecondFactors factors = DVSecondFactors(
    cipher: DVFieldCipher.secure(
        DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(32, 5))}')),
    issuer: 'Probe',
  );
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(provider: provider),
    secondFactors: factors,
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Map<String, Object?> credentials(String email) =>
      <String, Object?>{'email': email, 'password': password};

  try {
    // A password-only session on an account with no second factor.
    final String plain = tokenOf(
        await call(port, 'POST', '/auth/sign-up', body: credentials('ada@acme.test')));
    out['anonymousBilling'] = await call(port, 'GET', '/billing');
    out['plainOpen'] = await call(port, 'GET', '/open', bearer: plain);
    out['plainBilling'] = await call(port, 'GET', '/billing', bearer: plain);
    out['plainTransfer'] = await call(port, 'POST', '/transfer', bearer: plain);

    // An account with an authenticator: pending, then completed.
    final AuthUser grace = (await provider.signUp('grace@acme.test', password))!;
    final DVTotpEnrollment enrollment =
        await factors.beginTotp(grace.id, account: 'grace@acme.test');
    final List<int> secret = DVTotp.base32Decode(enrollment.secret);
    await factors.confirmTotp(grace.id,
        const DVTotp().generate(secret, at: DateTime.now().subtract(const Duration(seconds: 30))));
    final List<String> codes = (await factors.regenerateRecoveryCodes(grace.id)).codes;
    final String pending = tokenOf(
        await call(port, 'POST', '/auth/sign-in', body: credentials('grace@acme.test')));
    out['pendingBilling'] = await call(port, 'GET', '/billing', bearer: pending);
    final String strong = tokenOf(await call(port, 'POST', '/auth/second-factor',
        bearer: pending,
        body: <String, Object?>{
          'code': const DVTotp().generate(secret, at: DateTime.now()),
        }));
    out['strongBilling'] = await call(port, 'GET', '/billing', bearer: strong);
    out['strongTransfer'] = await call(port, 'POST', '/transfer', bearer: strong);

    // The transfer's window is three seconds.
    sleep(const Duration(seconds: 4));
    out['staleBilling'] = await call(port, 'GET', '/billing', bearer: strong);
    out['staleTransfer'] = await call(port, 'POST', '/transfer', bearer: strong);
    final String stepped = tokenOf(await call(port, 'POST', '/auth/second-factor',
        bearer: strong, body: <String, Object?>{'recoveryCode': codes.first}));
    out['steppedTransfer'] = await call(port, 'POST', '/transfer', bearer: stepped);
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
  final Directory project = Directory.systemTemp.createTempSync('dv_mfa_policy_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: mfa_policy_probe
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

void main() {
  group('a generated backend with mfa-guarded functions', () {
    late Directory project;
    late Map<String, Object?> r;

    setUpAll(() async {
      final String packages = await packagesDirectory();
      project = _project(packages, <String, String>{
        'lib/backend/functions/open.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _open(DVContext context) async => 'open';
''',
        'lib/backend/functions/billing.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(mfa: DVMfa.required)
Future<String> _billing(DVContext context) async => 'billing';
''',
        'lib/backend/functions/transfer.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(
  mfa: DVMfa.recent(Duration(seconds: 3)),
)
Future<String> _transfer(DVContext context) async => 'transferred';
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

    void expectStepUp(String key, {int? maxAge}) {
      expect(status(key), 401, reason: '$key: ${at(key)}');
      expect(at(key)['www'], contains('insufficient_user_authentication'),
          reason: key);
      expect((at(key)['json']! as Map)['error'], 'mfa_required', reason: key);
      if (maxAge != null) {
        expect(at(key)['www'], contains('max_age=$maxAge'), reason: key);
      }
      expect(at(key)['body'], isNot(contains('billing')));
      expect(at(key)['body'], isNot(contains('transferred')));
    }

    test('an unguarded function answers a password-only session', () {
      expect(status('plainOpen'), 200, reason: '${at('plainOpen')}');
    });

    test('nobody signed in is asked to sign in, not to step up', () {
      expect(status('anonymousBilling'), 401);
      expect(at('anonymousBilling')['www'],
          isNot(contains('insufficient_user_authentication')));
    });

    test('a password-only session is asked for a second factor', () {
      expectStepUp('plainBilling');
      expectStepUp('plainTransfer', maxAge: 3);
    });

    test('a session still waiting for its second factor runs nothing', () {
      expect(status('pendingBilling'), 401, reason: '${at('pendingBilling')}');
      expect(at('pendingBilling')['www'],
          contains('insufficient_user_authentication'));
    });

    test('a completed second factor runs both', () {
      expect(status('strongBilling'), 200, reason: '${at('strongBilling')}');
      expect(at('strongBilling')['body'], 'billing');
      expect(status('strongTransfer'), 200, reason: '${at('strongTransfer')}');
    });

    test('DVMfa.required stays satisfied; DVMfa.recent goes stale and a '
        'step-up satisfies it again', () {
      expect(status('staleBilling'), 200);
      expectStepUp('staleTransfer', maxAge: 3);
      expect(status('steppedTransfer'), 200, reason: '${at('steppedTransfer')}');
      expect(at('steppedTransfer')['body'], 'transferred');
    });
  });

  test('an mfa value the generator cannot read stops the build and names the '
      'file, rather than leaving the function unguarded', () async {
    final String packages = await packagesDirectory();
    final Directory project = _project(packages, <String, String>{
      'lib/backend/functions/payout.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

const DVMfa strict = DVMfa.required;

@DVBackendFunction(mfa: strict)
Future<String> _payout(DVContext context) async => 'paid';
''',
    });
    addTearDown(() => project.deleteSync(recursive: true));
    final ProcessResult generated = await _generate(packages, project.path);
    expect(generated.exitCode, isNot(0),
        reason: '${generated.stdout}\n${generated.stderr}');
    expect('${generated.stdout}${generated.stderr}', contains('payout.post.dart'));
    expect('${generated.stdout}${generated.stderr}', contains('mfa'));
  });
}
