// What the generated backend wires into the account endpoints by itself:
// verification mail through DV.Notifications.mail, and deletion through the
// DV.Privacy runtime it configures from DARTVEL_PRIVACY_KEY.
//
// DVAuthEndpoints could change an address and delete an account only when the
// application passed sendEmailVerification and a DVPrivacy to install, and
// nothing generated did. An application wiring its own auth provider got an
// address change that refused and a deletion that removed the account row and
// erased nothing, with a 200.
//
// This generates a real backend and runs it in two child processes: one with
// mail and DARTVEL_PRIVACY_KEY configured and the application passing only its
// provider, and one with neither. The silent failures:
//  * a verification code sent to the old address, or in a log, or in the
//    process output;
//  * an address change answering 202 when no mail can be sent, or a failed
//    send leaving the account showing an address that nothing was sent to;
//  * a deletion answering 200 with no erasure configured, or with an erasure
//    that could not reach one of its adapters.
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
  RecordingAdapter({this.fail = false});

  final bool fail;
  final List<String> erased = <String>[];

  @override
  String get name => 'probe-search-index';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    if (fail) throw StateError('the index is unreachable');
    erased.add('${subject.id}');
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{};
}

class FailingMail implements DVMailProvider {
  final List<String> texts = <String>[];

  @override
  Future<void> send(DVMailMessage message) async {
    texts.add(message.text);
    throw StateError('the relay refused ${message.text}');
  }
}

