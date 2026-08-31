/// Runs what the cron annotations declare.
///
/// `@DVBackendCron` and `@DVClientCron` generated a list of entries and
/// nothing ran one. A schedule that is parsed but never fired is
/// documentation.
///
/// Driven by [tick] rather than owning a timer, so the caller decides the
/// cadence: a server ticks from a periodic timer, a client ticks on resume and
/// on a timer while it is foregrounded, and a test ticks by moving its clock.
library dartvel.scheduling.scheduler;

import 'dart:async';

import '../../dartvel.dart' show DVCronEntry;
import 'cron.dart';

/// A task that failed, kept so the process can report it.
class DVScheduledFailure {
  const DVScheduledFailure({
    required this.name,
    required this.at,
    required this.error,
    this.stackTrace,
  });

  final String name;
  final DateTime at;
  final Object error;
  final StackTrace? stackTrace;
}

class _DVTask {
  _DVTask({
    required this.name,
    required this.schedule,
    required this.handler,
    required this.catchUp,
    required this.maxCatchUp,
    required this.lastRun,
  });

  final String name;
  final DVCronSchedule schedule;
  final Future<void> Function() handler;
  final bool catchUp;
  final int maxCatchUp;

  /// The last occurrence this task has been run for, not the wall time it ran
  /// at: comparing occurrences is what makes a repeated tick within one minute
  /// a no-op.
  DateTime lastRun;

  /// True while the handler is in flight.
  bool running = false;
}

/// The schedule registry and the thing that fires it.
class DVScheduler {
  DVScheduler({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _startedAt = _clock();
  }

  final DateTime Function() _clock;
  late final DateTime _startedAt;
  final Map<String, _DVTask> _tasks = <String, _DVTask>{};
  final List<DVScheduledFailure> _failures = <DVScheduledFailure>[];

  List<String> get names => _tasks.keys.toList(growable: false);

  List<DVScheduledFailure> get failures =>
      List<DVScheduledFailure>.unmodifiable(_failures);

  /// Adds a task.
  ///
  /// [catchUp] runs each occurrence that was missed while the process was
  /// down, bounded by [maxCatchUp]. Off by default: a phone that was closed
  /// for four days should not send four nightly digests the moment it opens.
  /// On is right for work that writes a row per period, where a missing period
  /// is a hole in the data.
  void register(
    String name,
    String expression,
    Future<void> Function() handler, {
    bool catchUp = false,
    int maxCatchUp = 100,
  }) {
    if (_tasks.containsKey(name)) {
      // Two tasks under one name means one of them silently never runs.
      throw ArgumentError.value(
        name,
        'name',
        'a task with this name is already registered',
      );
    }
    // Parsed here rather than at the first tick, so a bad expression is a
    // startup failure instead of a silence hours later in a log nobody reads.
    final DVCronSchedule schedule = DVCronSchedule.parse(expression);
    _tasks[name] = _DVTask(
      name: name,
      schedule: schedule,
      handler: handler,
      catchUp: catchUp,
      maxCatchUp: maxCatchUp,
      lastRun: _startedAt,
    );
  }

  /// Registers every entry in [entries] against a handler of the same name.
  ///
  /// This is how a schedule declared with `@DVClientCron` reaches the
  /// scheduler without the application copying the expression out by hand.
  void registerAll(
    List<DVCronEntry> entries, {
    required Map<String, Future<void> Function()> handlers,
    bool catchUp = false,
  }) {
    for (final DVCronEntry entry in entries) {
      final Future<void> Function()? handler = handlers[entry.name];
      if (handler == null) {
        // Refused rather than skipped: silently skipping is how a job appears
        // scheduled and never runs.
        throw ArgumentError.value(
          entry.name,
          'entries',
          'no handler was supplied for this scheduled task '
              '(declared in ${entry.filePath})',
        );
      }
      register(entry.name, entry.cron, handler, catchUp: catchUp);
    }
  }

  void unregister(String name) => _tasks.remove(name);

  /// The next time [name] is due, or null if it can never run again.
  DateTime? nextRunOf(String name) {
    final _DVTask? task = _tasks[name];
    if (task == null) return null;
    return task.schedule.nextAfter(task.lastRun);
  }

  /// Runs whatever is due.
  ///
  /// Safe to call as often as the caller likes: a task is keyed to the
  /// occurrence it last ran for, so ticking every few seconds within one
  /// minute fires it once rather than a dozen times.
  Future<void> tick() async {
    final DateTime now = _clock();
    await Future.wait(<Future<void>>[
      for (final _DVTask task in _tasks.values.toList()) _runIfDue(task, now),
    ]);
  }

  Future<void> _runIfDue(_DVTask task, DateTime now) async {
    // A five-minute job on a one-minute schedule would otherwise accumulate
    // copies until the process falls over.
    if (task.running) return;

    final List<DateTime> due = <DateTime>[];
    DateTime? next = task.schedule.nextAfter(task.lastRun);
    while (next != null && !next.isAfter(now)) {
      due.add(next);
      next = task.schedule.nextAfter(next);
      if (due.length >= task.maxCatchUp) break;
    }
    if (due.isEmpty) return;

    // Without catch-up only the most recent occurrence runs, and the earlier
    // ones are marked done. Running them all is what turns a four-day absence
    // into four digests arriving at once.
    final List<DateTime> toRun =
        task.catchUp ? due : <DateTime>[due.last];

    task.running = true;
    try {
      for (final DateTime occurrence in toRun) {
        try {
          await task.handler();
        } on Object catch (error, stack) {
          // Recorded, not rethrown: one bad job must not silence every other
          // schedule in the process, and the next occurrence is a fresh
          // attempt rather than a disabled task.
          _failures.add(DVScheduledFailure(
            name: task.name,
            at: occurrence,
            error: error,
            stackTrace: stack,
          ));
        }
      }
      task.lastRun = due.last;
    } finally {
      task.running = false;
    }
  }

  /// Forgets recorded failures.
  void clearFailures() => _failures.clear();
}
