import 'dart:async';

import '../lifecycle/lifecycle.dart';

/// Lifecycle signals scoped to a single context.
class DVContextLifecycle {
  DVContextLifecycle({
    DVMutableLifecycleSignal<DVTransactionLifecycle>? transaction,
    DVMutableLifecycleSignal<DVRequestLifecycle>? request,
    DVMutableLifecycleSignal<DVPageLifecycle>? page,
  })  : _transaction = transaction,
        _request = request,
        _page = page;

  final DVMutableLifecycleSignal<DVTransactionLifecycle>? _transaction;
  final DVMutableLifecycleSignal<DVRequestLifecycle>? _request;
  final DVMutableLifecycleSignal<DVPageLifecycle>? _page;

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
  })  : _parent = parent,
        lifecycle = DVContextLifecycle(
          transaction: transactionLifecycle,
          request: requestLifecycle,
          page: pageLifecycle,
        );

  /// The enclosing context when transactions are nested.
  final DVContext? _parent;

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

  /// The transaction currently in progress on this zone, if any.
  static DVContext? _active;

  /// The context of the transaction in progress, or null outside one.
  static DVContext? get activeContext => _active;

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
    final parent = isolated ? null : _active;

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

    final previous = _active;
    _active = context;
    signal.set(DVTransactionLifecycle.active);

    try {
      final result = await body(context);

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
    } finally {
      _active = previous;
    }
  }
}
