/// The values `DV.Workers` hands a caller, and the seam each target's
/// mechanism implements.
///
/// Kept apart from the pool so the per-target runners -- an isolate on the
/// VM, a web worker in a browser -- can depend on these without depending on
/// the pool, and so none of them imports `dart:isolate` into a web build.
library dartvel.compute.worker_types;

import 'dart:async';

import '../lifecycle/lifecycle.dart' show DVLifecycleSignal;

/// How far through a task is.
///
/// The specification says progress and cancellation are the typed events
/// Background and Durable Work defines. That section defines none, so these
/// are defined here and the jobs layer can adopt them rather than a second
/// vocabulary appearing there later.
final class DVProgress {
  const DVProgress(this.fraction, {this.message});

  /// Between 0 and 1 inclusive.
  final double fraction;

  /// What the task is doing, when it says.
  final String? message;

  @override
  String toString() =>
      'DVProgress(${(fraction * 100).toStringAsFixed(1)}%'
      '${message == null ? '' : ', $message'})';
}

/// What a task is given to report through.
abstract interface class DVWorkerReporter {
  /// Reports [fraction] done, between 0 and 1. Anything else is a programming
  /// error and throws, failing the task loudly rather than drawing a progress
  /// bar past its end.
  void progress(double fraction, {String? message});

  /// Whether the caller has cancelled.
  ///
  /// Only an inline run can see this become true: a worker on its own thread
  /// is ended outright when it is cancelled, so it never gets to look. A task
  /// that checks it is being polite to the targets without threads.
  bool get isCancelled;
}

/// A task: a top-level or static function from a typed input to a typed
/// output. That is what can cross an isolate boundary and what a web worker
/// can be handed; a closure over the calling scope is neither.
typedef DVWorkerTask<I, O> = FutureOr<O> Function(
    I input, DVWorkerReporter reporter);

/// A request to stop, which a caller or an owner's lifecycle can make.
///
/// One token may be handed to several runs; cancelling it cancels all of
/// them. Cancelling twice keeps the first reason.
final class DVCancellation {
  DVCancellation();

  /// A token that cancels itself when [owner] reaches a state [ended]
  /// accepts -- a page disposing, a request completing, the app shutting
  /// down -- so a result is never delivered to something that is gone.
  ///
  /// An owner already in such a state cancels the token at once.
  static DVCancellation until<T>(
    DVLifecycleSignal<T> owner,
    bool Function(T state) ended,
  ) {
    final DVCancellation token = DVCancellation();
    if (ended(owner.value)) {
      token.cancel('owner already ${_stateName(owner.value)}');
      return token;
    }
    token._subscription = owner.changes.listen((T state) {
      if (ended(state)) token.cancel('owner reached ${_stateName(state)}');
    });
    return token;
  }

  final Completer<void> _done = Completer<void>();
  final List<void Function()> _listeners = <void Function()>[];
  StreamSubscription<Object?>? _subscription;
  String? _reason;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Why, when it was said.
  String? get reason => _reason;

  /// Completes when the token is cancelled.
  Future<void> get whenCancelled => _done.future;

  void cancel([String? reason]) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason ?? 'cancelled';
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Listeners run synchronously, so by the time cancel() returns every run
    // holding this token has been answered and none can deliver a value.
    for (final void Function() listener
        in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
    _done.complete();
  }

  /// Stops watching an owner without cancelling.
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Registers [listener]; returns a function that removes it.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  static String _stateName(Object? state) {
    final String text = state.toString();
    final int dot = text.lastIndexOf('.');
    return dot < 0 ? text : text.substring(dot + 1);
  }
}

/// How a run ended.
enum DVWorkerOutcome { completed, failed, cancelled, timedOut }

/// What carried the work.
enum DVWorkerMechanism { isolate, webWorker, inline }

/// Why a run did not produce a value.
enum DVWorkerFailureKind {
  /// The task threw. [DVWorkerResult.error] is what it threw, when that could
  /// cross back; otherwise a failure of this kind describing it.
  threw,

  /// The worker ended without answering: it exited, or an error nobody was
  /// listening for killed it.
  crashed,

  /// The input cannot cross to the worker.
  unsendableInput,

  /// The task captured state that cannot cross to the worker
  /// (`DV-WORKER-002`).
  unsendableTask,

  /// The task's result cannot cross back.
  unsendableResult,

  cancelled,
  timedOut,
}

/// A run that produced no value, described.
final class DVWorkerFailure implements Exception {
  const DVWorkerFailure(this.kind, this.message, {this.code});

  final DVWorkerFailureKind kind;
  final String message;

  /// The diagnostic code, when there is one.
  final String? code;

