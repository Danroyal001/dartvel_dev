/// Workers on the Dart VM: one isolate per task, in the caller's isolate
/// group.
///
/// An isolate is spawned for each task rather than kept warm. Isolates in a
/// group spawn in about a millisecond, and a fresh one is the only way
/// cancellation can be honest: `Isolate.kill` ends a busy loop at its next
/// safepoint, where a reused isolate would have to be asked to stop and
/// would go on charging until it looked.
library dartvel.compute.workers_isolate;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'worker_types.dart';

DVWorkerRunner? dvHostWorkerRunner() => const _IsolateRunner();

int dvHostProcessors() => Platform.numberOfProcessors;

final class _IsolateRunner implements DVWorkerRunner {
  const _IsolateRunner();

  @override
  DVWorkerCapability get capability => const DVWorkerCapability.isolate();

  @override
  DVWorkerExecution start(
      DVWorkerCall<Object?, Object?> call, Object? input, DVWorkerSink sink) {
    final _IsolateExecution execution = _IsolateExecution(sink);
    unawaited(execution.begin(call, input));
    return execution;
  }
}

final class _IsolateExecution implements DVWorkerExecution {
  _IsolateExecution(this.sink);

  final DVWorkerSink sink;
  final RawReceivePort _port = RawReceivePort();
  Isolate? _isolate;
  bool _stopped = false;
  bool _exited = false;

  Future<void> begin(DVWorkerCall<Object?, Object?> call, Object? input) async {
    _port.handler = _receive;
    try {
      _isolate = await Isolate.spawn<_Start>(
        _workerMain,
        _Start(call, input, _port.sendPort),
        // Both land on the same port as the task's own messages, and after
        // them, so a worker that dies silently still produces a message.
        onExit: _port.sendPort,
        onError: _port.sendPort,
        errorsAreFatal: true,
        debugName: 'dv-worker',
      );
    } on Object catch (error, stackTrace) {
      sink.failed(_diagnoseUnsendable(call, input, error), stackTrace);
      _exit();
      return;
    }
    // Cancelled while the spawn was in flight.
    if (_stopped) _isolate!.kill(priority: Isolate.immediate);
  }

  void _receive(Object? message) {
    switch (message) {
      case _Progress(:final double fraction, :final String? text):
        sink.progress(DVProgress(fraction, message: text));
      case _Done(:final Object? value):
        sink.completed(value);
      case _Failed(:final Object error, :final String stack):
        sink.failed(error, StackTrace.fromString(stack));
      case [final Object? error, final Object? stack]:
        // What onError sends: an uncaught error that ended the isolate.
        sink.failed(
          DVWorkerFailure(DVWorkerFailureKind.crashed,
              'the worker died of an uncaught error: $error'),
          stack == null ? null : StackTrace.fromString('$stack'),
        );
      case null:
        _exit();
    }
  }

  void _exit() {
    if (_exited) return;
    _exited = true;
    _port.close();
    sink.exited();
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _isolate?.kill(priority: Isolate.immediate);
  }
}

/// Which half of the spawn message could not be sent.
///
/// Only reached after a spawn has already failed, so probing costs nothing
/// on the path that works. A send to a port in this isolate checks
/// sendability the same way a send to another one does.
DVWorkerFailure _diagnoseUnsendable(
    DVWorkerCall<Object?, Object?> call, Object? input, Object error) {
  if (!_sendable(call)) {
    return DVWorkerFailure(
      DVWorkerFailureKind.unsendableTask,
      'the task captured state it cannot send; make it top-level or static '
      '($error)',
      code: 'DV-WORKER-002',
    );
  }
  if (!_sendable(input)) {
    return DVWorkerFailure(
      DVWorkerFailureKind.unsendableInput,
      'input of type ${input.runtimeType} cannot cross to a worker ($error)',
    );
  }
  return DVWorkerFailure(
      DVWorkerFailureKind.crashed, 'the worker could not be started: $error');
}

bool _sendable(Object? value) {
  final RawReceivePort probe = RawReceivePort();
  try {
    probe.sendPort.send(value);
    return true;
  } on Object {
    return false;
  } finally {
    probe.close();
  }
}

// ---------------------------------------------------------------------------
// Messages. Classes rather than tagged lists: isolates in one group share
// class identity, and a pattern on a type cannot be misspelt.
// ---------------------------------------------------------------------------

final class _Start {
  const _Start(this.call, this.input, this.port);
  final DVWorkerCall<Object?, Object?> call;
  final Object? input;
  final SendPort port;
}

final class _Progress {
  const _Progress(this.fraction, this.text);
  final double fraction;
  final String? text;
}

final class _Done {
  const _Done(this.value);
  final Object? value;
}

final class _Failed {
  const _Failed(this.error, this.stack);
  final Object error;
  final String stack;
}

final class _PortReporter implements DVWorkerReporter {
  const _PortReporter(this.port);
  final SendPort port;

  @override
  void progress(double fraction, {String? message}) {
    dvCheckedProgress(fraction, message);
    port.send(_Progress(fraction, message));
  }

  // A cancelled worker is killed, so it never observes its cancellation.
  @override
  bool get isCancelled => false;
}

Future<void> _workerMain(_Start start) async {
  final SendPort port = start.port;
  final Object? value;
  try {
    value = await start.call.invoke(start.input, _PortReporter(port));
  } on Object catch (error, stackTrace) {
    try {
      port.send(_Failed(error, stackTrace.toString()));
    } on Object {
      // What was thrown cannot cross; say what it was instead.
      port.send(_Failed(
        DVWorkerFailure(DVWorkerFailureKind.threw,
            '${error.runtimeType}: $error'),
        stackTrace.toString(),
      ));
    }
    Isolate.exit();
  }
  try {
    // Isolate.exit hands the result over without copying it.
    Isolate.exit(port, _Done(value));
  } on Object catch (error, stackTrace) {
    // It throws rather than exiting when the result cannot be sent, and an
    // isolate left with a port open would otherwise never end.
    port.send(_Failed(
      DVWorkerFailure(
        DVWorkerFailureKind.unsendableResult,
        'the result of type ${value.runtimeType} cannot cross back from the '
        'worker ($error)',
      ),
      stackTrace.toString(),
    ));
    Isolate.exit();
  }
}
