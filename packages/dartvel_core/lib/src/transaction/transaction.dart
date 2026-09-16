import 'dart:async';
import 'dart:math' as math;

import '../auth/api_scopes.dart' show DVApiPrincipal;
import '../auth/session_authentication.dart' show DVSessionPrincipal;
import '../lifecycle/lifecycle.dart';

/// Lifecycle signals scoped to a single context.
class DVContextLifecycle {
  /// Read-only signals, because this class only ever reads them.
  ///
  /// It used to require the mutable type, which meant anything holding a
  /// read-only signal -- the page scope, whose whole point is that the
  /// application cannot move it -- could not build one of these. Widening
  /// the parameter breaks no caller: every mutable signal is a read-only
  /// one.
  DVContextLifecycle({
    DVLifecycleSignal<DVTransactionLifecycle>? transaction,
    DVLifecycleSignal<DVRequestLifecycle>? request,
    DVLifecycleSignal<DVPageLifecycle>? page,
  })  : _transaction = transaction,
        _request = request,
        _page = page;

  final DVLifecycleSignal<DVTransactionLifecycle>? _transaction;
  final DVLifecycleSignal<DVRequestLifecycle>? _request;
  final DVLifecycleSignal<DVPageLifecycle>? _page;

  /// `context.lifecycle.transaction` — only inside a [DV.transaction].
  DVLifecycleSignal<DVTransactionLifecycle> get transaction {
    final signal = _transaction;
    if (signal == null) {
      throw StateError(
        'context.lifecycle.transaction is only available inside '
        'DV.transaction(...).',
      );
    }
    return signal;
  }

  /// `context.lifecycle.request` — only inside a backend function.
  DVLifecycleSignal<DVRequestLifecycle> get request {
    final signal = _request;
    if (signal == null) {
      throw StateError(
        'context.lifecycle.request is only available inside a backend '
        'function.',
      );
    }
    return signal;
  }

  /// `context.lifecycle.page` — only inside a page.
  DVLifecycleSignal<DVPageLifecycle> get page {
    final signal = _page;
    if (signal == null) {
      throw StateError(
        'context.lifecycle.page is only available inside a page.',
      );
    }
    return signal;
  }
}

/// Thrown when a compensation handler itself fails during rollback.
///
/// Carries both the original failure and the compensation failures, because
/// losing the original cause is what makes these incidents hard to debug.
class DVCompensationException implements Exception {
  DVCompensationException({
    required this.cause,
    required this.compensationErrors,
  });

  /// The error that triggered the rollback.
  final Object cause;

  /// Errors thrown by compensation handlers, in the order they ran.
  final List<Object> compensationErrors;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('DVCompensationException: rollback did not fully succeed.')
      ..writeln('  Original failure: $cause');
    for (final error in compensationErrors) {
      buffer.writeln('  Compensation failure: $error');
    }
    return buffer.toString();
  }
}

/// The context handed to a [DV.transaction] body and to backend functions.
///
/// A backend function whose first parameter is a `DVContext` receives it by
/// injection; it is not a client-supplied argument.
class DVContext {
  DVContext({
    DVMutableLifecycleSignal<DVTransactionLifecycle>? transactionLifecycle,
    DVMutableLifecycleSignal<DVRequestLifecycle>? requestLifecycle,
    DVMutableLifecycleSignal<DVPageLifecycle>? pageLifecycle,
    DVContext? parent,
    DVSessionPrincipal? session,
    DVApiPrincipal? apiPrincipal,
  })  : _parent = parent,
        _id = parent == null ? _dvNewTransactionId() : '',
        session = session ?? parent?.session ?? DVSessionPrincipal.current,
        apiPrincipal =
            apiPrincipal ?? parent?.apiPrincipal ?? DVApiPrincipal.current,
        lifecycle = DVContextLifecycle(
          transaction: transactionLifecycle,
          request: requestLifecycle,
          page: pageLifecycle,
        );

  /// The signed-in person the request authenticated with the application's
  /// own session, or null.
  ///
  /// Taken when the context is made -- which, for an injected context, is
  /// inside the request's authentication stage -- so work the function hands
  /// on keeps the caller it was started by.
  final DVSessionPrincipal? session;

