/// `DV.Workers`: declared offloadable work on a bounded pool.
///
/// One surface on every target. What carries the work -- an isolate, a web
/// worker, or the calling isolate where there are no threads -- is the
/// runner's business and is reported through [DVWorkers.capability], not
/// something a caller chooses.
library dartvel.compute.workers;

import 'dart:async';
import 'dart:collection';

import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'worker_types.dart';
import 'workers_host_stub.dart'
    if (dart.library.isolate) 'workers_isolate.dart' as host;

/// How many workers a device gets, from what the device is.
///
/// Not a count an application sets: a hand-tuned number is right on the
/// device it was tuned on and wrong on the next one. A device profile says
/// how many cores the device has and the rule below does the rest.
final class DVWorkerProfile {
  const DVWorkerProfile({required this.cores});

  /// The host's own report, for a build with no device profile.
  ///
  /// On an embedded board this is the number the specification warns
  /// against, because a board can report cores the UI needs; a profile that
  /// names the device is what fixes that.
  factory DVWorkerProfile.host() =>
      DVWorkerProfile(cores: host.dvHostProcessors());

  /// Cores the device has.
  final int cores;

  /// The most workers any device gets. Past this an isolate's heap costs more
  /// than another core returns for the client-side work workers are for.
  static const int ceiling = 8;

  /// One core is left for the UI; a device with one or two still gets a
  /// worker, because work off the event loop is preempted by the OS instead
  /// of stalling every frame until it finishes.
  int get poolSize {
    if (cores < 1) {
      throw ArgumentError.value(cores, 'cores', 'a device has at least one');
    }
    final int spare = cores - 1;
    if (spare < 1) return 1;
    return spare > ceiling ? ceiling : spare;
  }
}

/// The pool.
final class DVWorkers {
  /// Workers carried by the target's own mechanism.
  DVWorkers({DVWorkerProfile? profile})
      : this._(host.dvHostWorkerRunner() ?? const _InlineRunner(),
            profile ?? DVWorkerProfile.host());

  /// Workers that run on the calling isolate: what a target without threads
  /// gets, and what a test of that degradation constructs.
  DVWorkers.inline({DVWorkerProfile? profile})
      : this._(const _InlineRunner(), profile ?? const DVWorkerProfile(cores: 1));

  DVWorkers._(this._runner, DVWorkerProfile profile)
      : poolSize = profile.poolSize;

  final DVWorkerRunner _runner;

  /// How many tasks may hold a thread at once.
  final int poolSize;

  static DVWorkers? _current;

  /// The application's pool: `DV.Workers`.
  static DVWorkers get current => _current ??= DVWorkers();

  /// Replaces the application's pool, e.g. with one sized from the device
  /// profile the build was made for.
  static void configure(DVWorkers workers) => _current = workers;

  static bool _inlineReported = false;

  /// Lets a test observe the once-per-boot diagnostics again.
  static void debugResetOnceDiagnostics() => _inlineReported = false;

  /// What carries the work here, and what that costs.
  DVWorkerCapability get capability => _runner.capability;

  final Queue<_Job<Object?>> _queue = Queue<_Job<Object?>>();
  final Set<_Job<Object?>> _started = <_Job<Object?>>{};
  int _slots = 0;
  bool _saturationReported = false;
  bool _closed = false;
  Completer<void>? _drained;

  /// Tasks started and not yet answered.
  int get running =>
      _started.where((_Job<Object?> job) => !job.settled).length;

  /// Tasks waiting for a slot.
  int get queued => _queue.length;

  /// Threads still held -- including one whose task was cancelled and whose
  /// isolate has not finished ending. The bound applies to this number.
  int get live => _slots;

  /// Runs [task] on [input] off the calling isolate.
  ///
  /// The returned future always completes, exactly once: with the value,
  /// with what the task threw, with a crash when the worker died without
  /// answering, or cancelled or timed out. After it completes, [onProgress]
  /// is never called again.
  ///
  /// [timeout] runs from this call, so time spent queued behind a saturated
  /// pool counts: a caller's deadline is about when it gets an answer.
  Future<DVWorkerResult<O>> run<I, O>(
    DVWorkerTask<I, O> task, {
    required I input,
    void Function(DVProgress progress)? onProgress,
    DVCancellation? cancellation,
    Duration? timeout,
  }) {
    if (_closed) {
      throw StateError('DV.Workers is closed; it accepts no more tasks.');
    }
    final _Job<O> job = _Job<O>(
      this,
      DVWorkerCall<I, O>(task),
      input,
      onProgress,
      Zone.current,
    );
    if (cancellation != null) {
      if (cancellation.isCancelled) {
        job.end(DVWorkerOutcome.cancelled,
            DVWorkerFailure(DVWorkerFailureKind.cancelled,
                cancellation.reason ?? 'cancelled'));
        return job.completer.future;
      }
      job.detach = cancellation.onCancel(() => job.end(
          DVWorkerOutcome.cancelled,
          DVWorkerFailure(
              DVWorkerFailureKind.cancelled, cancellation.reason ?? 'cancelled')));
    }
    if (timeout != null) {
      job.timer = Timer(
          timeout,
          () => job.end(
              DVWorkerOutcome.timedOut,
              DVWorkerFailure(DVWorkerFailureKind.timedOut,
                  'no answer within ${timeout.inMilliseconds} ms')));
    }
    _queue.add(job);
    _pump();
    if (!job.settled && job.execution == null && !_saturationReported) {
      _saturationReported = true;
      DVObservability.log(
        'The worker pool is saturated and tasks are queueing behind it.',
        level: DVLogLevel.warn,
        code: 'DV-WORKER-005',
        context: <String, Object?>{'poolSize': poolSize, 'queued': queued},
      );
    }
    return job.completer.future;
  }

