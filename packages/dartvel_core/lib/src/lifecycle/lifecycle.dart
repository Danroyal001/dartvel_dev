import 'dart:async';
import '../kiosk/runtime.dart' show DVKioskState;

/// Application-level lifecycle states.
enum DVAppLifecycle {
  uninitialized,
  initializing,
  booting,
  ready,
  backgrounded,
  suspended,
  resuming,
  shuttingDown,
  stopped,
  failed,
}

/// Page-level lifecycle states, observed through `context.lifecycle.page`.
enum DVPageLifecycle {
  created,
  resolving,
  loading,
  ready,
  entering,
  active,
  inactive,
  leaving,
  disposing,
  disposed,
  failed,
}

/// Module lifecycle states, observed through `DV.Modules.<id>.lifecycle`.
enum DVModuleLifecycle {
  discovered,
  resolving,
  validating,
  loading,
  loaded,
  mounting,
  mounted,
  active,
  suspended,
  unmounting,
  unloaded,
  failed,
}

/// Backend request lifecycle states, observed through
/// `context.lifecycle.request`.
enum DVRequestLifecycle {
  received,
  contextCreated,
  decoding,
  tenantResolving,
  tenantResolved,
  authenticating,
  authenticated,
  securityChecking,
  rateLimitChecking,
  validating,
  authorized,
  transactionStarting,
  executing,
  preparingResponse,
  committing,
  encoding,
  completed,
  cancelled,
  rollingBack,
  failed,
}

/// Transaction lifecycle states, observed through
/// `context.lifecycle.transaction`.
enum DVTransactionLifecycle {
  created,
  active,
  preparing,
  committing,
  committed,
  rollingBack,
  rolledBack,
  compensating,
  compensated,
  cancelled,
  failed,
}

/// Build pipeline lifecycle states, observed through `DV.lifecycle.build`.
enum DVBuildLifecycle {
  idle,
  scanning,
  analyzing,
  generating,
  validating,
  compiling,
  bundling,
  completed,
  failed,
}

/// A read-only reactive value.
///
/// Lifecycle state is owned by the framework: application code reads and
/// observes it but never assigns it, which is why this type exposes no setter.
/// The framework mutates it through [DVMutableLifecycleSignal].
///
/// This is deliberately not the widget-bound `DVSignal` from
/// `dartvel_flutter`: lifecycle exists on the server and during builds, where
/// there is no `BuildContext` to bind to.
abstract class DVLifecycleSignal<T> {
  /// The current state.
  T get value;

  /// The current state. Provided so reads look the same as elsewhere in
  /// Dartvel, where signals are read with `.read()`.
  T read();

  /// Emits on every transition. Does not replay the current value; read
  /// [value] for that.
  Stream<T> get changes;

  /// Observes transitions. Returns a subscription the caller can cancel.
  ///
  /// [onState] may be asynchronous; failures in a listener are isolated so one
  /// bad observer cannot derail a lifecycle transition.
  StreamSubscription<T> listen(FutureOr<void> Function(T state) onState);
}

/// The framework-facing half of a lifecycle signal.
///
/// Kept separate from [DVLifecycleSignal] so that handing a signal to
/// application code hands over no way to drive it.
class DVMutableLifecycleSignal<T> implements DVLifecycleSignal<T> {
  DVMutableLifecycleSignal(T initial) : _value = initial;

  T _value;
  final _controller = StreamController<T>.broadcast();

  @override
  T get value => _value;

  @override
  T read() => _value;

  @override
  Stream<T> get changes => _controller.stream;

  @override
  StreamSubscription<T> listen(FutureOr<void> Function(T state) onState) {
    return _controller.stream.listen((state) async {
      try {
        await onState(state);
      } catch (_) {
        // A failing observer must not break the transition for others.
      }
    });
  }

  /// Advances the state. Re-emitting the same state is a no-op, so observers
  /// only ever see genuine transitions.
  void set(T next) {
    if (_value == next) return;
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> dispose() => _controller.close();
}

/// The lifecycle signals reachable from `DV.lifecycle`.
class DVLifecycleRegistry {
  DVLifecycleRegistry();

  final _app = DVMutableLifecycleSignal<DVAppLifecycle>(
    DVAppLifecycle.uninitialized,
  );
  final _build = DVMutableLifecycleSignal<DVBuildLifecycle>(
    DVBuildLifecycle.idle,
  );
  final _kiosk = DVMutableLifecycleSignal<DVKioskState>(DVKioskState.off);

  /// Application lifecycle: `DV.lifecycle.app`.
  DVLifecycleSignal<DVAppLifecycle> get app => _app;

  /// Build pipeline lifecycle: `DV.lifecycle.build`.
  DVLifecycleSignal<DVBuildLifecycle> get build => _build;

  /// Framework-only: advances application state.
  void setApp(DVAppLifecycle state) => _app.set(state);

  /// Framework-only: advances build state.
  void setBuild(DVBuildLifecycle state) => _build.set(state);

  /// The kiosk's state -- off, active, staffMode, resetting, locked, failed
  /// -- as the runtime drives it. Reset shows as `resetting -> active`.
  DVLifecycleSignal<DVKioskState> get kiosk => _kiosk;

  void setKiosk(DVKioskState state) => _kiosk.set(state);

  /// Test-only: returns both signals to their initial states.
  void resetForTesting() {
    _app.set(DVAppLifecycle.uninitialized);
    _build.set(DVBuildLifecycle.idle);
    _kiosk.set(DVKioskState.off);
  }
}
