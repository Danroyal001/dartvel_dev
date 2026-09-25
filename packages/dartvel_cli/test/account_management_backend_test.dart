// Changing the account's e-mail address and deleting the account, through
// the generated backend's own endpoints.
//
// An account page needs both and nothing generated served either: an
// application wrote them, and each mistake available there still answers 200.
// This generates a real backend, starts it in a child process and drives both
// over HTTP, asserting on what the server answered and on what the provider
// and the erasure were asked to do.
//
// The silent failures:
//  * an e-mail change that takes effect before the new address proves it can
//    receive mail -- an account takeover with a password reset attached;
//  * the verification code sent to the old address, or readable anywhere;
//  * a change request whose answer says whether the address belongs to
//    somebody else;
//  * a deletion that proceeds without the password, without the second
//    factor on an account that has one, or without explicit confirmation;
//  * a deletion that removes the account row and leaves its sessions working,
//    or never reaches the Data Compliance erasure the project configured.
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
const String missing = 'dvs_missing';

class RecordingAdapter implements DVPrivacyAdapter {
  final List<String> erased = <String>[];

  @override
  String get name => 'probe-search-index';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async =>
      erased.add('${subject.id}');

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{};
}

Future<Map<String, Object?>> call(int port, String method, String path,
    {String? bearer, bool csrf = true, Object? body}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port/api$path'));
    request.headers.set('x-tenant', 'acme');
    request.headers.set('x-forwarded-for', '203.0.113.11');
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
      'cacheControl': response.headers.value('cache-control'),
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
  final List<List<String>> mail = <List<String>>[];
  final RecordingAdapter index = RecordingAdapter();
  final LocalAuthProvider provider = LocalAuthProvider();
  final DVSecondFactors factors = DVSecondFactors(
    cipher: DVFieldCipher.secure(
        DVFieldKeyring.parse('k1:${base64Encode(List<int>.filled(32, 3))}')),
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
    sendEmailVerification: (String email, String code) async =>
        mail.add(<String>[email, code]),
    privacy: DVPrivacy(
      models: const <DVPrivacyModel>[],
      database: MemoryDVDatabaseAdapter(),
      signingKey: List<int>.filled(32, 8),
      adapters: <DVPrivacyAdapter>[index],
    ),
  );
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  Future<Map<String, Object?>> post(String path,
          {String? bearer, bool csrf = true, Map<String, Object?>? body}) =>
      call(port, 'POST', path, bearer: bearer, csrf: csrf, body: body);
  Future<Map<String, Object?>> get(String path, {String? bearer}) =>
      call(port, 'GET', path, bearer: bearer);
  Map<String, Object?> credentials(String email) =>
      <String, Object?>{'email': email, 'password': password};

  try {
    final Map<String, Object?> up =
        await post('/auth/sign-up', body: credentials('ada@acme.test'));
    final String ada = tokenOf(up);
    out['adaId'] = ((up['json']! as Map)['user']! as Map)['id'];
    await post('/auth/sign-up', body: credentials('grace@acme.test'));

    out['account'] = await get('/auth/account', bearer: ada);
    out['accountAnonymous'] = await get('/auth/account');

    // --- an e-mail change waits for the new address -----------------------
    out['changeWithoutCsrf'] = await post('/auth/account/email',
        bearer: ada, csrf: false, body: <String, Object?>{'email': 'ada@new.test'});
    out['changeAnonymous'] =
        await post('/auth/account/email', body: <String, Object?>{'email': 'ada@new.test'});
    out['changeInvalid'] = await post('/auth/account/email',
        bearer: ada, body: <String, Object?>{'email': 'not an address'});
    out['change'] = await post('/auth/account/email',
        bearer: ada, body: <String, Object?>{'email': 'ada@new.test'});
    out['mailAfterChange'] = List<List<String>>.of(mail);
    out['accountPending'] = await get('/auth/account', bearer: ada);
    out['signInNewBeforeVerify'] =
        await post('/auth/sign-in', body: credentials('ada@new.test'));
    out['signInOldBeforeVerify'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    final String code = mail.isEmpty ? '000000' : mail.last[1];
    final String wrong = code == '999999' ? '999998' : '999999';
    out['verifyWrong'] = await post('/auth/account/email/verify',
        bearer: ada, body: <String, Object?>{'code': wrong});
    out['accountAfterWrong'] = await get('/auth/account', bearer: ada);
    final Map<String, Object?> verified = await post('/auth/account/email/verify',
        bearer: ada, body: <String, Object?>{'code': code});
    out['verify'] = verified;
    final String adaRotated = tokenOf(verified);
    out['whoamiOldAfterVerify'] = await get('/auth/account', bearer: ada);
    out['accountAfterVerify'] = await get('/auth/account', bearer: adaRotated);
    out['signInNewAfterVerify'] =
        await post('/auth/sign-in', body: credentials('ada@new.test'));
    out['signInOldAfterVerify'] =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    out['verifyReplay'] = await post('/auth/account/email/verify',
        bearer: adaRotated, body: <String, Object?>{'code': code});

    // A taken address: the request answers exactly as for a free one.
    out['changeFree'] = await post('/auth/account/email',
        bearer: adaRotated, body: <String, Object?>{'email': 'ada@free.test'});
    out['changeTaken'] = await post('/auth/account/email',
        bearer: adaRotated, body: <String, Object?>{'email': 'grace@acme.test'});
    final String takenCode = mail.last[1];
    out['verifyTaken'] = await post('/auth/account/email/verify',
        bearer: adaRotated, body: <String, Object?>{'code': takenCode});
    out['graceStillSignsIn'] =
        await post('/auth/sign-in', body: credentials('grace@acme.test'));

    // --- deletion ----------------------------------------------------------
    final Map<String, Object?> second =
        await post('/auth/sign-in', body: credentials('ada@new.test'));
    final String adaOther = tokenOf(second);
    out['deleteUnconfirmed'] = await post('/auth/account/delete',
        bearer: adaRotated, body: <String, Object?>{'password': password});
    out['deleteNoPassword'] = await post('/auth/account/delete',
        bearer: adaRotated, body: <String, Object?>{'confirm': true});
    out['deleteWrongPassword'] = await post('/auth/account/delete',
        bearer: adaRotated,
        body: <String, Object?>{'confirm': true, 'password': 'not the password'});
    out['deleteWithoutCsrf'] = await post('/auth/account/delete',
        bearer: adaRotated,
        csrf: false,
        body: <String, Object?>{'confirm': true, 'password': password});
    out['existsAfterRefusals'] =
        await post('/auth/sign-in', body: credentials('ada@new.test'));
    out['erasedAfterRefusals'] = List<String>.of(index.erased);
    final Map<String, Object?> deleted = await post('/auth/account/delete',
        bearer: adaRotated,
        body: <String, Object?>{'confirm': true, 'password': password});
    out['delete'] = deleted;
    out['erased'] = List<String>.of(index.erased);
    out['signInAfterDelete'] =
        await post('/auth/sign-in', body: credentials('ada@new.test'));
    out['sessionAfterDelete'] = await get('/auth/account', bearer: adaRotated);
    out['otherSessionAfterDelete'] = await get('/auth/account', bearer: adaOther);

    // An account with a second factor also needs it to delete.
    final AuthUser carol = (await provider.signUp('carol@acme.test', password))!;
    final DVTotpEnrollment enrollment =
        await factors.beginTotp(carol.id, account: 'carol@acme.test');
    await factors.confirmTotp(
        carol.id,
        const DVTotp().generate(DVTotp.base32Decode(enrollment.secret),
            at: DateTime.now().subtract(const Duration(seconds: 30))));
    final List<String> codes = (await factors.regenerateRecoveryCodes(carol.id)).codes;
    final Map<String, Object?> carolIn =
        await post('/auth/sign-in', body: credentials('carol@acme.test'));
    final String carolSession = tokenOf(await post('/auth/second-factor',
        bearer: tokenOf(carolIn), body: <String, Object?>{'recoveryCode': codes[0]}));
    out['deleteWithoutFactor'] = await post('/auth/account/delete',
        bearer: carolSession,
        body: <String, Object?>{'confirm': true, 'password': password});
    out['carolExistsAfterRefusal'] = await provider.userById(carol.id) != null;
    out['deleteWithFactor'] = await post('/auth/account/delete',
        bearer: carolSession,
        body: <String, Object?>{
          'confirm': true,
          'password': password,
          'recoveryCode': codes[1],
        });
    out['carolExistsAfterDelete'] = await provider.userById(carol.id) != null;
    out['carolFactorAfterDelete'] = await factors.hasTotp(carol.id);
    out['carolId'] = carol.id;
    out['erasedFinal'] = List<String>.of(index.erased);
  } finally {
    await handle.stop();
  }
  out['mail'] = mail;
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
    project = Directory.systemTemp.createTempSync('dv_account_management_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: account_management_probe
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
  Map<String, Object?> account(String key) =>
      json(key)['account']! as Map<String, Object?>;

  group('the account', () {
    test('is the signed-in person\'s, and nobody else gets one', () {
      expect(status('account'), 200, reason: '${at('account')}');
      expect(account('account')['email'], 'ada@acme.test');
      expect(account('account')['id'], r['adaId']);
      expect(status('accountAnonymous'), 401);
      expect(at('account')['cacheControl'], 'no-store');
    });
  });

  group('changing the e-mail address', () {
    test('needs a session and a CSRF token, and a real address', () {
      expect(status('changeWithoutCsrf'), 403);
      expect(status('changeAnonymous'), 401);
      expect(status('changeInvalid'), 400, reason: '${at('changeInvalid')}');
    });

    test('sends a code to the new address only, and never answers it', () {
      expect(status('change'), 202, reason: '${at('change')}');
      final List<Object?> sent = r['mailAfterChange']! as List<Object?>;
      expect(sent, hasLength(1));
      expect((sent.single! as List<Object?>)[0], 'ada@new.test');
      final String code = (sent.single! as List<Object?>)[1]! as String;
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(body('change'), isNot(contains(code)));
    });

    test('changes nothing until the new address is verified', () {
      expect(account('accountPending')['email'], 'ada@acme.test');
      expect(account('accountPending')['pendingEmail'], 'ada@new.test');
      expect(status('signInNewBeforeVerify'), 400);
      expect(status('signInOldBeforeVerify'), 200);
      expect(status('verifyWrong'), 400, reason: '${at('verifyWrong')}');
      expect(json('verifyWrong')['error'], 'invalid_code');
      expect(account('accountAfterWrong')['email'], 'ada@acme.test');
    });

    test('takes effect with the code, rotating the session', () {
      expect(status('verify'), 200, reason: '${at('verify')}');
      expect(account('verify')['email'], 'ada@new.test');
      expect(status('whoamiOldAfterVerify'), 401);
      expect(account('accountAfterVerify')['email'], 'ada@new.test');
      expect(account('accountAfterVerify'), isNot(contains('pendingEmail')));
      expect(status('signInNewAfterVerify'), 200);
      expect(status('signInOldAfterVerify'), 400);
    });

    test('a code works once', () {
      expect(status('verifyReplay'), 400, reason: '${at('verifyReplay')}');
    });

    test('a request for an address somebody else has answers exactly as for '
        'a free one', () {
      expect(status('changeTaken'), status('changeFree'));
      expect(body('changeTaken').replaceAll('grace@acme.test', 'X'),
          body('changeFree').replaceAll('ada@free.test', 'X'));
    });

    test('verifying an address somebody else has changes neither account', () {
      expect(status('verifyTaken'), 409, reason: '${at('verifyTaken')}');
      expect(status('graceStillSignsIn'), 200);
    });
  });

  group('deleting the account', () {
    test('is refused without explicit confirmation, the password or CSRF, and '
        'nothing is erased', () {
      expect(status('deleteUnconfirmed'), 400, reason: '${at('deleteUnconfirmed')}');
      expect(json('deleteUnconfirmed')['error'], 'confirmation_required');
      expect(status('deleteNoPassword'), 400);
      expect(status('deleteWrongPassword'), 400);
      expect(json('deleteWrongPassword')['error'], 'invalid_credentials');
      expect(status('deleteWithoutCsrf'), 403);
      expect(status('existsAfterRefusals'), 200);
      expect(r['erasedAfterRefusals'], isEmpty);
    });

    test('with them, hands the person to the configured erasure, deletes the '
        'account and ends every session', () {
      expect(status('delete'), 200, reason: '${at('delete')}');
      expect(json('delete')['deleted'], isTrue);
      final Map<String, Object?> erasure =
          json('delete')['erasure']! as Map<String, Object?>;
      expect(erasure['complete'], isTrue);
      expect(r['erased'], <Object?>[r['adaId']]);
      expect(status('signInAfterDelete'), 400);
      expect(status('sessionAfterDelete'), 401);
      expect(status('otherSessionAfterDelete'), 401);
    });

    test('an account with a second factor needs it too', () {
      expect(status('deleteWithoutFactor'), 401, reason: '${at('deleteWithoutFactor')}');
      expect(at('deleteWithoutFactor')['www'], contains('insufficient_user_authentication'));
      expect(r['carolExistsAfterRefusal'], isTrue);
      expect(status('deleteWithFactor'), 200, reason: '${at('deleteWithFactor')}');
      expect(r['carolExistsAfterDelete'], isFalse);
      expect(r['carolFactorAfterDelete'], isFalse);
      expect(r['erasedFinal'], contains(r['carolId']));
    });
  });

  test('no verification code reaches a log or the process output', () {
    for (final Object? sent in r['mail']! as List<Object?>) {
      final String code = (sent! as List<Object?>)[1]! as String;
      expect('${r['logs']}', isNot(contains('code $code')));
      expect(processOutput, isNot(contains(code)));
    }
  });
}
