/// Leaving a kiosk, and failing to.
///
/// The exit method is the whole of "cannot be left by the user": staff get out
/// with a PIN, and everyone else does not. What makes that true is the
/// counting -- `maxAttempts`, then a lockout that outlasts the person trying.
///
/// State only. Nothing here touches a display or an input device; a device
/// that cannot enforce fullscreen or confine input reports that through
/// enforcement rather than by pretending here.
library dartvel.kiosk.runtime;

import 'dart:async';

import '../lifecycle/lifecycle.dart' show DVLifecycleRegistry;
import 'policy.dart';

/// Where a kiosk is.
enum DVKioskState { off, active, staffMode, resetting, locked, failed }

/// Why a session was reset.
enum DVKioskResetReason { idle, explicit, staffExit, startup }

/// A request to leave kiosk mode.
class DVKioskExitRequest {
  const DVKioskExitRequest._(this.method, this.value);

  /// A PIN entry.
  const DVKioskExitRequest.pin(String pin)
      : this._(DVKioskExitMethod.pin, pin);

  /// An authenticated administrator.
  const DVKioskExitRequest.adminAuth(String token)
      : this._(DVKioskExitMethod.adminAuth, token);

  /// A remote management instruction.
  const DVKioskExitRequest.remote(String token)
      : this._(DVKioskExitMethod.remote, token);

  final DVKioskExitMethod method;
  final String value;
}

/// What came of an exit attempt.
class DVKioskExitResult {
  const DVKioskExitResult({
    required this.granted,
    required this.message,
    this.code,
  });

  final bool granted;

  /// Safe to show on a kiosk screen: never says what the right answer was, or
  /// how close the wrong one came.
  final String message;

  /// The diagnostic code, when something was worth reporting.
  final String? code;
}

/// What a reset cleared, and where it left the kiosk.
class DVKioskReset {
  const DVKioskReset({
    required this.cleared,
    required this.home,
    required this.reason,
  });

  final Set<DVKioskClearable> cleared;
  final String home;
  final DVKioskResetReason reason;
}

/// A minimal read-only signal, so this package needs no Flutter.
class DVKioskSignal<T> {
  DVKioskSignal(this._value);

  T _value;
  final List<void Function()> _listeners = <void Function()>[];

