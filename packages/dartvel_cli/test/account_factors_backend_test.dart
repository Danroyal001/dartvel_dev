// Enrolling, regenerating and removing a second factor, through the generated
// backend's own endpoints.
//
// DVSecondFactors could begin and confirm a TOTP enrollment, generate
// recovery codes and remove an authenticator, and nothing served any of it:
// an application wrote its own endpoints, and every mistake available there
// still answers 200. This generates a real backend, starts it in a child
// process and drives enrollment, recovery codes, step-up and removal over
// HTTP -- asserting on what the server answered and what it stored, never on
// the generated text.
//
// The silent failures:
//  * a factor that is active before its first code is confirmed, so an
//    enrollment abandoned half way locks the account behind an app nobody
//    set up -- or the QR code encodes a different secret than the stored one;
//  * recovery codes that can be read a second time, or are stored as
//    themselves, or survive being regenerated;
//  * a factor removed by a session that did not present a second factor in
//    the same request;
//  * a factor changed without rotating the session, or by a session still
//    waiting for its own second factor;
//  * the secret or a recovery code written to a log.
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
import 'package:dartvel_core/dv.dart';

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
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', 'acme');
    request.headers.set('x-forwarded-for', '203.0.113.9');
    if (client == 'native') {
      request.headers.set('x-dartvel-session-delivery', 'token');
    } else {
      request.headers.set('origin', 'http://127.0.0.1:$port');
      request.headers.set('sec-fetch-mode', 'cors');
      request.headers.set('sec-fetch-site', 'same-origin');
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
      'www': response.headers.value('www-authenticate'),
      'cacheControl': response.headers.value('cache-control'),
      'setCookie': response.headers[HttpHeaders.setCookieHeader]?.join('\n'),
    };
  } finally {
    http.close(force: true);
  }
}

String? cookieOf(Map<String, Object?> answer) {
  final String? set = answer['setCookie'] as String?;
  return set?.split(';').first.trim();
}

// Stands in for a token or a code an answer did not carry, so the probe runs
// to the end and the assertion that owns the failure is the one that reports.
const String missing = 'dvs_missing';

List<String> codesOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  final Object? codes = json is Map ? json['recoveryCodes'] : null;
  return <String>[
    if (codes is List) for (final Object? c in codes) '$c',
    'AAAAA-AAAAA', 'BBBBB-BBBBB',
  ];
}

String? tokenOf(Map<String, Object?> answer) {
  final Object? json = answer['json'];
  return json is Map ? json['token'] as String? : null;
}

