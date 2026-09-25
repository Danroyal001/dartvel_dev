// Deleting an account after the grace period the project configures.
//
// "Deletion ... invokes the erasure Data Compliance and Lifecycle defines --
// after a confirmation step and a grace period the project configures." The
// deletion endpoint erased at once and nothing configured a grace period.
// This generates a backend declaring dartvel.auth.deletionGraceDays, runs it
// in a child process with DARTVEL_PRIVACY_KEY set, and moves the endpoints'
// clock through the window.
//
// The silent failures:
//  * an erasure that runs after the person signed in to cancel it -- the one
//    this whole mechanism exists to prevent;
//  * the person's sessions left working while the deletion waits;
//  * a sign-in after the window that quietly cancels a deletion already due;
//  * an erasure that never runs, or that could not reach an adapter and
//    reported the account deleted anyway.
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
const String missing = 'dvs_missing';

class RecordingAdapter implements DVPrivacyAdapter {
  bool fail = false;
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
    return <String, Object?>{'status': response.statusCode, 'body': text, 'json': json};
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
  DVAuthEndpoints.install(
    credentials: DVCredentialGuard(
      provider: provider,
      velocity: DVVelocityLimiter(
        perAccount: const DVVelocityBudget(50, Duration(minutes: 15)),
        perSource: const DVVelocityBudget(1000, Duration(minutes: 15)),
      ),
    ),
  );
  final RecordingAdapter index = RecordingAdapter();
  DVPrivacyRuntime.installAdapters(<DVPrivacyAdapter>[index]);
  final DateTime start = DateTime.now().toUtc();
  DateTime now = start;
  DVAuthEndpoints.clock = () => now;
  // The sweep's own timer would move through the window on the real clock,
  // beside the sweeps this probe runs on its own.
  final dynamic handle = await gen.startBackend(
      host: '127.0.0.1', port: 0, scheduleTick: const Duration(hours: 1));
  final int port = handle.port as int;
  out['grace'] = DVAuthEndpoints.deletionGracePeriod.inDays;
  Future<Map<String, Object?>> post(String path, {String? bearer, Map<String, Object?>? body}) =>
      call(port, 'POST', path, bearer: bearer, body: body);
  Future<Map<String, Object?>> get(String path, {String? bearer}) =>
      call(port, 'GET', path, bearer: bearer);
  Map<String, Object?> credentials(String email) =>
      <String, Object?>{'email': email, 'password': password};
  Future<String> signUp(String email) async =>
      tokenOf(await post('/auth/sign-up', body: credentials(email)));
  Future<Map<String, Object?>> delete(String token) => post('/auth/account/delete',
      bearer: token, body: <String, Object?>{'confirm': true, 'password': password});
  Future<bool> exists(String email) async {
    try {
      return (await provider.signIn(email, password)) != null;
    } on AuthException {
      return false;
    }
  }