  /// The third-party caller the request authenticated with an API key or an
  /// OAuth token, or null.
  final DVApiPrincipal? apiPrincipal;

  /// The application's user the session resolved to on this request, or
  /// null for a request with no session or an application that resolves no
  /// user.
  Object? get user => session?.user;

  /// The enclosing context when transactions are nested.
  final DVContext? _parent;

  /// This transaction's identifier, held by the outermost context.
  final String _id;

  /// The identifier of the unit of work this context belongs to.
  ///
  /// The same for every context in one transaction -- a nested call joins the
  /// outer one -- and different between two, so a change recorded with it can
  /// be traced back to the unit of work that made it. Record history stores it
  /// on every entry.
  String get transactionId => _root._id;

  /// Lifecycle signals scoped to this context.
  final DVContextLifecycle lifecycle;

  final _afterCommit = <FutureOr<void> Function()>[];
  final _compensations = <FutureOr<void> Function()>[];

  /// Whether this context is nested inside another transaction.
  bool get isNested => _parent != null;

  /// Registers work to run only after the transaction commits.
  ///
  /// This is where irreversible effects belong — email, SMS, webhooks, settled
  /// payments — because a rollback must not leave them already sent.
  ///
  /// In a nested transaction the callback is deferred to the outermost
  /// transaction, so it fires once, after the whole unit of work commits.
  void afterCommit(FutureOr<void> Function() callback) {
    final target = _root;
    target._afterCommit.add(callback);
  }

  /// Registers the inverse of an external effect that Dartvel cannot reverse
  /// on its own — refunding a charge, deleting a remote record.
  ///
  /// Compensations run in reverse registration order, so each one undoes its
  /// effect while the effects it depended on are still in place.
  void compensate(FutureOr<void> Function() callback) {
    final target = _root;
    target._compensations.add(callback);
  }

  DVContext get _root {
    var context = this;
    for (var parent = context._parent; parent != null; parent = context._parent) {
      context = parent;
    }
    return context;
  }

  /// Registered after-commit callbacks, in registration order.
  List<FutureOr<void> Function()> get pendingAfterCommit =>
      List.unmodifiable(_afterCommit);

  /// Registered compensations, in registration order.
  List<FutureOr<void> Function()> get pendingCompensations =>
      List.unmodifiable(_compensations);
}

/// Runs reversible units of work.
///
/// Exposed to application code as `DV.transaction(...)`.
class DVTransactionRunner {
  DVTransactionRunner();

  /// The zone value key under which a transaction body finds its transaction.
  ///
  /// The active transaction used to be a static field, so it belonged to the
  /// isolate rather than to the flow that opened it. Two requests served by
  /// one isolate interleave at every await, and each would find the other's
  /// transaction: a DV.transaction in one joined the other's, one request's
  /// failure ran the other's compensations, and after-commit work fired on
  /// the wrong commit. A zone value follows the body through every await,
  /// timer and microtask it schedules, and no further.
  static final Object _zoneKey = Object();

  /// The context of the transaction in progress on this flow, or null
  /// outside one.
  ///
  /// Null once that transaction has committed or rolled back, even to work
  /// the body scheduled and did not await: that work runs after the unit of
  /// work is over, and joining it would attach compensations nothing runs.
  static DVContext? get activeContext {
    final Object? scope = Zone.current[_zoneKey];
    return scope is _DVTransactionScope && scope.open ? scope.context : null;
  }

