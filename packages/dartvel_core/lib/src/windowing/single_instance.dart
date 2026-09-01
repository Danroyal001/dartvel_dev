/// The single-instance lock behind `windowing.singleInstance`.
///
/// The Multi-Window contract sets it true by default on desktop and routes an
/// external open request — a deep link, a file association, a second launch —
/// through the same idempotent `open()`, so a second launch focuses rather
/// than forks. Nothing implemented the lock, so every launch forked and the
/// deep-link path had nothing to hand a route to.
///
/// Built on an advisory file lock rather than a pid file. The kernel drops an
/// advisory lock when the holding process dies, however it dies, so a crash
/// cannot leave the application permanently unable to start. A pid file has to
/// be reaped by someone, and the someone is usually a user deleting a file
/// they do not know about.
library dartvel.windowing.single_instance;

import 'dart:convert';
import 'dart:io';

/// A held (or refused) single-instance lock.
class DVInstanceLock {
  DVInstanceLock._({
    required this.isPrimary,
    required this.path,
    RandomAccessFile? handle,
  }) : _handle = handle;

  /// Whether this process owns the application.
  ///
  /// False means another instance is already running, and this process should
  /// hand it the route it was launched with and exit.
  final bool isPrimary;

  final String path;
  RandomAccessFile? _handle;

  File get _queue => File('$path.requests');

  /// Asks the running instance to open [route].
  ///
  /// Appends rather than overwrites: two launches in quick succession are two
  /// routes, and the second must not erase the first.
  void send(String route) {
    final List<String> pending = _read();
    // Idempotent by URL, matching open(). Two identical requests would make
    // the primary open and then focus the same window twice.
    if (pending.contains(route)) return;
    pending.add(route);
    _write(pending);
  }

  /// The routes waiting to be opened, clearing them.
  ///
  /// Only the primary drains: a secondary that drained would swallow the route
  /// it just asked for. Cleared on read, or the primary reopens the same route
  /// on every poll.
  List<String> takePending() {
    if (!isPrimary) return const <String>[];
    final List<String> pending = _read();
    if (pending.isNotEmpty) _write(const <String>[]);
    return pending;
  }

  List<String> _read() {
    if (!_queue.existsSync()) return <String>[];
    try {
      final Object? decoded = jsonDecode(_queue.readAsStringSync());
      if (decoded is! List) return <String>[];
      return <String>[
        for (final Object? entry in decoded)
          if (entry is String) entry,
      ];
    } on Object {
      // A corrupt or truncated file is recoverable; refusing to launch over it
      // is not.
      return <String>[];
    }
  }

  void _write(List<String> routes) {
    try {
      _queue.writeAsStringSync(jsonEncode(routes));
    } on Object {
      // A queue that cannot be written costs a focus request, not a launch.
    }
  }

  /// Drops the lock.
  ///
  /// Safe to call twice: release runs from a shutdown path that may itself run
  /// more than once.
  void release() {
    if (isPrimary) DVSingleInstance._held.remove(path);
    final RandomAccessFile? handle = _handle;
    _handle = null;
    if (handle == null) return;
    try {
      handle.unlockSync();
    } on Object {
      // Already gone; the close below is what matters.
    }
    try {
      handle.closeSync();
    } on Object {
      // Nothing useful to do while shutting down.
    }
  }
}

/// Acquires the application's single-instance lock.
class DVSingleInstance {
  const DVSingleInstance._();

  /// Paths this process already holds.
  ///
  /// A POSIX advisory lock is owned by the *process*, not the file
  /// descriptor, so opening the same file twice in one process and locking
  /// both succeeds. Without this, a second acquire inside one application
  /// would report itself primary and two parts of the same process would each
  /// believe they owned the application.
  static final Set<String> _held = <String>{};

  /// Takes the lock at [path], or reports that another instance holds it.
  ///
  /// Never throws. A platform or filesystem that cannot lock — a read-only
  /// home, a filesystem without advisory locking — degrades to "this process
  /// is primary", because refusing to start is a worse answer than starting
  /// twice.
  static DVInstanceLock acquire(String path) {
    if (_held.contains(path)) {
      return DVInstanceLock._(isPrimary: false, path: path);
    }

    final File file = File(path);
    try {
      file.parent.createSync(recursive: true);
      final RandomAccessFile handle = file.openSync(mode: FileMode.write);
      try {
        handle.lockSync(FileLock.exclusive);
      } on Object {
        // Held by another instance.
        handle.closeSync();
        return DVInstanceLock._(isPrimary: false, path: path);
      }
      _held.add(path);
      return DVInstanceLock._(isPrimary: true, path: path, handle: handle);
    } on Object {
      _held.add(path);
      return DVInstanceLock._(isPrimary: true, path: path);
    }
  }
}
