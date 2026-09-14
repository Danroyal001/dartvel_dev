/// Read-only reactive values the media runtime owns, and the timers it runs on.
library;

import 'dart:async';

/// A read-only reactive value driven by the media runtime.
///
/// `player.state`, `player.position` and `session.capturing` are these. The
/// runtime is the only thing that moves them: a play button, a scrubber and a
/// "now playing" row are readers of one value, and none of them can put the
/// value out of step with what the backend actually reported.
///
/// Deliberately the same shape as `DVLifecycleSignal` rather than the
/// widget-bound `DVSignal`: a player exists before any widget reads it and
/// after the page that started it has gone, where there is no element to bind
/// to. `dartvel_flutter` reads these into a build.
abstract interface class DVMediaSignal<T> {
  /// The current value.
  T get value;

  /// The current value. Present so reads look like every other signal.
  T read();

  /// Every change. Does not replay the current value; read [value] for that.
  Stream<T> get changes;

  /// Observes changes. Cancel the returned subscription to stop.
  StreamSubscription<T> listen(void Function(T value) onValue);
}

/// The runtime-facing half of a [DVMediaSignal].
///
/// Kept separate so a signal handed to application code carries no way to
/// drive it.
final class DVMutableMediaSignal<T> implements DVMediaSignal<T> {
  DVMutableMediaSignal(T initial) : _value = initial;

  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  @override
  T get value => _value;

  @override
  T read() => _value;

  @override
  Stream<T> get changes => _controller.stream;

  @override
  StreamSubscription<T> listen(void Function(T value) onValue) =>
      _controller.stream.listen(onValue);

  /// Whether anything is subscribed to [changes].
  bool get hasListener => _controller.hasListener;

  /// Moves the value. Setting the value it already holds emits nothing, so a
  /// reader only ever sees real changes.
  void set(T next) {
    if (_value == next) return;
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Ends the stream. The last value stays readable.
  Future<void> close() => _controller.close();
}

/// A signal that reads whichever signal it currently points at.
///
/// What lets `DVBox.video(source).controller` be taken before the box is
/// mounted, and still read the player the mounted box ends up driving: the
/// reader holds this, and the runtime moves what it points at.
///
/// Subscribes to its target only while something listens to it. A box rebuilt
/// by its parent makes a new handle every build; if each handle subscribed on
/// construction, the player would carry one more subscription per rebuild for
/// as long as it played.
final class DVForwardingMediaSignal<T> implements DVMediaSignal<T> {
  DVForwardingMediaSignal(DVMediaSignal<T> target) : _target = target {
    _controller = StreamController<T>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
  }

  DVMediaSignal<T> _target;
  StreamSubscription<T>? _subscription;
  late final StreamController<T> _controller;

  void _subscribe() {
    _subscription ??= _target.changes.listen(_forward);
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _forward(T value) {
    if (!_controller.isClosed) _controller.add(value);
  }

  /// Points this signal at [target]. A listener sees the new target's value
  /// when it differs from the old one's.
  void retarget(DVMediaSignal<T> target) {
    if (identical(target, _target)) return;
    final T before = _target.value;
    final bool listening = _subscription != null;
    _unsubscribe();
    _target = target;
    if (listening) {
      _subscribe();
      if (target.value != before) _forward(target.value);
    }
  }

  @override
  T get value => _target.value;

  @override
  T read() => _target.value;

  @override
  Stream<T> get changes => _controller.stream;

  @override
  StreamSubscription<T> listen(void Function(T value) onValue) =>
      _controller.stream.listen(onValue);

  Future<void> close() async {
    _unsubscribe();
    await _controller.close();
  }
}

/// One scheduled callback.
abstract interface class DVMediaTimer {
  void cancel();
}

/// Where the media runtime gets its timers.
///
/// A seam, because the stall watchdog and a capture's maximum duration are
/// both about time passing with nothing happening, and a test that waits for
/// real seconds to prove that is a slow test that still flakes.
abstract interface class DVMediaTimers {
  DVMediaTimer start(Duration after, void Function() onFire);
}

/// `dart:async` timers.
final class DVSystemMediaTimers implements DVMediaTimers {
  const DVSystemMediaTimers();

  @override
  DVMediaTimer start(Duration after, void Function() onFire) =>
      _DVSystemTimer(Timer(after, onFire));
}

final class _DVSystemTimer implements DVMediaTimer {
  _DVSystemTimer(this._timer);
  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// Receives a `DV-MEDIA-*` code and what happened.
typedef DVMediaDiagnosticSink = void Function(String code, String message);
