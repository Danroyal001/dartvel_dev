// A deletion still scheduled when dartvel.auth.deletionGraceDays is removed.
//
// A person asked for their account to be deleted under a seven-day window and
// was told when it would be erased. The project then removed the window. The
// generated sweep only ran while a window was declared, so their deletion
// stayed scheduled for ever: the account, and the data the erasure exists to
// remove, kept by a configuration change nobody connected to them.
//
// Decided on the merits: the deletion is executed, at the erasesAt the person
// was given. Not cancelled -- nobody but the person may cancel it, by signing
// in. Not erased at once either -- the window they were promised to change
// their mind in is theirs, and it ends within the erasure's own deadline
// because the window that set it was under thirty days.
//
// This generates a backend declaring no window, schedules a deletion as an
// earlier build would have left it, and lets the generated server's own timer
// sweep -- nothing here calls eraseDueDeletions.
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

class RecordingAdapter implements DVPrivacyAdapter {
  final List<String> erased = <String>[];

  @override
  String get name => 'probe-search-index';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
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
    return <String, Object?>{'status': response.statusCode, 'json': json};
  } finally {
    http.close(force: true);
  }
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
  final dynamic handle = await gen.startBackend(
      host: '127.0.0.1', port: 0, scheduleTick: const Duration(milliseconds: 50));
  final int port = handle.port as int;
  out['grace'] = DVAuthEndpoints.deletionGracePeriod.inDays;
  Future<bool> exists(String email) async {
    try {
      return (await provider.signIn(email, password)) != null;
    } on AuthException {
      return false;
    }
  }

  Future<String> leftScheduled(String email) async {
    final Map<String, Object?> signedUp = await call(port, 'POST', '/auth/sign-up',
        body: <String, Object?>{'email': email, 'password': password});
    final String token = (signedUp['json']! as Map)['token']! as String;
    final String id = ((((await call(port, 'GET', '/auth/account', bearer: token))['json']!
        as Map)['account']!) as Map)['id']! as String;
    // What a build declaring a seven-day window left behind.
    await DVAccountDeletionStore(DVPrivacyRuntime.current.database).schedule(id,
        requestedAt: start, dueAt: start.add(const Duration(days: 7)));
    return id;
  }

  try {
    final String adaId = await leftScheduled('ada@acme.test');
    final String bobId = await leftScheduled('bob@acme.test');
    out['adaId'] = adaId;
    out['bobId'] = bobId;

    // Within the window the person was given: kept, and still theirs to
    // cancel.
    now = start.add(const Duration(days: 3));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    out['erasedWithinWindow'] = List<String>.of(index.erased);
    out['adaExistsWithinWindow'] = await exists('ada@acme.test');
    out['bobSignIn'] = await call(port, 'POST', '/auth/sign-in',
        body: <String, Object?>{'email': 'bob@acme.test', 'password': password});

    // Past it: the server's own sweep erases ada, and not bob.
    now = start.add(const Duration(days: 8));
    for (int i = 0; i < 100 && index.erased.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    out['erasedAfterWindow'] = List<String>.of(index.erased);
    out['adaExistsAfterWindow'] = await exists('ada@acme.test');
    out['bobExistsAfterWindow'] = await exists('bob@acme.test');
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
    project = Directory.systemTemp.createTempSync('dv_account_deletion_removed_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: account_deletion_removed_probe
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
  Map<String, Object?> json(String key) => at(key)['json']! as Map<String, Object?>;

  test('the generated server declares no window', () {
    expect(r['grace'], 0);
  });

  test('a deletion left scheduled is kept until the erasesAt the person was '
      'given, and signing in within it still cancels', () {
    expect(r['erasedWithinWindow'], isEmpty);
    expect(r['adaExistsWithinWindow'], isTrue);
    expect(at('bobSignIn')['status'], 200, reason: '${at('bobSignIn')}');
    expect(json('bobSignIn')['deletionCancelled'], isTrue);
  });

  test('once that time passes the server sweeps it, with no window declared',
      () {
    expect(r['erasedAfterWindow'], <Object?>[r['adaId']]);
    expect(r['adaExistsAfterWindow'], isFalse);
    expect(r['bobExistsAfterWindow'], isTrue);
  });
}
