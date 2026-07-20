import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';

class QueueCommand extends Command<void> {
  @override
  final String name = 'queue';

  @override
  String get description => 'Work and inspect Dartvel queues.';

  QueueCommand() {
    addSubcommand(_QueueWorkCommand());
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

  _QueueWorkCommand() {
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
    final completed = await const DVQueues().work(
      queue: queue,
      maxJobs: maxJobs,
    );
    stdout.writeln('Processed $completed job(s) from "$queue".');
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
        '${job.id}\t${job.payload.runtimeType}\tattempts=${job.attempts}\terror=${job.lastError}',
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
