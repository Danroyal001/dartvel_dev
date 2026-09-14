/// What a web worker and its caller say to each other.
///
/// A web worker is a separately loaded script. It cannot be handed a Dart
/// function the way an isolate in the same group can -- only a message -- so
/// a task crosses by a name both sides registered, and its input and result
/// by structured clone, which copies and which refuses anything that is not
/// plain data. On the VM a class instance crosses an isolate boundary
/// without complaint; in a browser the same call throws a `DataCloneError`
/// naming nothing. The checks here turn that into a failure that names the
/// value and where it sits, and do it in Dart any target can test.
///
/// Platform-neutral on purpose: the Worker object is in `workers_web.dart`,
/// and everything that decides what happens is here.
library dartvel.compute.web_worker_protocol;

import 'dart:async';
import 'dart:typed_data';

import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'worker_types.dart';

/// Tasks a web worker can be asked to run, by name.
///
/// The page and the worker script each register the same names. The page
/// looks a function up to find the name to send; the worker looks the name
/// up to find the function. Top-level and static tear-offs are canonical, so
/// the function itself is a reliable key on both.
final class DVWorkerTasks {
  const DVWorkerTasks._();

  static final Map<String, DVWorkerCall<Object?, Object?>> _byName =
      <String, DVWorkerCall<Object?, Object?>>{};
  static final Map<Function, String> _byTask = <Function, String>{};

  /// Where the page loads the worker script from: the compiled output of an
  /// entry that registers the same tasks and calls `dvWebWorkerMain`.
  static String script = 'dv_worker.dart.js';

  static void register<I, O>(String name, DVWorkerTask<I, O> task) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a task needs a name');
    }
    final String? existing = _byTask[task];
    if (existing == name) return;
    if (_byName.containsKey(name) || existing != null) {
      throw StateError('Worker task "$name" is already registered for a '
          'different function. A worker is handed a name, so one name must '
          'mean one function on both sides.');
    }
    _byName[name] = DVWorkerCall<I, O>(task);
    _byTask[task] = name;
  }

  static String? nameOf(Function task) => _byTask[task];

  static DVWorkerCall<Object?, Object?>? lookup(String name) => _byName[name];

  static void debugClear() {
    _byName.clear();
    _byTask.clear();
  }
}

/// Where the first value structured clone would refuse sits, and what it is;
/// null when [value] can be handed to a web worker.
///
/// Stricter than the browser in one place: a map must be keyed by strings,
/// because a Dart map crosses as a JavaScript object and a non-string key
/// does not survive the round trip as itself.
String? dvWorkerUnportable(Object? value, [String path = r'$']) {
  switch (value) {
    case null || bool() || num() || String() || TypedData() || ByteBuffer():
      return null;
    case List<Object?>():
      for (var i = 0; i < value.length; i++) {
        final String? found = dvWorkerUnportable(value[i], '$path[$i]');
        if (found != null) return found;
      }
      return null;
    case Map<Object?, Object?>():
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        if (entry.key is! String) {
          return '$path has a key of type ${entry.key.runtimeType}; a worker '
              'message is keyed by strings';
        }
        final String? found =
            dvWorkerUnportable(entry.value, '$path.${entry.key}');
        if (found != null) return found;
      }
      return null;
    default:
      return '$path is a ${value.runtimeType}, which a web worker cannot be '
          'handed; pass plain data (null, bool, num, String, typed data, '
          'lists, string-keyed maps)';
  }
}

/// A request from the page.
final class DVWorkerRequest {
  const DVWorkerRequest({
    required this.id,
    required this.task,
    required this.input,
  });

  final int id;
  final String task;
  final Object? input;

  Map<String, Object?> toMessage() =>
      <String, Object?>{'id': id, 'task': task, 'input': input};
}

enum DVWorkerResponseKind { progress, done, failed }

/// A message from the worker.
final class DVWorkerResponse {
  const DVWorkerResponse({
    required this.id,
    required this.kind,
    this.fraction,
    this.message,
    this.value,
    this.failureKind,
    this.error,
    this.stack,
  });

  factory DVWorkerResponse.fromMessage(Map<Object?, Object?> message) {
    final Object? id = message['id'];
    final DVWorkerResponseKind? kind = DVWorkerResponseKind.values
        .where((DVWorkerResponseKind k) => k.name == message['kind'])
        .firstOrNull;
    if (kind == null) {
      return DVWorkerResponse(
        id: id is num ? id.toInt() : -1,
        kind: DVWorkerResponseKind.failed,
        failureKind: DVWorkerFailureKind.crashed,
        error: 'the worker sent a message this page does not understand',
      );
    }
    final Object? fraction = message['fraction'];
    return DVWorkerResponse(
      id: id is num ? id.toInt() : -1,
      kind: kind,
      fraction: fraction is num ? fraction.toDouble() : null,
      message: message['message'] as String?,
      value: message['value'],
      failureKind: DVWorkerFailureKind.values
          .where((DVWorkerFailureKind k) => k.name == message['failure'])
          .firstOrNull,
      error: message['error'] as String?,
      stack: message['stack'] as String?,
    );
  }