  T get value => _value;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _set(T next) {
    if (next == _value) return;
    _value = next;
    for (final void Function() listener
        in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

/// The kiosk state machine.
class DVKioskRuntime {
  DVKioskRuntime(
    this.policy, {
    Future<String?> Function(String name)? readSecret,
    DateTime Function()? clock,
    Future<void> Function(Set<DVKioskClearable> what)? clear,
    this.tickEvery = const Duration(seconds: 1),
    this.lifecycle,
  })  : _readSecret = readSecret ?? _noSecrets,
        _clock = clock ?? DateTime.now,
        _clear = clear ?? _nothingToClear,
        state = DVKioskSignal<DVKioskState>(DVKioskState.off),
        countdown = DVKioskSignal<Duration?>(null);

  final DVKioskPolicy policy;
  final Future<String?> Function(String name) _readSecret;
  final DateTime Function() _clock;

  /// Performs the policy's clearOnReset: the application knows its signals,
  /// forms and stores; the runtime knows when. Called with what to clear,
  /// never with an empty set.
  final Future<void> Function(Set<DVKioskClearable> what) _clear;

  /// How often the idle clock is checked while active.
  final Duration tickEvery;

  /// Where `DV.lifecycle.kiosk` lives, when the application wired one: every
  /// state this runtime enters is mirrored there, so pages observe the
  /// kiosk the way they observe the app.
  final DVLifecycleRegistry? lifecycle;

  void _enter(DVKioskState next) {
    state._set(next);
    lifecycle?.setKiosk(next);
  }

  /// Observed, never assigned from outside.
  final DVKioskSignal<DVKioskState> state;

  /// Time left before the idle action, while the warning is showing; null
  /// otherwise. Drive the countdown route from this.
  final DVKioskSignal<Duration?> countdown;

  // Synchronous: the app's "go home" runs inside reset(), before the runtime
  // reports active again, so nothing is drawn against a half-cleared session.
  final StreamController<DVKioskReset> _resets =
      StreamController<DVKioskReset>.broadcast(sync: true);

  /// Every reset, idle or explicit, as it happens: what was cleared and
  /// where to go. The app navigates to [DVKioskReset.home] on each.
  Stream<DVKioskReset> get resets => _resets.stream;

  DateTime? _lastActivity;
  Timer? _timer;

  static Future<void> _nothingToClear(Set<DVKioskClearable> _) async {}

  /// Records that someone is here. Call on every pointer, key or touch.
  void touch() {
    _lastActivity = _clock();
    countdown._set(null);
  }

  /// Checks the idle clock once. The periodic timer calls this; a test can.
  Future<void> tick() async {
    if (state.value != DVKioskState.active) return;
    if (policy.onIdle == DVKioskIdleAction.none) return;
    final DateTime? last = _lastActivity;
    if (last == null) return;
    final Duration idle = _clock().difference(last);
    if (idle >= policy.idleTimeout) {
      countdown._set(null);
      if (policy.onIdle == DVKioskIdleAction.reset) {
        await reset(DVKioskResetReason.idle);
      } else {
        // Home only: nothing cleared, the clock restarts.
        touch();
        _resets.add(DVKioskReset(
          cleared: const <DVKioskClearable>{},
          home: policy.home,
          reason: DVKioskResetReason.idle,
        ));
      }
      return;
    }
    final Duration left = policy.idleTimeout - idle;
    countdown._set(left <= policy.idleWarning ? left : null);
  }

  /// Resets the session now: clears what the policy says, tells the app to
  /// go home, and starts the clock again. A clear that fails leaves the
  /// kiosk [DVKioskState.failed] and rethrows -- a half-cleared session
  /// presented as fresh is the one outcome worse than a visible failure.
  Future<DVKioskReset> reset(DVKioskResetReason reason) async {
    _enter(DVKioskState.resetting);
    countdown._set(null);
    try {
      if (policy.clearOnReset.isNotEmpty) await _clear(policy.clearOnReset);
    } catch (_) {
      _enter(DVKioskState.failed);
      rethrow;
    }
    final DVKioskReset result = DVKioskReset(
      cleared: Set<DVKioskClearable>.unmodifiable(policy.clearOnReset),
      home: policy.home,
      reason: reason,
    );
    touch();
    _enter(DVKioskState.active);
    _resets.add(result);
    return result;
  }

  /// Stops the idle clock. Call when the kiosk runtime is torn down.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  static Future<String?> _noSecrets(String name) async => null;

  /// Whether a lockout is still running.
  bool get isLockedOut {
    final DateTime? until = _lockedUntil;
    return until != null && _clock().isBefore(until);
  }

  /// Enters kiosk mode, or returns to it from staff mode.
  ///
  /// Does not clear a lockout. One that a resume could clear would stop
  /// nothing: the way out of a locked kiosk is to wait, or to be staff with
  /// the declared method.
  Future<void> resume() async {
    if (!policy.enabled) return;
    _enter(DVKioskState.active);
    touch();
    _timer ??= Timer.periodic(tickEvery, (_) => unawaited(tick()));
  }

  /// Attempts to leave kiosk mode.
  Future<DVKioskExitResult> exit(DVKioskExitRequest request) async {
    // A build with no kiosk policy has no kiosk runtime: the call exists,
    // reports, and changes nothing.
    if (!policy.enabled) {
      return const DVKioskExitResult(
        granted: false,
        message: 'This build declares no kiosk policy, so there is nothing to '
            'exit.',
        code: 'DV-KIOSK-005',
      );
    }

    if (isLockedOut) {
      return const DVKioskExitResult(
        granted: false,
        message: 'Too many attempts. Try again later.',
        code: 'DV-KIOSK-003',
      );
    }
    // The lockout has run out, so the next attempt starts clean.
    if (_lockedUntil != null) {
      _lockedUntil = null;
      _failedAttempts = 0;
      if (state.value == DVKioskState.locked) {
        _enter(DVKioskState.active);
      }
    }

    // The declared method is the only way out. Accepting a PIN against an
    // adminAuth policy would make the declaration advisory.
    final bool methodMatches = switch (policy.exitMethod) {
      DVKioskExitMethod.pin ||
      DVKioskExitMethod.gesturePin =>
        request.method == DVKioskExitMethod.pin,
      DVKioskExitMethod.adminAuth =>
        request.method == DVKioskExitMethod.adminAuth,
      DVKioskExitMethod.remote => request.method == DVKioskExitMethod.remote,
      DVKioskExitMethod.hardwareCombo => false,
      DVKioskExitMethod.none => false,
    };
    if (!methodMatches) {
      return const DVKioskExitResult(
        granted: false,
        message: 'That is not how this kiosk is left.',
      );
    }

    final bool ok = await _accepts(request);
    if (ok) {
      // Forgotten on success, or two wrong entries today and one tomorrow
      // lock a kiosk out for no reason anyone can see.
      _failedAttempts = 0;
      _lockedUntil = null;
      _enter(DVKioskState.staffMode);
      return const DVKioskExitResult(granted: true, message: 'Staff mode.');
    }

    _failedAttempts++;
    if (_failedAttempts >= policy.maxAttempts) {
      _lockedUntil = _clock().add(policy.lockoutFor);
      _enter(DVKioskState.locked);
      return const DVKioskExitResult(
        granted: false,
        message: 'Too many attempts. Try again later.',
        code: 'DV-KIOSK-003',
      );
    }
    // Never says what the right answer was, or how close this one came.
    return const DVKioskExitResult(
      granted: false,
      message: 'That did not work.',
    );
  }

  Future<bool> _accepts(DVKioskExitRequest request) async {
    switch (policy.exitMethod) {
      case DVKioskExitMethod.pin:
      case DVKioskExitMethod.gesturePin:
        final String? name = policy.exitPinSecret;
        if (name == null) return false;
        final String? expected = await _readSecret(name);
        if (expected == null || expected.isEmpty) return false;
        return _constantTimeEquals(expected, request.value);
      case DVKioskExitMethod.adminAuth:
      case DVKioskExitMethod.remote:
        // The caller has already authenticated; a non-empty token is what
        // reaches here.
        return request.value.isNotEmpty;
      case DVKioskExitMethod.hardwareCombo:
      case DVKioskExitMethod.none:
        return false;
    }
  }

  /// Compares without leaking length or position through timing.
  static bool _constantTimeEquals(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Clears the session and returns to `home`.
  ///
  /// Passes through [DVKioskState.resetting] so a workspace watching the
  /// signal can show that a wipe is happening rather than a flicker.
  Future<DVKioskReset> resetSession({
    required DVKioskResetReason reason,
  }) async {
    if (!policy.enabled) {
      return DVKioskReset(
        cleared: const <DVKioskClearable>{},
        home: policy.home,
        reason: reason,
      );
    }

    _enter(DVKioskState.resetting);
    final DVKioskReset reset = DVKioskReset(
      cleared: Set<DVKioskClearable>.unmodifiable(policy.clearOnReset),
      home: policy.home,
      reason: reason,
    );
    _enter(DVKioskState.active);
    return reset;
  }
}
