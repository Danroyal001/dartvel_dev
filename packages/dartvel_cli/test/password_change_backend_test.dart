// Changing the password, through the generated backend's own endpoint.
//
// SecurityPage said "password" in the specification and had no way to change
// one: an application wrote the endpoint, and each mistake available there
// still answers 200. This generates a real backend, starts it in a child
// process and drives POST /auth/account/password over HTTP.
//
// The silent failures:
//  * a change made with the session alone -- no current password, or a wrong
//    one that is not counted like one at sign-in;
//  * a change on an account with a second factor made without a fresh one;
//  * a new password from a breach corpus, or one the provider calls weak;
//  * the person's other sessions left working after the change -- the thief
//    whose session the change was meant to end keeps it -- or the session
//    making the change kept under the same token;
//  * the password echoed in an answer or written to a log.
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
const String oldPassword = 'correct horse battery staple';
const String newPassword = 'tr0ubadour and a second staple';
const String breached = 'password1234567890';
const String missing = 'dvs_missing';

Future<Map<String, Object?>> call(int port, String method, String path,
    {String? bearer, bool csrf = true, Object? body, String tenant = 'acme'}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port/api$path'));
    request.headers.set('x-tenant', tenant);
    request.headers.set('x-dartvel-session-delivery', 'token');
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (method != 'GET') {
      if (csrf) request.headers.set('x-dartvel-csrf-token', csrfToken);
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

String tokenOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  final Object? token = json is Map ? json['token'] : null;
  return token is String ? token : missing;
}

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final Map<String, Object?> out = <String, Object?>{};
  final LocalAuthProvider provider = LocalAuthProvider();
  final DVSecondFactors factors = DVSecondFactors(
    cipher: DVFieldCipher.secure(
        DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(32, 3))}')),
    issuer: 'Probe',
  );
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(
      provider: provider,
      breachedPasswords: DVMemoryBreachedPasswords(<String>[breached]),
      velocity: DVVelocityLimiter(
        perAccount: const DVVelocityBudget(50, Duration(minutes: 15)),
        perSource: const DVVelocityBudget(1000, Duration(minutes: 15)),
      ),
    ),
    secondFactors: factors,
    stepUpWindow: const Duration(seconds: 2),
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Future<Map<String, Object?>> post(String path,
          {String? bearer, bool csrf = true, Map<String, Object?>? body, String tenant = 'acme'}) =>
      call(port, 'POST', path, bearer: bearer, csrf: csrf, body: body, tenant: tenant);
  Future<Map<String, Object?>> get(String path, {String? bearer, String tenant = 'acme'}) =>
      call(port, 'GET', path, bearer: bearer, tenant: tenant);
  Map<String, Object?> credentials(String email, String password) =>
      <String, Object?>{'email': email, 'password': password};
  Map<String, Object?> change(String? current, String next, {String? code, String? recoveryCode}) =>
      <String, Object?>{
        if (current != null) 'currentPassword': current,
        'newPassword': next,
        if (code != null) 'code': code,
        if (recoveryCode != null) 'recoveryCode': recoveryCode,
      };

  try {
    final String ada = tokenOf(
        await post('/auth/sign-up', body: credentials('ada@acme.test', oldPassword)));
    final String adaLaptop = tokenOf(
        await post('/auth/sign-in', body: credentials('ada@acme.test', oldPassword)));
    final String adaPhone = tokenOf(
        await post('/auth/sign-in', body: credentials('ada@acme.test', oldPassword)));
    final String adaElsewhere = tokenOf(await post('/auth/sign-in',
        body: credentials('ada@acme.test', oldPassword), tenant: 'globex'));
    await post('/auth/sign-up', body: credentials('grace@acme.test', oldPassword));
    final String grace = tokenOf(
        await post('/auth/sign-in', body: credentials('grace@acme.test', oldPassword)));

    // --- refusals ------------------------------------------------------------
    out['anonymous'] = await post('/auth/account/password', body: change(oldPassword, newPassword));
    out['withoutCsrf'] = await post('/auth/account/password',
        bearer: ada, csrf: false, body: change(oldPassword, newPassword));
    out['noCurrent'] = await post('/auth/account/password',
        bearer: ada, body: change(null, newPassword));
    out['wrongCurrent'] = await post('/auth/account/password',
        bearer: ada, body: change('not the password', newPassword));
    out['weak'] = await post('/auth/account/password',
        bearer: ada, body: change(oldPassword, 'short'));
    out['breached'] = await post('/auth/account/password',
        bearer: ada, body: change(oldPassword, breached));
    out['unchanged'] = await post('/auth/account/password',
        bearer: ada, body: change(oldPassword, oldPassword));
    out['oldStillSignsIn'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test', oldPassword));
    out['laptopAfterRefusals'] = await get('/auth/account', bearer: adaLaptop);

    // --- the change ----------------------------------------------------------
    final Map<String, Object?> changed = await post('/auth/account/password',
        bearer: ada, body: change(oldPassword, newPassword));
    out['change'] = changed;
    final String adaRotated = tokenOf(changed);
    out['rotatedWorks'] = await get('/auth/account', bearer: adaRotated);
    out['oldTokenAfter'] = await get('/auth/account', bearer: ada);
    out['laptopAfter'] = await get('/auth/account', bearer: adaLaptop);
    out['phoneAfter'] = await get('/auth/account', bearer: adaPhone);
    out['elsewhereAfter'] =
        await get('/auth/account', bearer: adaElsewhere, tenant: 'globex');
    out['graceAfter'] = await get('/auth/account', bearer: grace);
    out['signInOld'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test', oldPassword));
    out['signInNew'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test', newPassword));

    // --- an account with a second factor -------------------------------------
    final AuthUser carol = (await provider.signUp('carol@acme.test', oldPassword))!;
    final DVTotpEnrollment enrollment =
        await factors.beginTotp(carol.id, account: 'carol@acme.test');
    final List<int> secret = DVTotp.base32Decode(enrollment.secret);
    await factors.confirmTotp(carol.id,
        const DVTotp().generate(secret, at: DateTime.now().subtract(const Duration(seconds: 30))));
    out['carolEnrolled'] = await factors.hasTotp(carol.id);
    final List<String> codes = (await factors.regenerateRecoveryCodes(carol.id)).codes;
    final Map<String, Object?> carolIn =
        await post('/auth/sign-in', body: credentials('carol@acme.test', oldPassword));
    final String carolSession = tokenOf(await post('/auth/second-factor',
        bearer: tokenOf(carolIn), body: <String, Object?>{'recoveryCode': codes[0]}));
    // Older than the step-up window.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    out['carolStale'] = await post('/auth/account/password',
        bearer: carolSession, body: change(oldPassword, newPassword));
    out['carolWrongCode'] = await post('/auth/account/password',
        bearer: carolSession, body: change(oldPassword, newPassword, recoveryCode: 'XXXXX-XXXXX'));
    out['carolUnchanged'] =
        await post('/auth/sign-in', body: credentials('carol@acme.test', oldPassword));
    final Map<String, Object?> carolChanged = await post('/auth/account/password',
        bearer: carolSession,
        body: change(oldPassword, newPassword, recoveryCode: codes[1]));
    out['carolWithCode'] = carolChanged;
    // A factor presented moments ago on the session is fresh enough.
    final String carolFresh = tokenOf(carolChanged);
    out['carolRecent'] = await post('/auth/account/password',
        bearer: carolFresh, body: change(newPassword, oldPassword));
  } finally {
    await handle.stop();
  }
  out['logs'] = <String>[
    for (final DVLogRecord record in DVObservability.recentLogs)
      '${record.message} ${record.context} ${record.error}',
  ];
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
  late Map<String, Object?> r;
  late String processOutput;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_password_change_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: password_change_probe
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
    write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong';
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
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    r = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    processOutput = output.replaceFirst(line, '');
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;
  String body(String key) => at(key)['body']! as String;
  Map<String, Object?> json(String key) => at(key)['json']! as Map<String, Object?>;

  group('is refused', () {
    test('signed out or without a CSRF token', () {
      expect(status('anonymous'), 401);
      expect(status('withoutCsrf'), 403);
    });

    test('without the current password, or with a wrong one', () {
      expect(status('noCurrent'), 400, reason: '${at('noCurrent')}');
      expect(json('noCurrent')['error'], 'invalid_request');
      expect(status('wrongCurrent'), 400, reason: '${at('wrongCurrent')}');
      expect(json('wrongCurrent')['error'], 'invalid_credentials');
    });

    test('for a new password the provider calls weak, one in a breach, or '
        'the same one', () {
      expect(status('weak'), 400, reason: '${at('weak')}');
      expect(json('weak')['error'], 'weak_password');
      expect(status('breached'), 400, reason: '${at('breached')}');
      expect(json('breached')['error'], 'breached_password');
      expect(status('unchanged'), 400, reason: '${at('unchanged')}');
      expect(json('unchanged')['error'], 'password_unchanged');
    });

    test('and a refusal changes nothing and ends no session', () {
      expect(status('oldStillSignsIn'), 200);
      expect(status('laptopAfterRefusals'), 200);
    });
  });

  group('with the current password', () {
    test('changes it, so only the new one signs in', () {
      expect(status('change'), 200, reason: '${at('change')}');
      expect(status('signInOld'), 400);
      expect(status('signInNew'), 200);
    });

    test('rotates this session and ends every other one of the person\'s, on '
        'every tenant, and nobody else\'s', () {
      expect(status('rotatedWorks'), 200);
      expect(status('oldTokenAfter'), 401);
      expect(status('laptopAfter'), 401);
      expect(status('phoneAfter'), 401);
      expect(status('elsewhereAfter'), 401);
      // The laptop, the phone, the other tenant, and the sign-in that proved
      // the old password still worked after the refusals.
      expect(json('change')['revoked'], 4);
      expect(status('graceAfter'), 200);
    });
  });

  group('on an account with a second factor', () {
    test('a factor older than the step-up window is refused as a step-up',
        () {
      expect(r['carolEnrolled'], isTrue);
      expect(status('carolStale'), 401, reason: '${at('carolStale')}');
      expect(at('carolStale')['www'], contains('insufficient_user_authentication'));
      expect(status('carolWrongCode'), 400, reason: '${at('carolWrongCode')}');
      expect(json('carolWrongCode')['error'], 'invalid_code');
      expect(status('carolUnchanged'), 200);
    });

    test('a factor in the request, or one presented within the window, lets '
        'it through', () {
      expect(status('carolWithCode'), 200, reason: '${at('carolWithCode')}');
      expect(status('carolRecent'), 200, reason: '${at('carolRecent')}');
    });
  });

  test('no password reaches an answer, a log or the process output', () {
    const List<String> passwords = <String>[
      'correct horse battery staple',
      'tr0ubadour and a second staple',
      'password1234567890',
    ];
    for (final String key in r.keys.where((String k) => r[k] is Map)) {
      for (final String password in passwords) {
        expect(body(key), isNot(contains(password)), reason: key);
      }
    }
    for (final String password in passwords) {
      expect('${r['logs']}', isNot(contains(password)));
      expect(processOutput, isNot(contains(password)));
    }
  });
}
