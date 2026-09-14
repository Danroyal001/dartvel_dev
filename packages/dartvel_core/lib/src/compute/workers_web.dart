/// Workers in a browser: one web worker per task.
///
/// Spawned per task and terminated when it answers, for the same reason the
/// VM spawns an isolate per task: `terminate()` is the only cancellation a
/// busy worker cannot ignore, and a worker kept warm would have to be asked.
///
/// A web worker shares nothing with the page, so a terminated worker holds
/// nothing the page can race on; it is reported exited as soon as it is
/// terminated.
library dartvel.compute.workers_web;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_worker_protocol.dart';
import 'worker_types.dart';

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url);
  external void postMessage(JSAny? message);
  external void terminate();
  external set onmessage(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

extension type _ErrorEvent._(JSObject _) implements JSObject {
  external JSString? get message;
  external void preventDefault();
}

DVWorkerRunner? dvHostWorkerRunner() {
  final DVWorkerCapability capability = dvWebWorkerCapability(
    hasWorker: globalContext.has('Worker'),
    crossOriginIsolated:
        (globalContext['crossOriginIsolated'] as JSBoolean?)?.toDart ?? false,
  );
  return capability.mechanism == DVWorkerMechanism.webWorker
      ? _WebWorkerRunner(capability)
      : null;
}

int dvHostProcessors() {
  final JSObject? navigator = globalContext['navigator'] as JSObject?;
  final JSNumber? cores = navigator?['hardwareConcurrency'] as JSNumber?;
  return cores == null ? 1 : cores.toDartInt.clamp(1, 1024);
}

int _nextId = 0;

final class _WebWorkerRunner implements DVWorkerRunner {
  const _WebWorkerRunner(this.capability);

  @override
  final DVWorkerCapability capability;

  @override
  DVWorkerExecution start(
      DVWorkerCall<Object?, Object?> call, Object? input, DVWorkerSink sink) {
    final _WebExecution execution = _WebExecution(sink);
    final String? name = DVWorkerTasks.nameOf(call.function);
    final String? unportable = dvWorkerUnportable(input);
    if (name == null) {
      execution.refuse(const DVWorkerFailure(
        DVWorkerFailureKind.unsendableTask,
        'a web worker is handed a task by name, and this one is not '
        'registered; register it with DVWorkerTasks in the page and in the '
        'worker entry',
      ));
    } else if (unportable != null) {
      execution.refuse(DVWorkerFailure(
        DVWorkerFailureKind.unsendableInput,
        'the input cannot be handed to a web worker: $unportable',
      ));
    } else {
      dvReportCopiedInput(capability, input);
      execution.begin(
          DVWorkerRequest(id: _nextId++, task: name, input: input));
    }
    return execution;
  }
}

final class _WebExecution implements DVWorkerExecution {
  _WebExecution(this.sink);

  final DVWorkerSink sink;
  _Worker? _worker;
  bool _ended = false;

  /// Answered on a later microtask, never inside start(): the pool has not
  /// recorded the execution yet, and releasing a slot from inside the loop
  /// that is filling slots would re-enter it.
  void refuse(DVWorkerFailure failure) {
    scheduleMicrotask(() {
      sink.failed(failure, null);
      _end();
    });
  }

  void begin(DVWorkerRequest request) {
    final _Worker worker;
    try {
      worker = _Worker(DVWorkerTasks.script.toJS);
    } on Object catch (error) {
      refuse(DVWorkerFailure(DVWorkerFailureKind.crashed,
          'the worker script ${DVWorkerTasks.script} could not be started: '
          '$error'));
      return;
    }
    _worker = worker;
    worker.onmessage = ((_MessageEvent event) {
      if (_ended) return;
      final Object? data = event.data.dartify();
      if (data is! Map) {
        sink.failed(
            const DVWorkerFailure(DVWorkerFailureKind.crashed,
                'the worker sent something that is not a response'),
            null);
        _end();
        return;
      }
      final DVWorkerResponse response = DVWorkerResponse.fromMessage(data);
      switch (response.kind) {
        case DVWorkerResponseKind.progress:
          sink.progress(DVProgress(response.fraction ?? 0,
              message: response.message));
        case DVWorkerResponseKind.done:
          sink.completed(response.value);
          _end();
        case DVWorkerResponseKind.failed:
          sink.failed(
            response.failure,
            response.stack == null
                ? null
                : StackTrace.fromString(response.stack!),
          );
          _end();
      }
    }).toJS;
    // A script that fails to load, or an error nothing in the worker caught,
    // arrives here. Without it the page would wait for an answer from a
    // worker that no longer exists.
    worker.onerror = ((_ErrorEvent event) {
      event.preventDefault();
      if (_ended) return;
      sink.failed(
        DVWorkerFailure(DVWorkerFailureKind.crashed,
            'the worker died: ${event.message?.toDart ?? 'no message'}'),
        null,
      );
      _end();
    }).toJS;
    worker.postMessage(request.toMessage().jsify());
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _worker?.terminate();
    _worker = null;
    sink.exited();
  }

  @override
  void stop() => _end();
}
