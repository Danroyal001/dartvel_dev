// Signing in, through the generated backend's own endpoints.
//
// The server authenticated a session on every route and nothing generated
// ever issued one: an application wrote its own sign-in function, picked where
// the token went, and every mistake available there still answers 200. This
// generates a real backend whose auth provider sits behind DVCredentialGuard,
// starts it in a child process and drives sign-up, sign-in, a second factor,
// an authorized request, the sessions endpoints and sign-out over HTTP --
// asserting on what the server answered, never on the generated text.
//
// The silent failures:
//  * a token handed to a browser in the response body, where a script can
//    read it, instead of an HttpOnly cookie -- or logged;
//  * a cookie without Secure or HttpOnly;
//  * a session issued before the second factor carrying full privilege;
//  * sign-out that forgets the token on the client and leaves it valid;
//  * revokeOthers revoking the current session, or another person's;
//  * sign-in answers that say whether an account exists, by body or by time,
//    including once a velocity limit trips;
//  * a sign-up with a breached password creating the account anyway.
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
  String? bearer,
  String? cookie,
  String client = 'native',
  bool csrf = true,
  Object? body,
}) async {
  final HttpClient http = HttpClient();
  final Stopwatch clock = Stopwatch()..start();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', 'acme');
    request.headers.set('x-forwarded-for', '203.0.113.7');
    if (client == 'native') {
      request.headers.set('x-dartvel-session-delivery', 'token');
    } else if (client == 'browser') {
      // What a browser sends and a script cannot suppress -- and a script
      // asking for the token as well, which it must not get.
      request.headers.set('origin', 'http://127.0.0.1:$port');
      request.headers.set('sec-fetch-mode', 'cors');
      request.headers.set('sec-fetch-site', 'same-origin');
      request.headers.set('x-dartvel-session-delivery', 'token');
    }
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (cookie != null) request.headers.set('cookie', cookie);
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
      'ms': clock.elapsedMilliseconds,
      'www': response.headers.value('www-authenticate'),
      'cacheControl': response.headers.value('cache-control'),
      'setCookie': response.headers[HttpHeaders.setCookieHeader]?.join('\n'),
    };
  } finally {
    http.close(force: true);
  }
}

/// The session token a Set-Cookie header carries, as a Cookie header.
String? cookieOf(Map<String, Object?> answer) {
  final String? set = answer['setCookie'] as String?;
  if (set == null) return null;
  return set.split(';').first.trim();
}

String? tokenOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  return json is Map ? json['token'] as String? : null;
}

String? sessionIdOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  final Object? session = json is Map ? json['session'] : null;
  return session is Map ? session['id'] as String? : null;
}

