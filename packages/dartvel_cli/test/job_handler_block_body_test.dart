// A block-bodied @DVJob.handler, generated end to end.
//
// The fourth and last generation input that refused a block body, and the one
// where it bit hardest: a job handler is the place people write retries,
// branching and several awaits, none of which fits an expression.
import 'dart:io';

import 'package:dartvel_cli/src/generators/job_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generateJobs(String source) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_job_block_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'jobs')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'jobs', 'jobs.dart')).writeAsStringSync(source);

  await JobGenerator.generate(
    root: root.path,
    pkgName: 'job_app',
    buildId: 'test-build',
  );

  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'jobs.g.dart'),
  ).readAsStringSync();
}

const String _job = '''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail')
class _SendWelcome {
  final String userId;

  const _SendWelcome({required this.userId});
}
''';

void main() {
  test('a block body reaches the generated handler', () async {
    final String jobs = await generateJobs('''$_job
@DVJob.handler()
Future<void> _sendWelcome(SendWelcome job) async {
  final String id = job.userId.trim();
  await deliver(id);
}

Future<void> deliver(String id) async {}
''');

    expect(jobs, contains('final String id = job.userId.trim();'));
    expect(jobs, contains('await j0.deliver(id);'));
  });

  test('a conditional and an early return survive', () async {
    final String jobs = await generateJobs('''$_job
@DVJob.handler()
Future<void> _sendWelcome(SendWelcome job) async {
  if (job.userId.isEmpty) {
    return;
  }
  await deliver(job.userId);
}

Future<void> deliver(String id) async {}
''');

    expect(jobs, contains('if (job.userId.isEmpty)'));
    expect(jobs, contains('return;'));
  });

  test('a symbol in an interpolation stays interpolated', () async {
    // The job generator carried its own copy of the qualifier, with the same
    // defect: `$prefix` became `$j0.prefix`, which Dart reads as the prefix
    // `w0` followed by literal text.
    final String jobs = await generateJobs('''$_job
const String prefix = 'welcome';

@DVJob.handler()
Future<void> _sendWelcome(SendWelcome job) async {
  await deliver('\$prefix:\${job.userId}');
}

Future<void> deliver(String id) async {}
''');

    expect(jobs, contains(r'${j0.prefix}'));
    expect(jobs, isNot(contains(r'$j0.prefix')));
  });

  test('an expression body still works', () async {
    final String jobs = await generateJobs('''$_job
@DVJob.handler()
Future<void> _sendWelcome(SendWelcome job) async => deliver(job.userId);

Future<void> deliver(String id) async {}
''');

    expect(jobs, contains('j0.deliver(job.userId)'));
  });
}