  @override
  String toString() =>
      'DVWorkerFailure(${kind.name}${code == null ? '' : ', $code'}): $message';
}

/// The answer to one `DV.Workers.run`.
final class DVWorkerResult<O> {
  const DVWorkerResult.completed(O this._value, this.mechanism)
      : outcome = DVWorkerOutcome.completed,
        error = null,
        stackTrace = null;

  const DVWorkerResult.ended(
    this.outcome,
    this.mechanism, {
    required Object this.error,
    this.stackTrace,
  })  : assert(outcome != DVWorkerOutcome.completed),
        _value = null;

  final DVWorkerOutcome outcome;
  final DVWorkerMechanism mechanism;
  final O? _value;

  /// Why there is no value: what the task threw, or a [DVWorkerFailure].
  final Object? error;

  /// Where it was thrown, on the worker, when known.
  final StackTrace? stackTrace;

  bool get isCompleted => outcome == DVWorkerOutcome.completed;

  /// The value, or the reason there is none, thrown.
  O get value {
    if (outcome == DVWorkerOutcome.completed) return _value as O;
    Error.throwWithStackTrace(error!, stackTrace ?? StackTrace.empty);
  }

  @override
  String toString() => 'DVWorkerResult(${outcome.name} on ${mechanism.name}'
      '${isCompleted ? '' : ': $error'})';
}

/// What a target's workers are, reported rather than hidden.
final class DVWorkerCapability {
  const DVWorkerCapability({
    required this.mechanism,
    required this.sharedMemory,
    required this.zeroCopyNative,
    this.note,
  });

  /// Isolates on Android, iOS, desktop and embedded.
  const DVWorkerCapability.isolate()
      : mechanism = DVWorkerMechanism.isolate,
        // Isolates share no Dart heap: an input is copied in. What they can
        // share is memory outside the heap, addressed natively.
        sharedMemory = false,
        zeroCopyNative = true,
        note = null;

  /// No threads: the work runs on the calling isolate.
  const DVWorkerCapability.inline()
      : mechanism = DVWorkerMechanism.inline,
        sharedMemory = false,
        zeroCopyNative = false,
        note = 'the target has no threads; work runs on the calling isolate '
            'and the frame budget is what is lost';

  final DVWorkerMechanism mechanism;

  /// Whether a buffer can be shared with a worker rather than copied to it.
  final bool sharedMemory;

  /// Whether off-heap native memory can be handed to a worker by address.
  final bool zeroCopyNative;

  /// Anything a caller designing around this should know.
  final String? note;

  /// The specification's label for the mechanism.
  String get label => switch (mechanism) {
        DVWorkerMechanism.isolate => 'Supported',
        DVWorkerMechanism.webWorker => 'Supported with limitations',
        DVWorkerMechanism.inline => 'Unsupported → inline',
      };

  @override
  String toString() => 'DVWorkerCapability($label, ${mechanism.name}, '
      'sharedMemory: $sharedMemory, zeroCopyNative: $zeroCopyNative)';
}

// ---------------------------------------------------------------------------
// The seam between the pool and a target's mechanism. Not exported: an
// application never implements a runner, and the barrel hides these.
// ---------------------------------------------------------------------------

/// A task bound to its types, so a runner can invoke it without a dynamic
/// call and so the pair crosses a boundary as one object.
final class DVWorkerCall<I, O> {
  const DVWorkerCall(this.task);

  final DVWorkerTask<I, O> task;

  FutureOr<O> invoke(Object? input, DVWorkerReporter reporter) =>
      task(input as I, reporter);
}

/// Where a runner reports what happened to one execution.
abstract interface class DVWorkerSink {
  void progress(DVProgress progress);
  void completed(Object? value);
  void failed(Object error, StackTrace? stackTrace);

  /// The execution no longer holds a thread. Called exactly once, after any
  /// answer, and also when there never was one -- which is how a worker that
  /// dies silently still reaches its caller.
  void exited();
}

/// One running execution.
abstract interface class DVWorkerExecution {
  /// Ends the work. The runner still reports [DVWorkerSink.exited] once the
  /// thread is actually gone.
  void stop();
}

/// A target's way of running work.
abstract interface class DVWorkerRunner {
  DVWorkerCapability get capability;
  DVWorkerExecution start(
      DVWorkerCall<Object?, Object?> call, Object? input, DVWorkerSink sink);
}

/// Validates a reported fraction.
DVProgress dvCheckedProgress(double fraction, String? message) {
  if (fraction.isNaN || fraction < 0 || fraction > 1) {
    throw ArgumentError.value(
        fraction, 'fraction', 'progress is a fraction between 0 and 1');
  }
  return DVProgress(fraction, message: message);
}