  try {
    // --- a deletion waits, and signing in within the window cancels it -----
    final String ada = await signUp('ada@acme.test');
    out['adaId'] = (((await get('/auth/account', bearer: ada))['json']! as Map)['account']! as Map)['id'];
    final String adaPhone = tokenOf(await post('/auth/sign-in', body: credentials('ada@acme.test')));
    final Map<String, Object?> adaDeleted = await delete(ada);
    out['adaDelete'] = adaDeleted;
    out['adaSessionAfterRequest'] = await get('/auth/account', bearer: ada);
    out['adaPhoneAfterRequest'] = await get('/auth/account', bearer: adaPhone);
    out['adaExistsDuringWindow'] = await exists('ada@acme.test');
    now = start.add(const Duration(days: 3));
    out['sweepEarly'] = await DVAuthEndpoints.eraseDueDeletions();
    out['erasedEarly'] = List<String>.of(index.erased);
    final Map<String, Object?> adaBack =
        await post('/auth/sign-in', body: credentials('ada@acme.test'));
    out['adaSignInWithinWindow'] = adaBack;
    now = start.add(const Duration(days: 8));
    out['sweepAfterCancel'] = await DVAuthEndpoints.eraseDueDeletions();
    out['adaExistsAfterCancel'] = await exists('ada@acme.test');
    out['adaSessionAfterCancel'] = await get('/auth/account', bearer: tokenOf(adaBack));

    // --- a deletion nobody cancels is erased once due ----------------------
    now = start;
    final String bob = await signUp('bob@acme.test');
    out['bobId'] = (((await get('/auth/account', bearer: bob))['json']! as Map)['account']! as Map)['id'];
    out['bobDelete'] = await delete(bob);
    now = start.add(const Duration(days: 8));
    out['sweepDue'] = await DVAuthEndpoints.eraseDueDeletions();
    out['erasedDue'] = List<String>.of(index.erased);
    out['bobExistsAfterSweep'] = await exists('bob@acme.test');
    out['sweepAgain'] = await DVAuthEndpoints.eraseDueDeletions();

    // --- a sign-in after the window does not cancel ------------------------
    now = start;
    final String carol = await signUp('carol@acme.test');
    await delete(carol);
    now = start.add(const Duration(days: 8));
    out['carolSignInAfterWindow'] =
        await post('/auth/sign-in', body: credentials('carol@acme.test'));
    await DVAuthEndpoints.eraseDueDeletions();
    out['carolExistsAfterSweep'] = await exists('carol@acme.test');

    // --- a job already queued when the person cancels erases nothing -------
    now = start;
    final String dave = await signUp('dave@acme.test');
    final String daveId =
        (((await get('/auth/account', bearer: dave))['json']! as Map)['account']! as Map)['id']! as String;
    await delete(dave);
    now = start.add(const Duration(days: 7)).subtract(const Duration(minutes: 1));
    await const DVQueues().dispatch<DVAccountErasureJob>(DVAccountErasureJob(daveId),
        queue: DVAuthEndpoints.accountErasureQueue);
    out['daveCancel'] = await post('/auth/sign-in', body: credentials('dave@acme.test'));
    now = start.add(const Duration(days: 8));
    out['daveWorked'] = await const DVQueues()
        .work(queue: DVAuthEndpoints.accountErasureQueue, maxJobs: 5);
    out['daveExists'] = await exists('dave@acme.test');
    out['erasedAfterDave'] = List<String>.of(index.erased);

    // --- an erasure that cannot reach an adapter keeps the account ---------
    now = start;
    final String erin = await signUp('erin@acme.test');
    await delete(erin);
    now = start.add(const Duration(days: 8));
    index.fail = true;
    out['sweepUnreached'] = await DVAuthEndpoints.eraseDueDeletions();
    out['erinExistsAfterUnreached'] = await exists('erin@acme.test');
    index.fail = false;
    now = start.add(const Duration(days: 9));
    out['sweepRetry'] = await DVAuthEndpoints.eraseDueDeletions();
    out['erinExistsAfterRetry'] = await exists('erin@acme.test');
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

void main() {
  late Directory project;
  late Map<String, Object?> r;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_account_deletion_grace_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: account_deletion_grace_probe
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
  auth:
    deletionGraceDays: 7
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
      environment: <String, String>{
        'DARTVEL_PRIVACY_KEY': List<String>.filled(32, 'cd').join(),
      },
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
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;
  Map<String, Object?> json(String key) => at(key)['json']! as Map<String, Object?>;

  test('the generated server installs the declared grace period', () {
    expect(r['grace'], 7);
  });

  group('a deletion request', () {
    test('is accepted as scheduled, for when the window ends', () {
      expect(status('adaDelete'), 202, reason: '${at('adaDelete')}');
      expect(json('adaDelete')['scheduled'], isTrue);
      final DateTime erasesAt = DateTime.parse(json('adaDelete')['erasesAt']! as String);
      expect(erasesAt.difference(DateTime.now().toUtc()).inHours,
          inInclusiveRange(7 * 24 - 1, 7 * 24));
    });

    test('ends every one of the person\'s sessions at once, and keeps the '
        'account and its data during the window', () {
      expect(status('adaSessionAfterRequest'), 401);
      expect(status('adaPhoneAfterRequest'), 401);
      expect(r['adaExistsDuringWindow'], isTrue);
      expect(r['sweepEarly'], 0);
      expect(r['erasedEarly'], isEmpty);
    });
  });

  group('signing in', () {
    test('within the window cancels the deletion, and nothing is erased', () {
      expect(status('adaSignInWithinWindow'), 200,
          reason: '${at('adaSignInWithinWindow')}');
      expect(json('adaSignInWithinWindow')['deletionCancelled'], isTrue);
      expect(r['sweepAfterCancel'], 0);
      expect(r['adaExistsAfterCancel'], isTrue);
      expect(status('adaSessionAfterCancel'), 200);
      expect(r['erasedDue'], isNot(contains(r['adaId'])));
    });

    test('after the window is refused, and the deletion goes ahead', () {
      expect(status('carolSignInAfterWindow'), 403,
          reason: '${at('carolSignInAfterWindow')}');
      expect(json('carolSignInAfterWindow')['error'], 'account_deleted');
      expect(json('carolSignInAfterWindow'), isNot(contains('token')));
      expect(r['carolExistsAfterSweep'], isFalse);
    });

    test('before a queued erasure job runs means the job erases nothing', () {
      expect(status('daveCancel'), 200, reason: '${at('daveCancel')}');
      expect(json('daveCancel')['deletionCancelled'], isTrue);
      expect(r['daveExists'], isTrue);
      expect((r['erasedAfterDave']! as List<Object?>).length,
          (r['erasedDue']! as List<Object?>).length + 1,
          reason: 'only carol was erased since bob');
    });
  });

  group('once the window ends', () {
    test('the erasure runs through the queue, then the account goes, once',
        () {
      expect(status('bobDelete'), 202);
      expect(r['sweepDue'], 1);
      expect(r['erasedDue'], <Object?>[r['bobId']]);
      expect(r['bobExistsAfterSweep'], isFalse);
      expect(r['sweepAgain'], 0);
    });

    test('an erasure that cannot reach an adapter keeps the account, and the '
        'next sweep finishes it', () {
      expect(r['sweepUnreached'], 0);
      expect(r['erinExistsAfterUnreached'], isTrue);
      expect(r['sweepRetry'], 1);
      expect(r['erinExistsAfterRetry'], isFalse);
    });
  });
}
