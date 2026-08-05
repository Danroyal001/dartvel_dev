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

    expect(generated, contains('class SendWelcomeEmail {'));
    expect(generated, contains('final String userId;'));
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

  test('a block-bodied handler names the restriction it hits', () async {
    await expectLater(
      generate('''
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
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('expression body'),
        ),
      ),
    );
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
}
