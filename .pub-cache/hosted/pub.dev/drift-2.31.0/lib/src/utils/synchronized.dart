import 'dart:async';

/// A single asynchronous lock implemented by future-chaining.
class Lock {
  Future<void>? _last;

  /// Waits for previous [synchronized]-calls on this [Lock] to complete, and
  /// then calls [block] before further [synchronized] calls are allowed.
  Future<T> synchronized<T>(FutureOr<T> Function() block) {
    final previous = _last;
    // This completer may not be sync: It must complete just after
    // callBlockAndComplete completes.
    final blockCompleted = Completer<void>();
    final blockReleasedLock = blockCompleted.future;
    _last = blockReleasedLock;

    Future<T> callBlockAndComplete() {
      return Future.sync(block).whenComplete(() {
        blockCompleted.complete();

        if (identical(_last, blockReleasedLock)) {
          // There's no subsequent waiter entering the lock now, so we can reset
          // the entire state.
          _last = null;

          // This doesn't affect the correctness of the lock, but is helpful
          // when drift is used in `fake_async` scenarios but then cleaned up
          // outside of that `fake_async` scope (a very common pattern in
          // Flutter widget tests).
          // Waiting on `previous.then` on a completed `previous` future will
          // schedule a microtask, so if we call synchronized in a zone outside
          // of fake_async and the lock was previously locked in a fake_async
          // zone, that microtask might not run if no one completes the pending
          // fake_async microtasks.
          // Since the lock is idle anyway, the next waiter can just call
          // callBlockAndComplete() directly without calling `.then()` on a
          // future that will no longer notify listeners.
        }
      });
    }

    if (previous != null) {
      return previous.then((_) => callBlockAndComplete());
    } else {
      return callBlockAndComplete();
    }
  }
}
