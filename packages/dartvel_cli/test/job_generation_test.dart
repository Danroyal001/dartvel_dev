import 'dart:io';

import 'package:dartvel_cli/src/generators/job_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes [source] as `lib/jobs/jobs.dart` and returns the generated
/// `jobs.g.dart`.
Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_job_test_');
  try {
    Directory(p.join(root.path, 'lib', 'jobs')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'jobs', 'jobs.dart'))
        .writeAsStringSync(source);

    await JobGenerator.generate(
      root: root.path,
      pkgName: 'job_app',
      buildId: 'test-build',
    );

    return File(
      p.join(root.path, 'lib', 'dartvel_client', 'jobs.g.dart'),
    ).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('a @DVJob class generates a payload, constants and dispatch', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class _SendWelcomeEmail {
  final String userId;

  const _SendWelcomeEmail({required this.userId});
}
''');

    expect(
      generated,
      contains(
        'class const SendWelcomeEmail({required final String userId}) {',
      ),
    );
    expect(generated, isNot(contains('required this.userId')));
    // Settings declared on the annotation, which DV.Jobs.dispatch cannot know.
    expect(generated, contains("static const String queue = 'mail';"));
    expect(generated, contains('static const int maxAttempts = 5;'));
    expect(
      generated,
      contains('static const Duration backoff = Duration(seconds: 60);'),
    );
    expect(generated, contains('Future<DVJobEnvelope<SendWelcomeEmail>> '
        'dispatch({'));

    // Named queues become generated constants.
    expect(generated, contains("static const String mail = 'mail';"));
    expect(generated, contains("static const String defaultQueue = 'default';"));

    // A durable queue cannot round-trip a payload without a codec.
    expect(generated, contains('codecs.register<SendWelcomeEmail>('));
    expect(generated, contains('decode: SendWelcomeEmail.fromJson,'));
  });

  test('a handler is lowered to a public function and registered', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail')
class _SendWelcomeEmail {
  final String userId;

  const _SendWelcomeEmail({required this.userId});
}

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    sendWelcome(job.userId);
''');

    expect(
      generated,
      contains('Future<void> handleSendWelcomeEmail(\n'
          '  SendWelcomeEmail job,\n'
          ') async => sendWelcome(job.userId);'),
    );
    expect(
      generated,
      contains('queues.register<SendWelcomeEmail>(handleSendWelcomeEmail);'),
    );
  });

  test('a public job input is rejected with a rename message', () async {
    // Same rule as models and pages: annotated inputs are private.
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob()
class SendWelcomeEmail {
  final String userId;

  const SendWelcomeEmail({required this.userId});
}
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('_SendWelcomeEmail'),
        ),
      ),
    );
  });

  test('a handler for a job that does not exist fails at generation',
      () async {
    // Otherwise it fails at runtime, when the job is already in the queue.
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob.handler()
Future<void> _handleGhost(GhostJob job) async => run(job);
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('no @DVJob class generates'),
        ),
      ),
    );
  });

  test('two handlers for one job fail rather than one silently winning',
      () async {
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob()
class _Ping {
  final String id;

  const _Ping({required this.id});
}

@DVJob.handler()
Future<void> _handleA(Ping job) async => a(job);

@DVJob.handler()
Future<void> _handleB(Ping job) async => b(job);
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('more than one @DVJob.handler()'),
        ),
      ),
    );
  });

  test('a block-bodied handler is lowered into the generated handler', () async {
    // This used to assert the generator named the restriction it hit. The
    // restriction is gone; a job handler is exactly where branching and
    // several awaits belong, so it asserts the lowering instead.
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

@DVJob()
class _Ping {
  final String id;

  const _Ping({required this.id});
}

@DVJob.handler()
Future<void> _handlePing(Ping job) async {
  await run(job);
}

Future<void> run(Ping job) async {}
''');

    expect(generated, contains('await j0.run(job);'));
    expect(generated, isNot(contains('_handlePing(')));
  });

  test('a project with no jobs still generates a usable file', () async {
    final generated = await generate('''
import 'package:dartvel_core/dartvel.dart';

const int unrelated = 1;
''');

    // The barrel exports this file unconditionally, so it has to compile and
    // registerDartvelJobs() has to exist for the runtime to call.
    expect(generated, contains('void registerDartvelJobs()'));
    expect(generated, contains("static const String defaultQueue = 'default';"));
  });

  // jobs.g.dart is what the generated backend imports, and a server process
  // has no dart:ui: one Flutter import reachable from it and the worker, the
  // web server and the cron process all fail to compile. It used to import
  // dartvel_flutter unconditionally, so no server could register a handler.
  // The handlers that can only run under Flutter go to client_jobs.g.dart,
  // and the server half names them, so a worker can say which jobs it cannot
  // run instead of dead-lettering them in silence.
  group('the server half and the client half', () {
    const String payload = '''
@DVJob(queue: 'mail')
class _SendWelcomeEmail {
  final String userId;

  const _SendWelcomeEmail({required this.userId});
}
''';

    test('the server half imports nothing of Flutter, whatever a handler uses',
        () async {
      final (String server, String _, List<String> _) = await generateBoth(
        <String, String>{
          'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    DV.log('welcome \${job.userId}');
''',
        },
      );
      // The imports, not the text: the server half names the handler and why
      // it cannot run there, and that explanation mentions dartvel_flutter.
      expect(importsOf(server), <String>[
        "import 'package:dartvel_core/dartvel.dart';",
      ]);
    });

    test('a handler naming DV runs in the client only, and says so', () async {
      final (String server, String client, List<String> warnings) =
          await generateBoth(<String, String>{
        'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    DV.log('welcome \${job.userId}');
''',
      });
      expect(client, contains('Future<void> handleSendWelcomeEmail('));
      expect(
        client,
        contains('queues.register<SendWelcomeEmail>(handleSendWelcomeEmail);'),
      );
      expect(
        client,
        contains("import 'package:dartvel_flutter/dartvel_flutter.dart'"),
      );
      expect(server, isNot(contains('Future<void> handleSendWelcomeEmail(')));
      expect(server, isNot(contains('(handleSendWelcomeEmail);')));
      // The payload and its codec are the server's too: a backend function
      // dispatches it and the queue has to encode it.
      expect(
        server,
        contains(
          'class const SendWelcomeEmail({required final String userId}) {',
        ),
      );
      expect(server, contains('codecs.register<SendWelcomeEmail>('));
      expect(server, contains('dartvelClientOnlyJobHandlers'));
      expect(server, contains("'SendWelcomeEmail': "));
      expect(
        warnings,
        contains(allOf(contains('_handleSendWelcomeEmail'), contains('DV'))),
      );
    });

    test('DV named in a comment or a string is not a use of DV', () async {
      // Found by the worker test: a comment saying the handler "leaves
      // DV.Database for the application" put a core-only handler in the
      // client half, and the worker refused to start with no handler.
      final (String server, String client, List<String> warnings) =
          await generateBoth(<String, String>{
        'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async {
  // Not DV.log: this runs on the server.
  /* DV.Database is the application's. */
  final String note = 'sent by DV.Jobs to \${job.userId}';
  final String raw = r"DV.x";
  await const DVDatabase().execute(
    'INSERT INTO sent (id, note, raw) VALUES (?, ?, ?)',
    <Object?>[job.userId, note, raw],
  );
}
''',
      });
      expect(
        server,
        contains('queues.register<SendWelcomeEmail>(handleSendWelcomeEmail);'),
      );
      expect(client, isNot(contains('handleSendWelcomeEmail(')));
      expect(warnings, isEmpty);
    });

    test('DV used inside a string interpolation is a use of DV', () async {
      final (String server, String _, List<String> warnings) =
          await generateBoth(<String, String>{
        'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async {
  final String where = 'at \${DV.baseUrl}';
  await const DVDatabase().execute('SELECT ?', <Object?>[where]);
}
''',
      });
      expect(server, isNot(contains('(handleSendWelcomeEmail);')));
      expect(warnings, contains(contains('_handleSendWelcomeEmail')));
    });

    test('a handler written against core runs in the server, file unimported',
        () async {
      final (String server, String client, List<String> warnings) =
          await generateBoth(<String, String>{
        'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async {
  await const DVDatabase().execute(
    'INSERT INTO sent (id) VALUES (?)',
    <Object?>[job.userId],
  );
}
''',
      });
      expect(
        server,
        contains('queues.register<SendWelcomeEmail>(handleSendWelcomeEmail);'),
      );
      // The file imports the barrel, which exports Flutter. The body needs
      // nothing the file declares, so the file is never compiled here.
      expect(server, isNot(contains('package:job_app/jobs/welcome.dart')));
      expect(
        server,
        contains(
          'const Map<String, String> dartvelClientOnlyJobHandlers = '
          '<String, String>{};',
        ),
      );
      expect(client, contains('registerDartvelJobs();'));
      expect(client, isNot(contains('handleSendWelcomeEmail(')));
      expect(warnings, isEmpty);
    });

    test('a handler using its own file stays in the server when that file is '
        'server code', () async {
      final (String server, String client, List<String> _) =
          await generateBoth(<String, String>{
        'mail/mailer.dart': '''
import 'package:dartvel_core/dartvel.dart';

Future<void> deliver(String id) async {}
''',
        'jobs/welcome.dart': '''
import 'package:dartvel_core/dartvel.dart';
import '../mail/mailer.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    record(job.userId);

Future<void> record(String id) => deliver(id);
''',
      });
      expect(server, contains("import 'package:job_app/jobs/welcome.dart' as j0;"));
      expect(server, contains('j0.record(job.userId)'));
      expect(client, isNot(contains('j0.record')));
    });

    for (final (String why, Map<String, String> files) in <(
      String,
      Map<String, String>
    )>[
      (
        'imports the barrel',
        <String, String>{
          'jobs/welcome.dart': '''
import 'package:job_app/dartvel_client/dartvel_client.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    record(job.userId);

Future<void> record(String id) async {}
''',
        },
      ),
      (
        'reaches Flutter through another file of the application',
        <String, String>{
          'ui/toast.dart': '''
import 'package:flutter/widgets.dart';

void toast(String text) {}
''',
          'jobs/welcome.dart': '''
import 'package:dartvel_core/dartvel.dart';
import 'package:job_app/ui/toast.dart';

$payload
@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    record(job.userId);

Future<void> record(String id) async => toast(id);
''',
        },
      ),
    ]) {
      test('a handler using its own file runs in the client only when that '
          'file $why', () async {
        final (String server, String client, List<String> warnings) =
            await generateBoth(files);
        expect(importsOf(server), <String>[
          "import 'package:dartvel_core/dartvel.dart';",
        ]);
        expect(server, isNot(contains('j0.record')));
        expect(server, contains("'SendWelcomeEmail': "));
        expect(client, contains('j0.record(job.userId)'));
        expect(warnings, contains(contains('_handleSendWelcomeEmail')));
      });
    }
  });
}

/// The import directives of a generated file.
List<String> importsOf(String source) => <String>[
      for (final String line in source.split('\n'))
        if (line.startsWith('import ')) line,
    ];

/// Writes [files] under `lib/` and returns `jobs.g.dart`,
/// `client_jobs.g.dart` and what generation warned.
Future<(String, String, List<String>)> generateBoth(
  Map<String, String> files,
) async {
  final root = await Directory.systemTemp.createTemp('dartvel_job_split_');
  try {
    for (final MapEntry<String, String> file in files.entries) {
      final target = File(p.join(root.path, 'lib', file.key));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.value);
    }
    final List<String> warnings = await JobGenerator.generate(
      root: root.path,
      pkgName: 'job_app',
    );
    String read(String name) => File(
          p.join(root.path, 'lib', 'dartvel_client', name),
        ).readAsStringSync();
    return (read('jobs.g.dart'), read('client_jobs.g.dart'), warnings);
  } finally {
    root.deleteSync(recursive: true);
  }
}