Future<Map<String, Object?>> call(int port, String method, String path,
    {String? bearer, Object? body}) async {
  final HttpClient http = HttpClient();
  try {
    final HttpClientRequest request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port/api$path'));
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

Map<String, Object?> mailJson(DVMailMessage m) => <String, Object?>{
      'from': m.from.email,
      'to': <String>[for (final DVMailAddress a in m.to) a.email],
      'subject': m.subject,
      'text': m.text,
      'html': m.html,
    };

Future<void> main(List<String> args) async {
  final bool wired = args.single == 'wired';
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final Map<String, Object?> out = <String, Object?>{};
  final LocalAuthProvider provider = LocalAuthProvider();
  final DVCredentialGuard credentials = DVCredentialGuard(
    provider: provider,
    velocity: DVVelocityLimiter(
      perAccount: const DVVelocityBudget(50, Duration(minutes: 15)),
      perSource: const DVVelocityBudget(1000, Duration(minutes: 15)),
    ),
  );
  // The application passes its provider and nothing else.
  DVAuthEndpoints.install(credentials: credentials);
  final DVMemoryMailProvider mail = DVMemoryMailProvider();
  if (wired) {
    const DVNotificationsService().mail.useProvider(mail);
    const DVNotificationsService().useMailSender(const DVMailAddress('accounts@bank.test'));
  }
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  out['privacyConfigured'] = DVPrivacyRuntime.isConfigured;
  Future<Map<String, Object?>> post(String path,
          {String? bearer, Map<String, Object?>? body}) =>
      call(port, 'POST', path, bearer: bearer, body: body);
  Future<Map<String, Object?>> get(String path, {String? bearer}) =>
      call(port, 'GET', path, bearer: bearer);
  Map<String, Object?> credentialsOf(String email) =>
      <String, Object?>{'email': email, 'password': password};
  final List<String> codes = <String>[];

  try {
    final Map<String, Object?> up =
        await post('/auth/sign-up', body: credentialsOf('ada@bank.test'));
    String ada = tokenOf(up);
    out['adaId'] = ((up['json']! as Map)['user']! as Map)['id'];

    if (wired) {
      // --- mail through DV.Notifications.mail, with the generated template -
      out['change'] = await post('/auth/account/email',
          bearer: ada, body: <String, Object?>{'email': 'ada@new.test'});
      out['sent'] = <Object?>[for (final DVMailMessage m in mail.sent) mailJson(m)];
      final String code = mail.sent.isEmpty
          ? '000000'
          : (RegExp(r'\b\d{6}\b').firstMatch(mail.sent.last.text)?.group(0) ??
              '000000');
      codes.add(code);
      final Map<String, Object?> verified = await post(
          '/auth/account/email/verify',
          bearer: ada,
          body: <String, Object?>{'code': code});
      out['verify'] = verified;
      ada = tokenOf(verified);

      // --- the application's own template wins over the generated one -----
      DVAuthEndpoints.install(
        credentials: credentials,
        emailVerificationMail: (DVEmailVerification v) => DVMailMessage(
          from: v.from,
          to: <DVMailAddress>[DVMailAddress(v.to)],
          subject: 'OVERRIDDEN',
          text: 'code=${v.code} valid=${v.validFor.inMinutes}',
        ),
      );
      out['changeOverridden'] = await post('/auth/account/email',
          bearer: ada, body: <String, Object?>{'email': 'ada@third.test'});
      out['sentOverridden'] = mail.sent.isEmpty ? <String, Object?>{} : mailJson(mail.sent.last);
      if (mail.sent.isNotEmpty) {
        codes.add(RegExp(r'code=(\d{6})').firstMatch(mail.sent.last.text)?.group(1) ?? '');
      }

      // --- a send that fails leaves nothing pending ------------------------
      final FailingMail failing = FailingMail();
      const DVNotificationsService().mail.useProvider(failing);
      out['changeSendFails'] = await post('/auth/account/email',
          bearer: ada, body: <String, Object?>{'email': 'ada@fourth.test'});
      out['accountAfterSendFails'] = await get('/auth/account', bearer: ada);
      const DVNotificationsService().mail.useProvider(mail);
      for (final String text in failing.texts) {
        codes.add(RegExp(r'\b\d{6}\b').firstMatch(text)?.group(0) ?? '');
      }

      // --- deletion through the configured DV.Privacy ----------------------
      DVPrivacyRuntime.installAdapters(<DVPrivacyAdapter>[RecordingAdapter(fail: true)]);
      out['deleteUnreached'] = await post('/auth/account/delete',
          bearer: ada,
          body: <String, Object?>{'confirm': true, 'password': password});
      out['sessionAfterUnreached'] = await get('/auth/account', bearer: ada);
      out['signInAfterUnreached'] =
          await post('/auth/sign-in', body: credentialsOf('ada@new.test'));
      final RecordingAdapter index = RecordingAdapter();
      DVPrivacyRuntime.installAdapters(<DVPrivacyAdapter>[index]);
      out['delete'] = await post('/auth/account/delete',
          bearer: ada,
          body: <String, Object?>{'confirm': true, 'password': password});
      out['erased'] = List<String>.of(index.erased);
      out['signInAfterDelete'] =
          await post('/auth/sign-in', body: credentialsOf('ada@new.test'));
    } else {
      // --- a sender and no mail provider ------------------------------------
      const DVNotificationsService().useMailSender(const DVMailAddress('accounts@bank.test'));
      out['changeNoMail'] = await post('/auth/account/email',
          bearer: ada, body: <String, Object?>{'email': 'ada@new.test'});
      // --- a provider and no sender ----------------------------------------
      const DVNotificationsService().resetRouting();
      const DVNotificationsService().mail.useProvider(mail);
      out['changeNoSender'] = await post('/auth/account/email',
          bearer: ada, body: <String, Object?>{'email': 'ada@new.test'});
      out['sentUnwired'] = mail.sent.length;
      out['accountUnwired'] = await get('/auth/account', bearer: ada);

      // --- deletion with no DV.Privacy -------------------------------------
      out['deleteNoPrivacy'] = await post('/auth/account/delete',
          bearer: ada,
          body: <String, Object?>{'confirm': true, 'password': password});
      out['sessionAfterRefusal'] = await get('/auth/account', bearer: ada);
      out['signInAfterRefusal'] =
          await post('/auth/sign-in', body: credentialsOf('ada@bank.test'));
    }
  } finally {
    await handle.stop();
  }
  out['codes'] = codes;
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

class _Run {
  _Run(this.r, this.output);

  final Map<String, Object?> r;
  final String output;

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;
  String body(String key) => at(key)['body']! as String;
  Map<String, Object?> json(String key) => at(key)['json']! as Map<String, Object?>;
}

Future<_Run> _runProbe(Directory project, String mode, Map<String, String> env) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'bin/probe.dart', mode],
    workingDirectory: project.path,
    environment: env,
  ).timeout(const Duration(minutes: 4));
  final String output = '${result.stdout}\n${result.stderr}';
  final String? line = const LineSplitter()
      .convert('${result.stdout}')
      .where((String l) => l.startsWith('PROBE '))
      .firstOrNull;
  if (result.exitCode != 0 || line == null) {
    fail('the $mode probe did not run (exit ${result.exitCode}):\n$output');
  }
  return _Run(jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>,
      output.replaceFirst(line, ''));
}