Future<void> main() async {
  final String mode = Platform.environment['PROBE_MODE'] ?? 'installed';
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  // With a database the server keeps accounts in it by default, so the
  // unconfigured server is one with no database as well.
  if (mode != 'unconfigured') const DVDatabase().configure(db);
  final Map<String, Object?> out = <String, Object?>{};
  final List<String> tokens = <String>[];
  void keep(Map<String, Object?> answer) {
    final String? token = tokenOf(answer);
    if (token != null) tokens.add(token);
    final String? cookie = cookieOf(answer);
    if (cookie != null && cookie.contains('dvs_')) {
      tokens.add(cookie.substring(cookie.indexOf('dvs_')));
    }
  }

  if (mode == 'unconfigured') {
    final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
    try {
      out['signIn'] = await call(handle.port as int, 'POST', '/api/auth/sign-in',
          body: <String, Object?>{'email': 'ada@acme.test', 'password': password});
    } finally {
      await handle.stop();
    }
    stdout.writeln('PROBE ${jsonEncode(out)}');
    exit(0);
  }

  final LocalAuthProvider provider = LocalAuthProvider();
  final DVSecondFactors factors = DVSecondFactors(
    cipher: DVFieldCipher.secure(
        DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(32, 7))}')),
    issuer: 'Probe',
  );
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(
      provider: provider,
      breachedPasswords: DVMemoryBreachedPasswords(<String>['password1234']),
      velocity: DVVelocityLimiter(
        perAccount: const DVVelocityBudget(3, Duration(minutes: 15)),
        perSource: const DVVelocityBudget(1000, Duration(minutes: 15)),
      ),
    ),
    secondFactors: factors,
  );

  // An account with an authenticator, and one that will be locked out.
  final AuthUser guarded = (await provider.signUp('mfa@acme.test', password))!;
  final DVTotpEnrollment enrollment =
      await factors.beginTotp(guarded.id, account: 'mfa@acme.test');
  final List<int> secret = DVTotp.base32Decode(enrollment.secret);
  await factors.confirmTotp(guarded.id,
      const DVTotp().generate(secret, at: DateTime.now().subtract(const Duration(seconds: 30))));
  await provider.signUp('carol@acme.test', password);

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Future<Map<String, Object?>> post(String path,
      {String client = 'native',
      String? bearer,
      String? cookie,
      bool csrf = true,
      Map<String, Object?>? body}) async {
    final Map<String, Object?> answer = await call(port, 'POST', '/api$path',
        client: client, bearer: bearer, cookie: cookie, csrf: csrf, body: body);
    keep(answer);
    return answer;
  }

  Future<Map<String, Object?>> get(String path,
          {String? bearer, String? cookie, String client = 'native'}) =>
      call(port, 'GET', '/api$path', bearer: bearer, cookie: cookie, client: client);

  Map<String, Object?> credentials(String email, [String secret = password]) =>
      <String, Object?>{'email': email, 'password': secret};

  try {
    // --- sign-up -------------------------------------------------------
    final Map<String, Object?> adaUp =
        await post('/auth/sign-up', body: credentials('ada@acme.test'));
    out['signUpNative'] = adaUp;
    final Map<String, Object?> graceUp = await post('/auth/sign-up',
        client: 'browser', body: credentials('grace@acme.test'));
    out['signUpBrowser'] = graceUp;
    out['signUpBreached'] = await post('/auth/sign-up',
        body: credentials('breach@acme.test', 'password1234'));
    out['signInBreached'] = await post('/auth/sign-in',
        body: credentials('breach@acme.test', 'password1234'));
    out['signUpWithoutCsrf'] = await post('/auth/sign-up',
        csrf: false, body: credentials('nocsrf@acme.test'));
    out['signInWithoutCsrf'] = await post('/auth/sign-in',
        csrf: false, body: credentials('ada@acme.test'));

    // --- refusals that must not tell accounts apart ---------------------
    out['signInUnknown'] =
        await post('/auth/sign-in', body: credentials('nobody@acme.test'));
    out['signInWrong'] = await post('/auth/sign-in',
        body: credentials('ada@acme.test', 'not the password at all'));
    for (int i = 0; i < 3; i++) {
      await post('/auth/sign-in',
          body: credentials('carol@acme.test', 'wrong password $i'));
      await post('/auth/sign-in',
          body: credentials('nobody2@acme.test', 'wrong password $i'));
    }
    out['lockedExisting'] =
        await post('/auth/sign-in', body: credentials('carol@acme.test'));
    out['lockedMissing'] =
        await post('/auth/sign-in', body: credentials('nobody2@acme.test'));

    // --- an authorized request ----------------------------------------
    final String adaToken = tokenOf(adaUp)!;
    final String graceCookie = cookieOf(graceUp)!;
    out['whoamiNative'] = await get('/whoami', bearer: adaToken);
    out['whoamiBrowser'] = await get('/whoami', cookie: graceCookie, client: 'browser');

    // --- sessions ------------------------------------------------------
    final Map<String, Object?> adaIn =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    out['signInNative'] = adaIn;
    final String adaSecond = tokenOf(adaIn)!;
    out['sessions'] = await get('/auth/sessions', bearer: adaSecond);
    out['session'] = await get('/auth/session', bearer: adaSecond);
    out['sessionAnonymous'] = await get('/auth/session');
    out['revokeForeign'] = await post('/auth/sessions/revoke',
        bearer: adaSecond, body: <String, Object?>{'id': sessionIdOf(graceUp)});
    out['whoamiGraceAfterForeign'] =
        await get('/whoami', cookie: graceCookie, client: 'browser');
    out['revokeOthersWithoutCsrf'] =
        await post('/auth/sessions/revoke-others', bearer: adaSecond, csrf: false);
    out['whoamiFirstAfterRefusedRevoke'] = await get('/whoami', bearer: adaToken);
    out['revokeOthers'] =
        await post('/auth/sessions/revoke-others', bearer: adaSecond);
    out['whoamiFirstAfterOthers'] = await get('/whoami', bearer: adaToken);
    out['whoamiSecondAfterOthers'] = await get('/whoami', bearer: adaSecond);
    out['whoamiGraceAfterOthers'] =
        await get('/whoami', cookie: graceCookie, client: 'browser');

    // A sign-in over a live session replaces it rather than leaving it.
    final Map<String, Object?> adaAgain = await post('/auth/sign-in',
        bearer: adaSecond, body: credentials('ada@acme.test'));
    out['signInOverSession'] = adaAgain;
    out['whoamiReplaced'] = await get('/whoami', bearer: adaSecond);
    final String adaThird = tokenOf(adaAgain)!;

    // --- a second factor ----------------------------------------------
    final Map<String, Object?> pending =
        await post('/auth/sign-in', body: credentials('mfa@acme.test'));
    out['signInMfa'] = pending;
    final String pendingToken = tokenOf(pending)!;
    out['whoamiPending'] = await get('/whoami', bearer: pendingToken);
    out['sessionsPending'] = await get('/auth/sessions', bearer: pendingToken);
    out['secondFactorWrong'] = await post('/auth/second-factor',
        bearer: pendingToken,
        body: <String, Object?>{
          'code': const DVTotp().generate(secret,
              at: DateTime.now().add(const Duration(minutes: 10))),
        });
    final Map<String, Object?> completed = await post('/auth/second-factor',
        bearer: pendingToken,
        body: <String, Object?>{
          'code': const DVTotp().generate(secret, at: DateTime.now()),
        });
    out['secondFactor'] = completed;
    out['whoamiPendingAfter'] = await get('/whoami', bearer: pendingToken);
    out['whoamiMfa'] = await get('/whoami', bearer: tokenOf(completed));
    out['guardedId'] = guarded.id;

    final Map<String, Object?> browserPending = await post('/auth/sign-in',
        client: 'browser', body: credentials('mfa@acme.test'));
    out['signInMfaBrowser'] = browserPending;
    out['whoamiPendingBrowser'] = await get('/whoami',
        cookie: cookieOf(browserPending), client: 'browser');
    final Map<String, Object?> recovery = await factors
        .regenerateRecoveryCodes(guarded.id)
        .then((DVRecoveryCodes codes) => post('/auth/second-factor',
            client: 'browser',
            cookie: cookieOf(browserPending),
            body: <String, Object?>{'recoveryCode': codes.codes.first}));
    out['secondFactorBrowser'] = recovery;
    out['whoamiMfaBrowser'] =
        await get('/whoami', cookie: cookieOf(recovery), client: 'browser');

    // --- sign-out ------------------------------------------------------
    out['signOutNative'] = await post('/auth/sign-out', bearer: adaThird);
    out['whoamiAfterSignOut'] = await get('/whoami', bearer: adaThird);
    out['signOutBrowser'] =
        await post('/auth/sign-out', client: 'browser', cookie: graceCookie);
    out['whoamiBrowserAfterSignOut'] =
        await get('/whoami', cookie: graceCookie, client: 'browser');
  } finally {
    await handle.stop();
  }
  out['tokens'] = tokens;
  out['logs'] = <String>[
    for (final DVLogRecord record in DV.ObservabilityAndLogging.recentLogs)
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

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_session_sign_in_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: sign_in_probe
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
    write('lib/backend/functions/whoami.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

/// Who the injected context says is calling.
String describeCaller(DVContext context) {
  final DVSessionPrincipal? session = context.session;
  return session == null ? 'anonymous' : '\${session.userId}@\${session.tenant}';
}

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

  Future<(Map<String, Object?>, String)> probe(
      [Map<String, String> environment = const <String, String>{}]) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      environment: environment,
    ).timeout(const Duration(minutes: 4));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    final String rest = output.replaceFirst(line, '');
    return (
      jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>,
      rest,
    );
  }

  group('the generated sign-in endpoints', () {
    late Map<String, Object?> r;
    late String processOutput;

    setUpAll(() async {
      (r, processOutput) = await probe();
    });

    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    int status(String key) => at(key)['status']! as int;
    String body(String key) => at(key)['body']! as String;
    Map<String, Object?> json(String key) =>
        at(key)['json']! as Map<String, Object?>;
    String? setCookie(String key) => at(key)['setCookie'] as String?;
    String userIdOf(String key) =>
        (json(key)['user']! as Map<String, Object?>)['id']! as String;

    group('delivery', () {
      test('a native client gets the token in the body and no cookie', () {
        expect(status('signUpNative'), 200, reason: '${at('signUpNative')}');
        expect(json('signUpNative')['token'], startsWith('dvs_'));
        expect(setCookie('signUpNative'), isNull);
        expect(at('signUpNative')['cacheControl'], 'no-store');
      });

      test('a browser gets a Secure HttpOnly host cookie and never the token '
          'in the body, even when a script asks for it', () {
        expect(status('signUpBrowser'), 200, reason: '${at('signUpBrowser')}');
        final String cookie = setCookie('signUpBrowser')!;
        expect(cookie, startsWith('__Host-dv_session=dvs_'));
        expect(cookie.split('; '),
            containsAll(<String>['Path=/', 'HttpOnly', 'Secure', 'SameSite=Lax']));
        expect(body('signUpBrowser'), isNot(contains('dvs_')));
        expect(json('signUpBrowser'), isNot(contains('token')));
      });

      test('the same holds for a sign-in and a completed second factor', () {
        expect(setCookie('signInNative'), isNull);
        expect(json('signInNative')['token'], startsWith('dvs_'));
        for (final String key in <String>['signInMfaBrowser', 'secondFactorBrowser']) {
          expect(status(key), 200, reason: '$key: ${at(key)}');
          expect(setCookie(key), contains('__Host-dv_session=dvs_'), reason: key);
          expect(body(key), isNot(contains('dvs_')), reason: key);
        }
      });

      test('no token is written to a log or to the process output', () {
        final List<Object?> tokens = r['tokens']! as List<Object?>;
        expect(tokens, isNotEmpty);
        for (final Object? token in tokens) {
          expect('${r['logs']}', isNot(contains('$token')));
          expect(processOutput, isNot(contains('$token')));
        }
      });

      test('a state-changing auth request still needs a CSRF token', () {
        expect(status('signUpWithoutCsrf'), 403);
        expect(status('signInWithoutCsrf'), 403);
        expect(status('revokeOthersWithoutCsrf'), 403);
        expect(status('whoamiFirstAfterRefusedRevoke'), 200);
      });
    });

    group('credentials', () {
      test('the session authorizes a request, bearer and cookie alike', () {
        expect(body('whoamiNative'), '${userIdOf('signUpNative')}@acme');
        expect(body('whoamiBrowser'), '${userIdOf('signUpBrowser')}@acme');
      });

      test('an unknown account and a wrong password get one answer', () {
        expect(status('signInUnknown'), 400, reason: '${at('signInUnknown')}');
        expect(status('signInWrong'), status('signInUnknown'));
        expect(body('signInWrong'), body('signInUnknown'));
        expect(setCookie('signInUnknown'), isNull);
        expect(body('signInUnknown'), isNot(contains('dvs_')));
        // Padded to the guard's floor, however quickly the provider answered.
        expect(at('signInUnknown')['ms'], greaterThanOrEqualTo(350));
        expect(at('signInWrong')['ms'], greaterThanOrEqualTo(350));
      });

      test('a tripped velocity limit answers the same whether or not the '
          'account exists, and never tries the right password', () {
        expect(status('lockedExisting'), 429, reason: '${at('lockedExisting')}');
        expect(status('lockedMissing'), 429);
        expect(body('lockedExisting'), body('lockedMissing'));
        expect(body('lockedExisting'), isNot(contains('dvs_')));
      });

      test('a breached password is refused at sign-up and no account exists',
          () {
        expect(status('signUpBreached'), 400);
        expect(body('signUpBreached'), contains('DV-EDGE-004'));
        expect(status('signInBreached'), 400);
        expect(body('signInBreached'), body('signInUnknown'));
      });
    });

    group('a second factor', () {
      test('a session awaiting its second factor authorizes nothing', () {
        expect(status('signInMfa'), 200, reason: '${at('signInMfa')}');
        expect(json('signInMfa')['mfaRequired'], isTrue);
        for (final String key in <String>[
          'whoamiPending',
          'sessionsPending',
          'whoamiPendingBrowser',
        ]) {
          expect(status(key), 401, reason: '$key: ${at(key)}');
          expect(at(key)['www'], contains('insufficient_user_authentication'),
              reason: key);
        }
      });

      test('a wrong code is refused', () {
        expect(status('secondFactorWrong'), 400,
            reason: '${at('secondFactorWrong')}');
        expect(body('secondFactorWrong'), isNot(contains('dvs_')));
      });

      test('the right code rotates the session and records the factor', () {
        expect(status('secondFactor'), 200, reason: '${at('secondFactor')}');
        final String rotated = json('secondFactor')['token']! as String;
        expect(rotated, isNot(json('signInMfa')['token']));
        final Map<String, Object?> session =
            json('secondFactor')['session']! as Map<String, Object?>;
        expect(session['mfaSatisfiedAt'], isNotNull);
        expect(status('whoamiPendingAfter'), 401);
        expect(body('whoamiMfa'), '${r['guardedId']}@acme');
      });

      test('a recovery code completes it in a browser, rotating the cookie', () {
        expect(setCookie('secondFactorBrowser'),
            isNot(setCookie('signInMfaBrowser')));
        expect(status('whoamiMfaBrowser'), 200,
            reason: '${at('whoamiMfaBrowser')}');
      });
    });

    group('sessions', () {
      test('the list is this person\'s, newest first, with this one current',
          () {
        expect(status('sessions'), 200, reason: '${at('sessions')}');
        final List<Object?> sessions = json('sessions')['sessions']! as List<Object?>;
        expect(sessions, hasLength(2));
        final List<Object?> current = <Object?>[
          for (final Object? s in sessions)
            if ((s! as Map<String, Object?>)['isCurrent'] == true) s,
        ];
        expect(current, hasLength(1));
        expect((current.single! as Map<String, Object?>)['id'],
            (json('signInNative')['session']! as Map<String, Object?>)['id']);
        expect(body('sessions'), isNot(contains('dvs_')));
      });

      test('the current session is described without its token', () {
        expect(status('session'), 200);
        expect((json('session')['session']! as Map<String, Object?>)['id'],
            (json('signInNative')['session']! as Map<String, Object?>)['id']);
        expect(body('session'), isNot(contains('dvs_')));
        expect(status('sessionAnonymous'), 401);
      });

      test('another person\'s session cannot be revoked, or told apart from '
          'one that does not exist', () {
        expect(status('revokeForeign'), 404, reason: '${at('revokeForeign')}');
        expect(status('whoamiGraceAfterForeign'), 200);
      });

      test('revokeOthers revokes the others and keeps this one and everyone '
          'else\'s', () {
        expect(status('revokeOthers'), 200, reason: '${at('revokeOthers')}');
        expect(json('revokeOthers')['revoked'], 1);
        expect(status('whoamiFirstAfterOthers'), 401);
        expect(status('whoamiSecondAfterOthers'), 200);
        expect(status('whoamiGraceAfterOthers'), 200);
      });

      test('signing in over a live session replaces it', () {
        expect(status('signInOverSession'), 200);
        expect(status('whoamiReplaced'), 401);
      });
    });

    group('sign-out', () {
      test('revokes the session on the server, not only on the client', () {
        expect(status('signOutNative'), 204, reason: '${at('signOutNative')}');
        expect(status('whoamiAfterSignOut'), 401);
      });

      test('clears the browser\'s cookie and the cookie stops working', () {
        expect(status('signOutBrowser'), 204);
        expect(setCookie('signOutBrowser'),
            allOf(startsWith('__Host-dv_session=;'), contains('Max-Age=0'),
                contains('Secure'), contains('HttpOnly')));
        expect(status('whoamiBrowserAfterSignOut'), 401);
      });
    });
  });

  test('without an auth provider installed or a database to keep accounts '
      'in, signing in is a configuration error that says what to install', () async {
    final (Map<String, Object?> r, String _) =
        await probe(const <String, String>{'PROBE_MODE': 'unconfigured'});
    final Map<String, Object?> answer = r['signIn']! as Map<String, Object?>;
    expect(answer['status'], 503, reason: '$answer');
    expect(answer['body'], contains('DVAuthEndpoints.install'));
  });
}
