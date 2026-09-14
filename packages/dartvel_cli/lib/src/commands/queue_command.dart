import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/routes_generator.dart' as routes;

class QueueCommand extends Command<void> {
  @override
  final String name = 'queue';

  @override
  String get description => 'Work and inspect Dartvel queues.';

  /// [root] is the project `queue work` runs the worker of; the working
  /// directory when null, which is what the CLI passes.
  QueueCommand({String? root}) {
    addSubcommand(_QueueWorkCommand(root));
    addSubcommand(_QueueFailedCommand());
    addSubcommand(_QueueRetryCommand());
    addSubcommand(_QueueFlushCommand());
  }
}

class _QueueWorkCommand extends Command<void> {
  @override
  final String name = 'work';

  @override
  String get description => 'Run queued jobs for a queue.';

  /// The project whose worker runs; the working directory when null.
  final String? _root;

  _QueueWorkCommand(this._root) {
    argParser
      ..addOption('queue', defaultsTo: 'default', help: 'Queue name to work.')
      ..addOption('max-jobs',
          defaultsTo: '1', help: 'Maximum jobs to reserve and process.');
  }

  @override
  Future<void> run() async {
    final queue = argResults?['queue'] as String? ?? 'default';
    final maxJobs = int.tryParse(argResults?['max-jobs'] as String? ?? '1');
    if (maxJobs == null || maxJobs < 1) {
      throw UsageException('--max-jobs must be a positive integer.', usage);
    }

    // In a Dartvel project the jobs, their handlers and the queue are the
    // application's, and none of them is in this process: working the CLI's
    // own queue drained a queue nothing had dispatched to and registered no
    // handler. So the project's generated backend runs as a worker, the same
    // program a DARTVEL_ROLE=worker unit starts, bounded by --max-jobs.
    final Directory project = Directory(_root ?? Directory.current.path);
    if (_isDartvelProject(project)) {
      await routes.generate(root_: project.path);
      final Process worker = await Process.start(
        'dart',
        <String>[
          'run',
          '.dart_tool/dartvel_server.dart',
          '--max-jobs=$maxJobs',
        ],
        workingDirectory: project.path,
        environment: <String, String>{
          'DARTVEL_ROLE': 'worker',
          'DARTVEL_QUEUE': queue,
        },
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await worker.exitCode;
      return;
    }

    // Outside a project there is only this process's queue.
    final completed = await const DVQueues().work(
      queue: queue,
      maxJobs: maxJobs,
    );
    stdout.writeln('Processed $completed job(s) from "$queue".');
  }

  static bool _isDartvelProject(Directory root) {
    final File pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    try {
      final Object? yaml = loadYaml(pubspec.readAsStringSync());
      return yaml is YamlMap && yaml.containsKey('dartvel');
    } on Object {
      return false;
    }
  }
}

class _QueueFailedCommand extends Command<void> {
  @override
  final String name = 'failed';

  @override
  String get description => 'List dead-lettered jobs for a queue.';

  _QueueFailedCommand() {
    argParser.addOption('queue', defaultsTo: 'default', help: 'Queue name.');
  }

  @override
  Future<void> run() async {
    final queue = argResults?['queue'] as String? ?? 'default';
    final jobs = await const DVQueues().deadLetters(queue);
    if (jobs.isEmpty) {
      stdout.writeln('No failed jobs in "$queue".');
      return;
    }
    for (final job in jobs) {
      stdout.writeln(
        '${job.id}\t${job.payloadType}\tattempts=${job.attempts}\terror=${job.lastError}',
      );
    }
  }
}

class _QueueRetryCommand extends Command<void> {
  @override
  final String name = 'retry';

  @override
  String get description => 'Retry a dead-lettered job by id.';

  @override
  Future<void> run() async {
    final args = argResults?.rest ?? const <String>[];
    if (args.length != 1 || args.single.trim().isEmpty) {
      throw UsageException('Provide a failed job id to retry.', usage);
    }
    final id = args.single.trim();
    final retried = await const DVQueues().retry(id);
    if (!retried) {
      stderr.writeln('Failed job "$id" was not found.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Retried job "$id".');
  }
}

class _QueueFlushCommand extends Command<void> {
  @override
  final String name = 'flush';

  @override
  String get description => 'Remove pending and failed jobs for a queue.';

  _QueueFlushCommand() {
    argParser.addOption('queue', defaultsTo: 'default', help: 'Queue name.');
  }

  @override
  Future<void> run() async {
    final queue = argResults?['queue'] as String? ?? 'default';
    final removed = await const DVQueues().flush(queue: queue);
    stdout.writeln('Removed $removed job(s) from "$queue".');
  }
}