void main() {
  late Directory project;
  late _Run wired;
  late _Run unwired;

  setUpAll(() async {
    expect(Platform.environment['DARTVEL_PRIVACY_KEY'], isNull,
        reason: 'the unwired probe needs a process without a privacy key');
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_account_wiring_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: account_wiring_probe
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
  seo:
    siteName: Probe Bank
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
    wired = await _runProbe(project, 'wired', <String, String>{
      'DARTVEL_PRIVACY_KEY': List<String>.filled(32, 'ab').join(),
    });
    unwired = await _runProbe(project, 'unwired', const <String, String>{});
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  group('with mail configured', () {
    test('an address change sends the generated template, from the '
        'configured sender, to the new address only', () {
      expect(wired.status('change'), 202, reason: '${wired.at('change')}');
      final List<Object?> sent = wired.r['sent']! as List<Object?>;
      expect(sent, hasLength(1));
      final Map<String, Object?> mail = sent.single! as Map<String, Object?>;
      expect(mail['to'], <Object?>['ada@new.test']);
      expect(mail['from'], 'accounts@bank.test');
      expect(mail['subject'], contains('Probe Bank'));
      final String code = (wired.r['codes']! as List<Object?>).first! as String;
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(mail['text'], contains(code));
      expect(mail['subject'], isNot(contains(code)));
      expect(wired.body('change'), isNot(contains(code)));
    });

    test('the code in the mail changes the address', () {
      expect(wired.status('verify'), 200, reason: '${wired.at('verify')}');
      expect((wired.json('verify')['account']! as Map)['email'], 'ada@new.test');
    });

    test('the application\'s own template wins over the generated one', () {
      expect(wired.status('changeOverridden'), 202,
          reason: '${wired.at('changeOverridden')}');
      final Map<String, Object?> mail =
          wired.r['sentOverridden']! as Map<String, Object?>;
      expect(mail['subject'], 'OVERRIDDEN');
      expect(mail['to'], <Object?>['ada@third.test']);
      expect(mail['text'], matches(RegExp(r'^code=\d{6} valid=30$')));
    });

    test('a send that fails is refused and leaves no pending address', () {
      expect(wired.status('changeSendFails'), 503,
          reason: '${wired.at('changeSendFails')}');
      final Map<String, Object?> account =
          wired.json('accountAfterSendFails')['account']! as Map<String, Object?>;
      expect(account, isNot(contains('pendingEmail')));
    });
  });

  group('with DV.Privacy configured from DARTVEL_PRIVACY_KEY', () {
    test('deletion that cannot reach an adapter is refused with the account '
        'and its session intact', () {
      expect(wired.r['privacyConfigured'], isTrue);
      expect(wired.status('deleteUnreached'), 503,
          reason: '${wired.at('deleteUnreached')}');
      expect(wired.json('deleteUnreached')['error'], 'erasure_incomplete');
      expect(wired.body('deleteUnreached'), contains('probe-search-index'));
      expect(wired.status('sessionAfterUnreached'), 200);
      expect(wired.status('signInAfterUnreached'), 200);
    });

    test('deletion runs the configured erasure, then removes the account', () {
      expect(wired.status('delete'), 200, reason: '${wired.at('delete')}');
      expect((wired.json('delete')['erasure']! as Map)['complete'], isTrue);
      expect(wired.r['erased'], <Object?>[wired.r['adaId']]);
      expect(wired.status('signInAfterDelete'), 400);
    });
  });

  group('with neither configured', () {
    test('an address change is refused naming what to configure, and nothing '
        'is pending or sent', () {
      expect(unwired.status('changeNoMail'), 503,
          reason: '${unwired.at('changeNoMail')}');
      expect(unwired.json('changeNoMail')['error'], 'mail_not_configured');
      expect(unwired.json('changeNoMail')['message'],
          contains('DV.Notifications.mail.useProvider'));
      expect(unwired.status('changeNoSender'), 503,
          reason: '${unwired.at('changeNoSender')}');
      expect(unwired.json('changeNoSender')['error'], 'mail_not_configured');
      expect(unwired.json('changeNoSender')['message'], contains('useMailSender'));
      expect(unwired.r['sentUnwired'], 0);
      final Map<String, Object?> account =
          unwired.json('accountUnwired')['account']! as Map<String, Object?>;
      expect(account['email'], 'ada@bank.test');
      expect(account, isNot(contains('pendingEmail')));
    });

    test('deletion is refused naming DARTVEL_PRIVACY_KEY, and the account and '
        'its session are intact', () {
      expect(unwired.r['privacyConfigured'], isFalse);
      expect(unwired.status('deleteNoPrivacy'), 503,
          reason: '${unwired.at('deleteNoPrivacy')}');
      expect(unwired.json('deleteNoPrivacy')['error'], 'erasure_not_configured');
      expect(unwired.json('deleteNoPrivacy')['message'],
          contains('DARTVEL_PRIVACY_KEY'));
      expect(unwired.status('sessionAfterRefusal'), 200);
      expect(unwired.status('signInAfterRefusal'), 200);
    });
  });

  test('no verification code reaches a log or the process output', () {
    for (final Object? code in wired.r['codes']! as List<Object?>) {
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect('${wired.r['logs']}', isNot(contains('$code')));
      expect(wired.output, isNot(contains('$code')));
    }
  });
}
