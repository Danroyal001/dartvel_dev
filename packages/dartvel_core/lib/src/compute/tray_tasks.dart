/// The background work a reader is shown.
///
/// Error, Empty, and Loading States: a background-task tray shows uploads,
/// exports and imports from the typed progress events the framework already
/// has. [DVProgress] is that event; this is the list of named work it belongs
/// to, which the page shell's tray renders. A `DV.Workers` run given a
/// `label:` is listed here while it runs, and leaves however it ends.
library dartvel.compute.tray_tasks;

import 'dart:async';

import 'worker_types.dart' show DVProgress;

/// The named work in progress in this process.
final class DVTrayTasks {
  DVTrayTasks();

  static DVTrayTasks? _current;

  /// The process's registry, which the default `DV.Workers` reports to and
  /// the page shell's tray reads.
  static DVTrayTasks get current => _current ??= DVTrayTasks();

  final List<DVTrayTask> _active = <DVTrayTask>[];
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

  /// The tasks running now, oldest first.
  List<DVTrayTask> get active => List<DVTrayTask>.unmodifiable(_active);

  /// An event each time a task starts, reports or ends.
  Stream<void> get changes => _changes.stream;

  /// Lists work named [label] until the returned task is ended.
  DVTrayTask begin(String label) {
    final DVTrayTask task = DVTrayTask._(this, label);
    _active.add(task);
    _changes.add(null);
    return task;
  }

  void _changed() => _changes.add(null);

  void _end(DVTrayTask task) {
    if (_active.remove(task)) _changes.add(null);
  }
}

/// One piece of named work, from begin to end.
final class DVTrayTask {
  DVTrayTask._(this._owner, this.label);

  final DVTrayTasks _owner;
  bool _ended = false;

  /// What the reader is told the work is.
  final String label;

  /// The latest progress reported, or null before the first report.
  DVProgress? get progress => _progress;
  DVProgress? _progress;

  /// Whether [end] has been called.
  bool get ended => _ended;

  /// Records [progress]; dropped once the task has ended, so a late report
  /// never brings a finished task back.
  void report(DVProgress progress) {
    if (_ended) return;
    _progress = progress;
    _owner._changed();
  }

  /// Takes the task off the list. Calling it again does nothing.
  void end() {
    if (_ended) return;
    _ended = true;
    _owner._end(this);
  }
}