Future<void> main() async {
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  const DVDatabase().configure(db);
  final Map<String, Object?> out = <String, Object?>{};
  final List<String> secrets = <String>[];

  final LocalAuthProvider provider = LocalAuthProvider();
  final DVSecondFactors factors = DVSecondFactors(
    cipher: DVFieldCipher.secure(
        DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(32, 9))}')),
    issuer: 'Probe',
  );
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(
      provider: provider,
      velocity: DVVelocityLimiter(
        perAccount: const DVVelocityBudget(50, Duration(minutes: 15)),
        perSource: const DVVelocityBudget(1000, Duration(minutes: 15)),
      ),
    ),
    secondFactors: factors,
    stepUpWindow: const Duration(seconds: 3),
  );

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Future<Map<String, Object?>> post(String path,
          {String client = 'native',
          String? bearer,
          String? cookie,
          bool csrf = true,
          Map<String, Object?>? body}) =>
      call(port, 'POST', '/api$path',
          client: client, bearer: bearer, cookie: cookie, csrf: csrf, body: body);
  Future<Map<String, Object?>> get(String path,
          {String? bearer, String? cookie, String client = 'native'}) =>
      call(port, 'GET', '/api$path', bearer: bearer, cookie: cookie, client: client);
  Map<String, Object?> credentials(String email) =>
      <String, Object?>{'email': email, 'password': password};
  String code(List<int> secret, {Duration offset = Duration.zero}) =>
      const DVTotp().generate(secret, at: DateTime.now().add(offset));

  try {
    final Map<String, Object?> up =
        await post('/auth/sign-up', body: credentials('ada@acme.test'));
    final String t0 = tokenOf(up)!;
    final String userId = ((up['json']! as Map)['user']! as Map)['id']! as String;
    out['userId'] = userId;

    out['statusBefore'] = await get('/auth/factors', bearer: t0);
    out['beginAnonymous'] = await post('/auth/factors/totp');
    out['beginWithoutCsrf'] = await post('/auth/factors/totp', bearer: t0, csrf: false);
    out['codesWithoutFactor'] = await post('/auth/factors/recovery-codes', bearer: t0);

    // --- begin: nothing is active until a code confirms ----------------
    final Map<String, Object?> begin = await post('/auth/factors/totp', bearer: t0);
    out['begin'] = begin;
    final Map<String, Object?> beginJson = begin['json']! as Map<String, Object?>;
    final String secret = beginJson['secret']! as String;
    secrets.add(secret);
    out['activeAfterBegin'] = await factors.hasTotp(userId);
    out['signInAfterBegin'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    out['whoamiAfterBegin'] = await get('/whoami', bearer: t0);

    // The QR code encodes the URI, so a code made from the URI's own secret
    // is what proves the URI and the stored secret are one.
    final Uri uri = Uri.parse(beginJson['uri']! as String);
    final List<int> fromUri =
        DVTotp.base32Decode(uri.queryParameters['secret']!);
    out['confirmWrong'] = await post('/auth/factors/totp/confirm',
        bearer: t0,
        body: <String, Object?>{'code': code(fromUri, offset: const Duration(minutes: 10))});
    out['activeAfterWrong'] = await factors.hasTotp(userId);
    final Map<String, Object?> confirmed = await post('/auth/factors/totp/confirm',
        bearer: t0, body: <String, Object?>{'code': code(fromUri)});
    out['confirm'] = confirmed;
    out['activeAfterConfirm'] = await factors.hasTotp(userId);
    final String t1 = tokenOf(confirmed) ?? missing;
    out['whoamiOldAfterConfirm'] = await get('/whoami', bearer: t0);
    out['whoamiNewAfterConfirm'] = await get('/whoami', bearer: t1);
    out['beginAgain'] = await post('/auth/factors/totp', bearer: t1);
    out['signInAfterConfirm'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    final String pending = tokenOf(out['signInAfterConfirm']! as Map<String, Object?>) ?? missing;
    out['codesPending'] = await post('/auth/factors/recovery-codes', bearer: pending);
    out['removePending'] = await post('/auth/factors/remove',
        bearer: pending, body: <String, Object?>{'code': code(fromUri)});
    out['activeAfterPendingRemove'] = await factors.hasTotp(userId);

    // --- recovery codes: shown once, stored hashed, replaced -----------
    final Map<String, Object?> first =
        await post('/auth/factors/recovery-codes', bearer: t1);
    out['codesFirst'] = first;
    final String t2 = tokenOf(first) ?? missing;
    final List<String> setA = codesOf(first);
    secrets.addAll(setA);
    out['whoamiOldAfterCodes'] = await get('/whoami', bearer: t1);
    out['statusAfterCodes'] = await get('/auth/factors', bearer: t2);
    out['rows'] = jsonEncode(await factors.store.debugRows());

    // Stale: the step-up window is three seconds.
    sleep(const Duration(seconds: 4));
    out['codesStale'] = await post('/auth/factors/recovery-codes', bearer: t2);
    final Map<String, Object?> stepUp = await post('/auth/second-factor',
        bearer: t2, body: <String, Object?>{'recoveryCode': setA[0]});
    out['stepUp'] = stepUp;
    final String t3 = tokenOf(stepUp) ?? missing;
    final Map<String, Object?> second =
        await post('/auth/factors/recovery-codes', bearer: t3);
    out['codesSecond'] = second;
    final String t4 = tokenOf(second) ?? missing;
    final List<String> setB = codesOf(second);
    secrets.addAll(setB);
    out['stepUpOldSet'] = await post('/auth/second-factor',
        bearer: t4, body: <String, Object?>{'recoveryCode': setA[1]});

    // --- removal needs a second factor in the same request -------------
    out['removeWithoutFactor'] = await post('/auth/factors/remove', bearer: t4);
    out['removeWrongCode'] = await post('/auth/factors/remove',
        bearer: t4, body: <String, Object?>{'recoveryCode': 'AAAAA-BBBBB'});
    out['activeAfterRefusedRemove'] = await factors.hasTotp(userId);
    final Map<String, Object?> removed = await post('/auth/factors/remove',
        bearer: t4, body: <String, Object?>{'recoveryCode': setB[0]});
    out['remove'] = removed;
    out['activeAfterRemove'] = await factors.hasTotp(userId);
    out['codesAfterRemove'] = await factors.remainingRecoveryCodes(userId);
    out['whoamiOldAfterRemove'] = await get('/whoami', bearer: t4);
    out['statusAfterRemove'] = await get('/auth/factors', bearer: tokenOf(removed) ?? missing);
    out['signInAfterRemove'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));

    // --- a browser gets the rotated session as a cookie -----------------
    final Map<String, Object?> grace = await post('/auth/sign-up',
        client: 'browser', body: credentials('grace@acme.test'));
    final Map<String, Object?> graceBegin = await post('/auth/factors/totp',
        client: 'browser', cookie: cookieOf(grace));
    out['graceBegin'] = graceBegin;
    final String graceSecret = (graceBegin['json']! as Map)['secret']! as String;
    secrets.add(graceSecret);
    out['graceConfirm'] = await post('/auth/factors/totp/confirm',
        client: 'browser',
        cookie: cookieOf(grace),
        body: <String, Object?>{'code': code(DVTotp.base32Decode(graceSecret))});
    out['graceCookieBefore'] = cookieOf(grace);
  } finally {
    await handle.stop();
  }
  out['secrets'] = secrets;
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
  late Map<String, Object?> r;
  late String processOutput;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_account_factors_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: account_factors_probe
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

  group('TOTP enrollment', () {
    test('needs a signed-in session and a CSRF token', () {
      expect(status('beginAnonymous'), 401, reason: '${at('beginAnonymous')}');
      expect(status('beginWithoutCsrf'), 403);
    });

    test('begin answers the secret and the otpauth URI for it, and is never '
        'cached', () {
      expect(status('begin'), 200, reason: '${at('begin')}');
      final String secret = json('begin')['secret']! as String;
      final Uri uri = Uri.parse(json('begin')['uri']! as String);
      expect(uri.scheme, 'otpauth');
      expect(uri.host, 'totp');
      expect(uri.queryParameters['secret'], secret);
      expect(uri.queryParameters['issuer'], 'Probe');
      expect(Uri.decodeComponent(uri.path), '/Probe:ada@acme.test');
      expect(at('begin')['cacheControl'], 'no-store');
    });

    test('begin activates nothing: sign-in asks for no factor and the status '
        'says none', () {
      expect(r['activeAfterBegin'], isFalse);
      expect(status('signInAfterBegin'), 200);
      expect(json('signInAfterBegin')['mfaRequired'], isFalse);
      expect(status('whoamiAfterBegin'), 200);
      expect(json('statusBefore')['totp'], isFalse);
      expect(json('statusBefore')['recoveryCodes'], 0);
    });

    test('a wrong code confirms nothing', () {
      expect(status('confirmWrong'), 400, reason: '${at('confirmWrong')}');
      expect(json('confirmWrong')['error'], 'invalid_code');
      expect(r['activeAfterWrong'], isFalse);
    });

    test('a code from the URI\'s own secret confirms it, and the session '
        'rotates with the factor recorded', () {
      expect(status('confirm'), 200, reason: '${at('confirm')}');
      expect(r['activeAfterConfirm'], isTrue);
      final Map<String, Object?> session =
          json('confirm')['session']! as Map<String, Object?>;
      expect(session['mfaSatisfiedAt'], isNotNull);
      expect(status('whoamiOldAfterConfirm'), 401);
      expect(body('whoamiNewAfterConfirm'), r['userId']);
    });

    test('after confirming, sign-in asks for the factor', () {
      expect(json('signInAfterConfirm')['mfaRequired'], isTrue);
    });

    test('a second enrollment is refused while one is active', () {
      expect(status('beginAgain'), 409, reason: '${at('beginAgain')}');
      expect(json('beginAgain')['error'], 'factor_exists');
    });

    test('a browser gets the rotated session as a cookie, not in the body', () {
      expect(status('graceConfirm'), 200, reason: '${at('graceConfirm')}');
      final String cookie = at('graceConfirm')['setCookie']! as String;
      expect(cookie, startsWith('__Host-dv_session=dvs_'));
      expect(cookie.split(';').first.trim(), isNot(r['graceCookieBefore']));
      expect(body('graceConfirm'), isNot(contains('dvs_')));
    });
  });

  group('recovery codes', () {
    test('need an active factor', () {
      expect(status('codesWithoutFactor'), 409,
          reason: '${at('codesWithoutFactor')}');
      expect(json('codesWithoutFactor')['error'], 'no_second_factor');
    });

    test('are answered once, and the session rotates', () {
      expect(status('codesFirst'), 200, reason: '${at('codesFirst')}');
      final List<Object?> codes = json('codesFirst')['recoveryCodes']! as List<Object?>;
      expect(codes, hasLength(10));
      expect(codes.toSet(), hasLength(10));
      expect(status('whoamiOldAfterCodes'), 401);
      expect(at('codesFirst')['cacheControl'], 'no-store');
    });

    test('cannot be read again: the status gives a count and no code', () {
      expect(status('statusAfterCodes'), 200);
      expect(json('statusAfterCodes')['totp'], isTrue);
      expect(json('statusAfterCodes')['recoveryCodes'], 10);
      final List<Object?> codes = json('codesFirst')['recoveryCodes']! as List<Object?>;
      for (final Object? code in codes) {
        expect(body('statusAfterCodes'), isNot(contains('$code')));
      }
    });

    test('are stored hashed, never as themselves', () {
      final String rows = r['rows']! as String;
      final List<Object?> codes = json('codesFirst')['recoveryCodes']! as List<Object?>;
      expect(rows, contains('hash'));
      for (final Object? code in codes) {
        expect(rows, isNot(contains('$code')));
        expect(rows, isNot(contains('$code'.replaceAll('-', ''))));
      }
    });

    test('need a recent second factor, and a step-up satisfies it', () {
      expect(status('codesStale'), 401, reason: '${at('codesStale')}');
      expect(at('codesStale')['www'], contains('insufficient_user_authentication'));
      expect(json('codesStale')['error'], 'mfa_required');
      expect(body('codesStale'), isNot(contains('recoveryCodes')));
      expect(status('stepUp'), 200);
      expect(status('codesSecond'), 200, reason: '${at('codesSecond')}');
    });

    test('regenerating invalidates the earlier set', () {
      expect(status('stepUpOldSet'), 400, reason: '${at('stepUpOldSet')}');
      final List<Object?> a = json('codesFirst')['recoveryCodes']! as List<Object?>;
      final List<Object?> b = json('codesSecond')['recoveryCodes']! as List<Object?>;
      expect(a.toSet().intersection(b.toSet()), isEmpty);
    });

    test('a session waiting for its own second factor can change nothing', () {
      for (final String key in <String>['codesPending', 'removePending']) {
        expect(status(key), 401, reason: '$key: ${at(key)}');
        expect(at(key)['www'], contains('insufficient_user_authentication'));
      }
      expect(r['activeAfterPendingRemove'], isTrue);
    });
  });

  group('removing a factor', () {
    test('is refused without a second factor in the same request, even from a '
        'fresh session', () {
      expect(status('removeWithoutFactor'), 400,
          reason: '${at('removeWithoutFactor')}');
      expect(status('removeWrongCode'), 400);
      expect(json('removeWrongCode')['error'], 'invalid_code');
      expect(r['activeAfterRefusedRemove'], isTrue);
    });

    test('with one, removes the authenticator and every recovery code, and '
        'rotates the session', () {
      expect(status('remove'), 200, reason: '${at('remove')}');
      expect(r['activeAfterRemove'], isFalse);
      expect(r['codesAfterRemove'], 0);
      expect(status('whoamiOldAfterRemove'), 401);
      expect(json('statusAfterRemove')['totp'], isFalse);
      expect(json('signInAfterRemove')['mfaRequired'], isFalse);
    });
  });

  test('no secret or recovery code reaches a log or the process output', () {
    final List<Object?> secrets = r['secrets']! as List<Object?>;
    expect(secrets, isNotEmpty);
    for (final Object? secret in secrets) {
      expect('${r['logs']}', isNot(contains('$secret')));
      expect(processOutput, isNot(contains('$secret')));
    }
  });
}