  final int id;
  final DVWorkerResponseKind kind;
  final double? fraction;
  final String? message;
  final Object? value;
  final DVWorkerFailureKind? failureKind;
  final String? error;
  final String? stack;

  /// What the page's pool is told.
  DVWorkerFailure get failure => DVWorkerFailure(
        failureKind ?? DVWorkerFailureKind.crashed,
        error ?? 'the worker failed without saying why',
      );
}

/// Runs one request inside a worker, posting what happens through [post].
///
/// Always posts a final `done` or `failed`, whatever the request looked
/// like, so a page never waits on a request the worker could not read.
Future<void> dvWorkerHandle(
  Map<Object?, Object?> request,
  void Function(Map<String, Object?> message) post,
) async {
  final Object? rawId = request['id'];
  final int id = rawId is num ? rawId.toInt() : -1;
  final Object? name = request['task'];

  void fail(DVWorkerFailureKind kind, String error, [String? stack]) =>
      post(<String, Object?>{
        'id': id,
        'kind': DVWorkerResponseKind.failed.name,
        'failure': kind.name,
        'error': error,
        'stack': stack,
      });

  if (name is! String) {
    fail(DVWorkerFailureKind.crashed, 'the request named no task');
    return;
  }
  final DVWorkerCall<Object?, Object?>? call = DVWorkerTasks.lookup(name);
  if (call == null) {
    fail(
      DVWorkerFailureKind.unsendableTask,
      'the worker has no task registered as "$name"; register it with '
      'DVWorkerTasks in the worker entry as well as in the page',
    );
    return;
  }

  final Object? value;
  try {
    value = await call.invoke(request['input'], _PostingReporter(id, post));
  } on Object catch (error, stackTrace) {
    fail(DVWorkerFailureKind.threw, '${error.runtimeType}: $error',
        stackTrace.toString());
    return;
  }
  final String? unportable = dvWorkerUnportable(value);
  if (unportable != null) {
    fail(DVWorkerFailureKind.unsendableResult,
        'the result cannot cross back from the worker: $unportable');
    return;
  }
  post(<String, Object?>{
    'id': id,
    'kind': DVWorkerResponseKind.done.name,
    'value': value,
  });
}

final class _PostingReporter implements DVWorkerReporter {
  const _PostingReporter(this.id, this.post);
  final int id;
  final void Function(Map<String, Object?>) post;

  @override
  void progress(double fraction, {String? message}) {
    dvCheckedProgress(fraction, message);
    post(<String, Object?>{
      'id': id,
      'kind': DVWorkerResponseKind.progress.name,
      'fraction': fraction,
      'message': message,
    });
  }

  // A cancelled web worker is terminated, so it never observes cancellation.
  @override
  bool get isCancelled => false;
}

/// What a browser's workers are.
DVWorkerCapability dvWebWorkerCapability({
  required bool hasWorker,
  required bool crossOriginIsolated,
}) {
  if (!hasWorker) return const DVWorkerCapability.inline();
  return DVWorkerCapability(
    mechanism: DVWorkerMechanism.webWorker,
    // SharedArrayBuffer exists only on a cross-origin-isolated page.
    sharedMemory: crossOriginIsolated,
    zeroCopyNative: false,
    note: crossOriginIsolated
        ? 'input crosses by structured clone; a SharedArrayBuffer is shared'
        : 'input is copied to the worker by structured clone; shared memory '
            'needs a cross-origin-isolated page (COOP and COEP headers)',
  );
}

bool _copiedReported = false;

/// `DV-WORKER-004`, once: bytes were copied to a worker because this page
/// cannot share memory.
///
/// Only for bytes. Copying a small map is not the performance surprise the
/// diagnostic is for; copying a buffer somebody designed to share is.
void dvReportCopiedInput(DVWorkerCapability capability, Object? input) {
  if (_copiedReported ||
      capability.mechanism != DVWorkerMechanism.webWorker ||
      capability.sharedMemory ||
      !_holdsBytes(input)) {
    return;
  }
  _copiedReported = true;
  DVObservability.log(
    'Shared memory is unavailable; input was copied to the worker.',
    level: DVLogLevel.info,
    code: 'DV-WORKER-004',
  );
}

void dvDebugResetCopiedReport() => _copiedReported = false;

bool _holdsBytes(Object? value) => switch (value) {
      TypedData() || ByteBuffer() => true,
      List<Object?>() => value.any(_holdsBytes),
      Map<Object?, Object?>() => value.values.any(_holdsBytes),
      _ => false,
    };