  /// Runs [body] as a transaction.
  ///
  /// On success, `afterCommit` callbacks run. On failure, compensations run in
  /// reverse order and the original error is rethrown — a rollback reverses
  /// work, it does not swallow the reason for it.
  ///
  /// Nested calls join the active transaction by default, so their
  /// compensations and after-commit callbacks resolve with the outermost one.
  /// Pass `isolated: true` for an independent transaction.
  Future<T> call<T>(
    FutureOr<T> Function(DVContext context) body, {
    bool isolated = false,
  }) async {
    final parent = isolated ? null : activeContext;

    if (parent != null) {
      // Joining: the outer transaction owns commit and rollback, so the body
      // runs against a child context and simply propagates failure.
      final child = DVContext(
        transactionLifecycle: DVMutableLifecycleSignal<DVTransactionLifecycle>(
          DVTransactionLifecycle.active,
        ),
        parent: parent,
      );
      return await body(child);
    }

    final signal = DVMutableLifecycleSignal<DVTransactionLifecycle>(
      DVTransactionLifecycle.created,
    );
    final context = DVContext(transactionLifecycle: signal);

    final scope = _DVTransactionScope(context);
    signal.set(DVTransactionLifecycle.active);

    try {
      final T result;
      try {
        // Only the body runs in the transaction's zone. After-commit work and
        // compensations run in the caller's, outside the transaction, so a
        // DV.transaction they open is a new one rather than a join onto a
        // unit of work that is already over.
        result = await runZoned(
          () => body(context),
          zoneValues: <Object, Object>{_zoneKey: scope},
        );
      } finally {
        scope.open = false;
      }

      signal.set(DVTransactionLifecycle.preparing);
      signal.set(DVTransactionLifecycle.committing);
      signal.set(DVTransactionLifecycle.committed);

      // After-commit effects run outside the transaction. A failure here
      // cannot roll back an already-committed transaction, so it surfaces
      // rather than triggering compensation.
      for (final callback in context.pendingAfterCommit) {
        await callback();
      }

      return result;
    } catch (error) {
      signal.set(DVTransactionLifecycle.rollingBack);

      final compensations = context.pendingCompensations.reversed.toList();
      final failures = <Object>[];

      if (compensations.isNotEmpty) {
        signal.set(DVTransactionLifecycle.compensating);
        for (final compensate in compensations) {
          try {
            await compensate();
          } catch (compensationError) {
            // Keep going: a later compensation may still undo real damage.
            failures.add(compensationError);
          }
        }
      }

      if (failures.isNotEmpty) {
        signal.set(DVTransactionLifecycle.failed);
        throw DVCompensationException(
          cause: error,
          compensationErrors: failures,
        );
      }

      signal.set(
        compensations.isEmpty
            ? DVTransactionLifecycle.rolledBack
            : DVTransactionLifecycle.compensated,
      );
      rethrow;
    }
  }
}

/// Runs the after-commit work [context] collected, in the order it was added.
///
/// For a context handed to a backend function, which is made per request and
/// is not a [DVTransactionRunner] transaction: the generated handler calls
/// this once the function has returned, so `afterCommit` there means what it
/// means inside `DV.transaction`.
Future<void> dvCommitContext(DVContext context) async {
  for (final FutureOr<void> Function() callback in context.pendingAfterCommit) {
    await callback();
  }
}

/// Runs [context]'s compensations in reverse order, going on past a failure,
/// and returns the failures. The generated handler calls it when a backend
/// function that was handed [context] throws.
Future<List<Object>> dvCompensateContext(DVContext context) async {
  final List<Object> failures = <Object>[];
  for (final FutureOr<void> Function() compensate
      in context.pendingCompensations.reversed) {
    try {
      await compensate();
    } catch (error) {
      failures.add(error);
    }
  }
  return failures;
}

/// What a transaction's zone carries: its context, and whether it is still
/// open to the work that finds it there.
class _DVTransactionScope {
  _DVTransactionScope(this.context);

  final DVContext context;
  bool open = true;
}

int _dvTransactionCounter = 0;

/// A process-unique transaction identifier: a timestamp, a counter and a
/// random suffix, so two transactions started in the same microsecond still
/// differ and two processes are unlikely to collide.
String _dvNewTransactionId() {
  _dvTransactionCounter = (_dvTransactionCounter + 1) & 0xFFFFFF;
  final int now = DateTime.now().microsecondsSinceEpoch;
  final int noise = _dvTransactionRandom.nextInt(0x7FFFFFFF);
  return 'tx-${now.toRadixString(36)}-'
      '${_dvTransactionCounter.toRadixString(36)}-${noise.toRadixString(36)}';
}

final math.Random _dvTransactionRandom = math.Random();
