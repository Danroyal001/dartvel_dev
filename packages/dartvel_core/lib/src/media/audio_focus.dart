/// Who is making sound.
///
/// One owner at a time. On Android that is AudioManager's focus, on iOS the
/// AVAudioSession, on a desktop it is only this process's own players -- but
/// the rule inside the application is the same everywhere: a second player
/// starting pauses the first, and a player that stops gives focus back. The
/// failure being prevented is silent: focus held by a player nobody can see
/// keeps the podcast the person paused for from ever resuming.
library;

import 'dart:async';

/// The platform half of audio focus.
abstract interface class DVAudioFocusBackend {
  /// Asks the platform for focus. False when it refused -- a call in
  /// progress, another application holding exclusive focus.
  Future<bool> request();

  /// Gives focus back.
  Future<void> abandon();

  /// Fires when the platform takes focus away: an incoming call, another
  /// application starting playback.
  Stream<void> get losses;
}

/// A backend for a target with no platform focus to negotiate: always
/// granted, never lost. Arbitration between this application's own players
/// still happens in [DVAudioFocus].
final class DVProcessAudioFocusBackend implements DVAudioFocusBackend {
  const DVProcessAudioFocusBackend();

  @override
  Future<bool> request() async => true;

  @override
  Future<void> abandon() async {}

  @override
  Stream<void> get losses => const Stream<void>.empty();
}

/// Thrown by `play()` when the platform refused audio focus.
final class DVAudioFocusRefused implements Exception {
  const DVAudioFocusRefused();

  @override
  String toString() =>
      'DVAudioFocusRefused: the platform did not grant audio focus';
}

/// Arbitrates audio focus between this application's players, and with the
/// platform.
final class DVAudioFocus {
  DVAudioFocus([this._backend = const DVProcessAudioFocusBackend()]) {
    _losses = _backend.losses.listen((_) => _lost());
  }

  final DVAudioFocusBackend _backend;
  late final StreamSubscription<void> _losses;

  Object? _holder;
  void Function()? _onLoss;
  bool _platformHeld = false;

  /// The player holding focus, or null.
  Object? get holder => _holder;

  /// Takes focus for [owner]. The previous holder, if any, is told through
  /// its own `onLoss` before this returns. False when the platform refused.
  Future<bool> acquire(Object owner, {required void Function() onLoss}) async {
    if (identical(_holder, owner)) {
      _onLoss = onLoss;
      return true;
    }
    if (!_platformHeld) {
      if (!await _backend.request()) return false;
      _platformHeld = true;
    }
    final void Function()? previous = _onLoss;
    _holder = owner;
    _onLoss = onLoss;
    previous?.call();
    return true;
  }

  /// Gives focus back if [owner] holds it. A no-op otherwise, so a player
  /// that lost focus to another can release without taking it from them.
  Future<void> release(Object owner) async {
    if (!identical(_holder, owner)) return;
    _holder = null;
    _onLoss = null;
    if (_platformHeld) {
      _platformHeld = false;
      await _backend.abandon();
    }
  }

  void _lost() {
    final void Function()? onLoss = _onLoss;
    _holder = null;
    _onLoss = null;
    _platformHeld = false;
    onLoss?.call();
  }

  Future<void> dispose() => _losses.cancel();
}

/// The process's audio focus, used by players that were not given one.
final DVAudioFocus dvAudioFocus = DVAudioFocus();
