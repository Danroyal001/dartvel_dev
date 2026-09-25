// Preview Environments, as a generated backend actually runs.
//
// The preview runtime -- capture, access, schedules -- was built and tested
// in isolation, and nothing on a server called any of it: a process deployed
// with DARTVEL_ENVIRONMENT=preview started exactly as production does, mailed
// real people, answered crawlers, reserved production's queue and had no idea
// which database was its own.
//
// So this generates a real backend the way `dartvel routes` does, starts it as
// a process under the environment a preview deployment writes, and asserts on
// what the process did: whether a provider was handed mail, which queue a job
// landed in, which database it would query, what went over the wire. Each
// silent failure is paired with its production control, because middleware
// installed everywhere passes every preview assertion.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_core/dartvel.dart'
    show DVPreviewDeployment, DVPreviewIdentity, DVPreviewVisibility;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

class RecordingMail implements DVMailProvider {
  int sent = 0;
  @override
  Future<void> send(DVMailMessage message) async => sent++;
}

Future<void> main() async {
  final RecordingMail mail = RecordingMail();
  const DVNotificationMail().useProvider(mail);
  const DVQueues().useAdapter(DVInMemoryQueueAdapter());

  // Before the backend starts: the earliest an application's own code can
  // send anything. A preview has to have captured it anyway.
  await const DVNotificationMail().send(const DVMailMessage(
    from: DVMailAddress('shop@example.com'),
    to: <DVMailAddress>[DVMailAddress('ada@example.com')],
    subject: 'Welcome',
    text: 'Hello',
  ));

  final handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  // And after it has, when the runtime writes its log to stdout: the capture
  // has to be reported where an operator reads it.
  await const DVNotificationMail().send(const DVMailMessage(
    from: DVMailAddress('shop@example.com'),
    to: <DVMailAddress>[DVMailAddress('grace@example.com')],
    subject: 'Receipt',
    text: 'Thanks',
  ));
  final job = await const DVQueues().dispatch<String>('job');

  String? database;
  try {
    final DVDatabaseAdapter adapter = const DVDatabase().adapter;
    database = adapter is DVPostgresDatabaseAdapter
        ? adapter.database
        : adapter.runtimeType.toString();
  } on StateError {
    database = null;
  }

  Future<Map<String, Object?>> get(String path) async {
    final HttpClient client = HttpClient();
    try {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:${handle.port}$path'));
      request.followRedirects = false;
      final response = await request.close();
      return <String, Object?>{
        'status': response.statusCode,
        'robots': response.headers.value('x-robots-tag'),
        'cookie': response.headers.value('set-cookie'),
        'body': await response.transform(utf8.decoder).join(),
      };
    } finally {
      client.close(force: true);
    }
  }

  final String token = io.Platform.environment['PROBE_TOKEN'] ?? '';
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'mailSent': mail.sent,
    'queue': job.queue,
    'database': database,
    'ping': await get('/api/ping'),
    'robotsTxt': await get('/robots.txt'),
    'withToken': await get('/api/ping?dv_preview=$token'),
  })}');
  await handle.stop();
  exit(0);
}
''';

final DVPreviewIdentity id = DVPreviewIdentity.forBranch(
  app: 'shop',
  branch: 'feature/cart',
);

Map<String, String> previewVariables(
  DVPreviewVisibility visibility, {
  String? linkToken,
  String productionDatabase = 'shop',
}) => DVPreviewDeployment(
  identity: id,
  visibility: visibility,
  secrets: const <String, String>{
    'DATABASE_URL': 'postgres://app:pw@db.internal:5432/shop',
  },
  linkDigest: linkToken == null
      ? null
      : sha256.convert(utf8.encode(linkToken)).toString(),
  productionOrigin: 'https://shop.example',
  productionDatabase: productionDatabase,
).variables;

void main() {
  late Directory project;

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );

    project = Directory.systemTemp.createTempSync('dv_preview_backend_');
    void write(String relative, String content) {
      final File file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: preview_backend_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    // dartvel_shelf asks for dartvel_core from hosted; the path has to win.
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

    await routes.generate(root_: project.path);

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

  Future<ProcessResult> run(Map<String, String> environment) {
    final Map<String, String> inherited = <String, String>{
      for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
        if (Platform.environment[key] != null) key: Platform.environment[key]!,
    };
    return Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      // Nothing of the runner's own: a DARTVEL_ENVIRONMENT exported in the
      // shell that runs the suite would decide the answer.
      includeParentEnvironment: false,
      environment: <String, String>{...inherited, ...environment},
    ).timeout(const Duration(minutes: 3));
  }

  Map<String, Object?> report(ProcessResult result) {
    final String out = '${result.stdout}';
    final String? line = const LineSplitter()
        .convert(out)
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail(
        'the probe did not run (exit ${result.exitCode}):\n$out\n'
        '${result.stderr}',
      );
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  void expectRefused(ProcessResult result, String because) {
    expect(
      result.exitCode,
      isNot(0),
      reason:
          'a preview that cannot be what it says must not start:\n'
          '${result.stdout}',
    );
    expect('${result.stdout}', isNot(contains('PROBE ')));
    expect('${result.stdout}${result.stderr}', contains(because));
  }

  test('outside a preview the generated backend installs nothing', () async {
    // Every preview variable left in place and only the environment name
    // changed, which is what a production deploy copied from a preview's
    // settings looks like. None of it may take effect.
    final Map<String, Object?> probe = report(
      await run(<String, String>{
        ...previewVariables(DVPreviewVisibility.link, linkToken: 't'),
        'DARTVEL_ENVIRONMENT': 'production',
      }),
    );

    expect(probe['mailSent'], 2, reason: 'production mail is sent');
    expect(probe['queue'], 'default');
    // DATABASE_URL's own database, untouched by the preview wiring. The
    // generated backend makes DATABASE_URL DV.Database when the application
    // configured none, so a backend function can query it; what must not
    // happen outside a preview is the switch to the preview's database.
    expect(
      probe['database'],
      'shop',
      reason: 'production runs on the database DATABASE_URL names',
    );
    expect(probe['database'], isNot(id.database));
    final Map<String, Object?> ping = probe['ping']! as Map<String, Object?>;
    expect(ping['status'], 200);
    expect(ping['robots'], isNull);
    expect(
      (probe['robotsTxt']! as Map<String, Object?>)['body'],
      isNot(contains('Disallow')),
    );
  });

  test('a preview captures mail sent before it started, namespaces its queue, '
      'uses its own database and is not indexed', () async {
    final ProcessResult result = await run(
      previewVariables(DVPreviewVisibility.public),
    );
    final Map<String, Object?> probe = report(result);

    expect(
      probe['mailSent'],
      0,
      reason:
          'no provider may be handed mail in a preview, even before the '
          'backend has started',
    );
    // From the mail sent after startup. The one sent before is captured too
    // (mailSent is 0), but the runtime writes no log line to stdout until
    // serve() configures logging, so its report stays in the log buffer.
    expect('${result.stdout}', contains('DV-PREVIEW-006'));
    expect(probe['queue'], '${id.queueNamespace}.default');
    expect(
      probe['database'],
      id.database,
      reason:
          'DATABASE_URL names production\'s database; the preview must '
          'resolve its own',
    );
    final Map<String, Object?> ping = probe['ping']! as Map<String, Object?>;
    expect(ping['status'], 200);
    expect(ping['robots'], contains('noindex'));
    expect(
      (probe['robotsTxt']! as Map<String, Object?>)['body'],
      contains('Disallow: /'),
    );
  });

  test('a link preview answers only the holder of its link', () async {
    final Map<String, Object?> probe = report(
      await run(<String, String>{
        ...previewVariables(DVPreviewVisibility.link, linkToken: 'tok3n'),
        'PROBE_TOKEN': 'tok3n',
      }),
    );

    final Map<String, Object?> ping = probe['ping']! as Map<String, Object?>;
    expect(ping['status'], 404);
    expect(ping['robots'], contains('noindex'));
    final Map<String, Object?> withToken =
        probe['withToken']! as Map<String, Object?>;
    expect(withToken['status'], inInclusiveRange(300, 399));
    expect(withToken['cookie'], contains('HttpOnly'));
  });

  test('a preview that cannot read its identity refuses to start', () async {
    expectRefused(
      await run(const <String, String>{'DARTVEL_ENVIRONMENT': 'preview'}),
      'DARTVEL_PREVIEW',
    );
  });

  test('a preview whose database is production\'s refuses to start', () async {
    // Production's database carrying this preview's own name is the case no
    // naming rule catches -- only the comparison does.
    expectRefused(
      await run(
        previewVariables(
          DVPreviewVisibility.public,
          productionDatabase: id.database,
        ),
      ),
      'production',
    );
  });

  test(
    'a preview on a queue namespace other than its own refuses to start',
    () async {
      expectRefused(
        await run(<String, String>{
          ...previewVariables(DVPreviewVisibility.public),
          'DARTVEL_QUEUE_NAMESPACE': 'default',
        }),
        'DARTVEL_QUEUE_NAMESPACE',
      );
    },
  );

  test('a members preview with no membership check refuses to start', () async {
    expectRefused(
      await run(previewVariables(DVPreviewVisibility.members)),
      'membership',
    );
  });
}