  /// Cancels everything queued and running, and completes when every thread
  /// the pool held has ended.
  Future<void> close() {
    _closed = true;
    for (final _Job<Object?> job in <_Job<Object?>>[..._queue, ..._started]) {
      job.end(DVWorkerOutcome.cancelled,
          const DVWorkerFailure(DVWorkerFailureKind.cancelled, 'the pool closed'));
    }
    if (_slots == 0) return Future<void>.value();
    return (_drained ??= Completer<void>()).future;
  }

  void _pump() {
    while (_queue.isNotEmpty && _slots < poolSize) {
      final _Job<Object?> job = _queue.removeFirst();
      if (job.settled) continue;
      _slots++;
      job.holdsSlot = true;
      _started.add(job);
      if (_runner.capability.mechanism == DVWorkerMechanism.inline &&
          !_inlineReported) {
        _inlineReported = true;
        DVObservability.log(
          'A task ran inline because the target has no threads.',
          level: DVLogLevel.info,
          code: 'DV-WORKER-001',
        );
      }
      job.execution = _runner.start(job.call, job.input, job);
    }
    if (_queue.isEmpty) _saturationReported = false;
  }

  void _unqueue(_Job<Object?> job) => _queue.remove(job);

  void _release(_Job<Object?> job) {
    _started.remove(job);
    _slots--;
    if (!_closed) _pump();
    if (_slots == 0 && _drained != null && !_drained!.isCompleted) {
      _drained!.complete();
    }
  }
}

final class _Job<O> implements DVWorkerSink {
  _Job(this.pool, this.call, this.input, this.onProgress, this.zone);

  final DVWorkers pool;
  final DVWorkerCall<Object?, Object?> call;
  final Object? input;
  final void Function(DVProgress progress)? onProgress;
  final Zone zone;
  final Completer<DVWorkerResult<O>> completer = Completer<DVWorkerResult<O>>();

  DVWorkerExecution? execution;
  Timer? timer;
  void Function()? detach;
  bool settled = false;
  bool holdsSlot = false;

  DVWorkerMechanism get _mechanism => pool.capability.mechanism;

  /// Answers the caller, once. Anything but a value or a failure the worker
  /// reported also ends the work, so a cancelled task stops charging.
  void end(DVWorkerOutcome outcome, Object error, [StackTrace? stackTrace]) {
    if (settled) return;
    settled = true;
    _tidy();
    pool._unqueue(this);
    completer.complete(DVWorkerResult<O>.ended(outcome, _mechanism,
        error: error, stackTrace: stackTrace));
    if (outcome == DVWorkerOutcome.cancelled ||
        outcome == DVWorkerOutcome.timedOut) {
      execution?.stop();
    }
  }

  void _tidy() {
    timer?.cancel();
    timer = null;
    detach?.call();
    detach = null;
  }

  @override
  void progress(DVProgress progress) {
    final void Function(DVProgress)? listener = onProgress;
    if (settled || listener == null) return;
    zone.runUnaryGuarded(listener, progress);
  }

  @override
  void completed(Object? value) {
    if (settled) return;
    settled = true;
    _tidy();
    completer.complete(DVWorkerResult<O>.completed(value as O, _mechanism));
  }

  @override
  void failed(Object error, StackTrace? stackTrace) {
    if (settled) return;
    end(DVWorkerOutcome.failed, error, stackTrace);
  }

  @override
  void exited() {
    if (!holdsSlot) return;
    holdsSlot = false;
    if (!settled) {
      end(
          DVWorkerOutcome.failed,
          const DVWorkerFailure(DVWorkerFailureKind.crashed,
              'the worker ended without answering'));
    }
    pool._release(this);
  }
}

/// The calling isolate. Work still happens and is still correct; the frame
/// budget is what is lost, which is why the first use says so.
final class _InlineRunner implements DVWorkerRunner {
  const _InlineRunner();

  @override
  DVWorkerCapability get capability => const DVWorkerCapability.inline();

  @override
  DVWorkerExecution start(
      DVWorkerCall<Object?, Object?> call, Object? input, DVWorkerSink sink) {
    final _InlineExecution execution = _InlineExecution(sink);
    // A later event rather than now, so run() has returned its future and a
    // frame can be drawn before synchronous work takes the loop.
    Timer.run(() {
      if (execution.stopped) return;
      unawaited(Future<Object?>.sync(() => call.invoke(input, execution))
          .then(sink.completed, onError: sink.failed)
          .whenComplete(execution.release));
    });
    return execution;
  }
}

final class _InlineExecution implements DVWorkerExecution, DVWorkerReporter {
  _InlineExecution(this.sink);

  final DVWorkerSink sink;
  bool stopped = false;
  bool _released = false;

  @override
  bool get isCancelled => stopped;

  @override
  void progress(double fraction, {String? message}) {
    final DVProgress checked = dvCheckedProgress(fraction, message);
    if (!stopped) sink.progress(checked);
  }

  @override
  void stop() {
    stopped = true;
    // Nothing can be preempted here, so the slot is not held for work that
    // cannot be ended; a cooperative task sees isCancelled and returns.
    release();
  }

  void release() {
    if (_released) return;
    _released = true;
    sink.exited();
  }
}
