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
import '../cache/adapters.dart' show DVAtomicCacheAdapter;
import '../database/adapter.dart' show DVDatabaseAdapter;
import '../database/framework_tables.dart';
import '../preview/preview_outbound.dart' show DVPreviewOutbound;
import 'cron.dart';

/// Decides which process runs an occurrence when several tick the same
/// schedules.
///
/// Every process that ticks sees the same occurrence come due. Without a
/// lease each one runs it, which is the nightly job firing once per process.
abstract interface class DVScheduleLease {
  /// Claims [occurrence] of [task]. True for exactly one claimant across
  /// every process sharing the lease's store; false for the rest.
  Future<bool> claim(String task, DateTime occurrence);
}

/// A [DVScheduleLease] on a cache store with compare-and-set: Redis,
/// Memcached, or any [DVAtomicCacheAdapter].
///
/// The claim is keyed to the occurrence -- the instant the schedule named,
/// not the wall time a process ticked at -- so processes whose timers land
/// seconds apart, or whose clocks read different time zones, claim the same
/// key. It is held for [hold] and never released: a released claim is one a
/// late ticker takes again.
///
/// An occurrence is claimed before it runs, so a process that dies while
/// running it does not have it re-run elsewhere. At most once, deliberately:
/// the alternative is at least once, which is the double fire this prevents.
final class DVCacheScheduleLease implements DVScheduleLease {
  DVCacheScheduleLease(
    this.store, {
    this.prefix = 'dartvel:schedule',
    this.hold = const Duration(days: 2),
  });

  final DVAtomicCacheAdapter store;
  final String prefix;
  final Duration hold;

  @override
  Future<bool> claim(String task, DateTime occurrence) => store.writeIfAbsent(
        '$prefix:$task:${occurrence.toUtc().toIso8601String()}',
        DateTime.now().toUtc().toIso8601String(),
        hold,
      );
}

/// A [DVScheduleLease] on the application's database, for a deployment whose
/// processes share one but no cache store with compare-and-set.
///
/// A claim is a row whose primary key is the occurrence -- the task and the
/// instant the schedule named, in UTC -- so the database's own uniqueness
/// decides between two processes inserting it at once, on Postgres, MySQL
/// and a SQLite file alike. An insert that fails is a lost claim only when
/// the row is there afterwards; anything else is a database that cannot be
/// reached and is rethrown, so the scheduler records it and runs nothing.
///
/// Held for [hold] like [DVCacheScheduleLease], and never released. A SQLite
/// file is shared by the processes of one host only: cron processes on two
/// hosts need a database both reach.
final class DVDatabaseScheduleLease implements DVScheduleLease {
  DVDatabaseScheduleLease(
    this.database, {
    this.tableName = 'dartvel_schedule_leases',
    this.hold = const Duration(days: 2),
  }) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Lease table names must be plain SQL identifiers.',
      );
    }
  }

  final DVDatabaseAdapter database;
  final String tableName;
  final Duration hold;
  bool _initialized = false;

  @override
  Future<bool> claim(String task, DateTime occurrence) async {
    if (!_initialized) {
      await dvEnsureFrameworkTable(
        database,
        'CREATE TABLE IF NOT EXISTS $tableName ('
        'lease_key VARCHAR(255) PRIMARY KEY, '
        'claimed_at BIGINT NOT NULL, '
        'expires_at BIGINT NOT NULL)',
      );
      _initialized = true;
    }
    final String key = '$task:${occurrence.toUtc().toIso8601String()}';
    final int now = DateTime.now().millisecondsSinceEpoch;
    await database.execute(
      'DELETE FROM $tableName WHERE expires_at < ?',
      <Object?>[now],
    );
    try {
      await database.execute(
        'INSERT INTO $tableName (lease_key, claimed_at, expires_at) '
        'VALUES (?, ?, ?)',
        <Object?>[key, now, now + hold.inMilliseconds],
      );
      return true;
    } on Object {
      final List<Map<String, Object?>> held = await database.query(
        'SELECT lease_key FROM $tableName WHERE lease_key = ?',
        <Object?>[key],
      );
      if (held.isNotEmpty) return false;
      rethrow;
    }
  }
}

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
  /// [lease], when given, is claimed for each occurrence before it runs, so
  /// processes sharing its store run each occurrence once between them.
  ///
  /// [onFailure] is told about each task that throws, as it happens. Without
  /// it a failure is kept in [failures], which a served process never reads.
  DVScheduler({DateTime Function()? clock, this.lease, this.onFailure})
      : _clock = clock ?? DateTime.now {
    _startedAt = _clock();
  }

  final DateTime Function() _clock;
  final DVScheduleLease? lease;
  final void Function(DVScheduledFailure failure)? onFailure;
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
  ///
  /// [catchUp] is the blanket setting, and a schedule that stated one of its
  /// own wins over it. An application that turns catch-up on has decided
  /// about the schedules that said nothing; a schedule that wrote it down
  /// had already decided about itself.
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
      register(
        entry.name,
        entry.cron,
        handler,
        catchUp: entry.catchUp ?? catchUp,
      );
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

    // A preview runs only the schedules it declared. The occurrences are
    // marked done rather than left due, so declaring a schedule later does
    // not release a backlog of the week the preview sat open.
    if (!DVPreviewOutbound.allowsSchedule(task.name)) {
      task.lastRun = due.last;
      return;
    }

    // Without catch-up only the most recent occurrence runs, and the earlier
    // ones are marked done. Running them all is what turns a four-day absence
    // into four digests arriving at once.
    final List<DateTime> toRun =
        task.catchUp ? due : <DateTime>[due.last];

    task.running = true;
    try {
      for (final DateTime occurrence in toRun) {
        try {
          final DVScheduleLease? lease = this.lease;
          // Claimed inside the try: a store that cannot be reached runs
          // nothing and is recorded. Running unguarded would be the double
          // fire the lease is for.
          if (lease != null && !await lease.claim(task.name, occurrence)) {
            continue;
          }
          await task.handler();
        } on Object catch (error, stack) {
          // Recorded, not rethrown: one bad job must not silence every other
          // schedule in the process, and the next occurrence is a fresh
          // attempt rather than a disabled task.
          final DVScheduledFailure failure = DVScheduledFailure(
            name: task.name,
            at: occurrence,
            error: error,
            stackTrace: stack,
          );
          _failures.add(failure);
          // A listener that throws must not stop the other occurrences, for
          // the same reason the task's own failure does not.
          try {
            onFailure?.call(failure);
          } on Object {
            // Kept in failures above either way.
          }
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
