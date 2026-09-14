/// `DV.Platform.Media.recordAudio(...)` and `recordVideo(...)`.
library;

import 'dart:async';

import '../lifecycle/lifecycle.dart';
import '../storage/file.dart';
import 'capture_backend.dart';
import 'media_controller.dart' show dvLogMediaDiagnostic;
import 'media_signal.dart';

/// Where a capture session is.
enum DVCaptureState {
  /// Checking the capability report.
  checking,
  requestingPermission,

  /// Asked the device to open; it has not confirmed.
  starting,

  /// The device confirmed it is recording.
  recording,

  /// Asked the device to stop; it has not confirmed.
  stopping,
  completed,

  /// The person said no.
  refused,

  /// Stopped by something other than the application: see
  /// [DVCaptureInterruption].
  interrupted,
  failed,
  disposed,
}

/// Why a recording stopped before the application stopped it.
enum DVCaptureInterruption {
  backgrounded,
  permissionRevoked,
  deviceLost,

  /// The session was disposed before the recording finished.
  disposed,
}

/// The person refused a capture permission.
final class DVCapturePermissionRefused implements Exception {
  const DVCapturePermissionRefused(this.permission);
  final String permission;

  @override
  String toString() =>
      'DVCapturePermissionRefused: $permission was refused (DV-MEDIA-104)';
}

/// The target cannot record what was asked for.
final class DVCaptureUnsupported implements Exception {
  const DVCaptureUnsupported(this.reason);
  final String reason;

  @override
  String toString() => 'DVCaptureUnsupported: $reason';
}

/// Another recording already holds the device.
final class DVCaptureBusy implements Exception {
  const DVCaptureBusy();

  @override
  String toString() => 'DVCaptureBusy: a recording is already running';
}

/// Recording stopped before the application stopped it. [partial] is what was
/// recorded up to then, still private, when there is any.
final class DVCaptureInterrupted implements Exception {
  const DVCaptureInterrupted(this.reason, this.partial);
  final DVCaptureInterruption reason;
  final DVFile? partial;

  @override
  String toString() => 'DVCaptureInterrupted: ${reason.name}';
}

/// The device failed.
final class DVCaptureFailure implements Exception {
  const DVCaptureFailure(this.message);
  final String message;

  @override
  String toString() => 'DVCaptureFailure: $message';
}

/// One recording.
///
/// Awaiting it gives the finished [DVFile]; holding it gives [stop], [dispose]
/// and the signals. Both, so `await DV.Platform.Media.recordAudio(...)` reads
/// as the specification writes it and a recording can still be stopped early.
///
/// A recording that nothing awaits does not raise an unhandled error when it
/// is refused or interrupted: [state] carries that, and the `DV-MEDIA-104`
/// diagnostic is still logged.
final class DVCaptureSession implements Future<DVFile> {
  DVCaptureSession._(this._runtime, this.request) {
    _completer.future.ignore();
  }

  final DVMediaCapture _runtime;

  /// What was asked for.
  final DVCaptureRequest request;

  final Completer<DVFile> _completer = Completer<DVFile>();
  final DVMutableMediaSignal<DVCaptureState> _state =
      DVMutableMediaSignal<DVCaptureState>(DVCaptureState.checking);
  final DVMutableMediaSignal<bool> _capturing =
      DVMutableMediaSignal<bool>(false);

  DVCaptureBackend? _backend;
  StreamSubscription<DVCaptureBackendEvent>? _events;
  StreamSubscription<DVAppLifecycle>? _lifecycle;
  DVMediaTimer? _limit;
  String? _path;
  DVCaptureInterruption? _interruption;
  bool _stopWhenStarted = false;
  bool _disposed = false;

  DVMediaSignal<DVCaptureState> get state => _state;

  /// Whether the device is open. Moved only by what the device reports, so a
  /// recording indicator bound to it cannot say "off" while the microphone is
  /// still open, or "on" before it is.
  DVMediaSignal<bool> get capturing => _capturing;

  bool get _terminal => switch (_state.value) {
        DVCaptureState.completed ||
        DVCaptureState.refused ||
        DVCaptureState.interrupted ||
        DVCaptureState.failed ||
        DVCaptureState.disposed =>
          true,
        _ => false,
      };

  static bool _inBackground(DVAppLifecycle app) =>
      app == DVAppLifecycle.backgrounded ||
      app == DVAppLifecycle.suspended ||
      app == DVAppLifecycle.shuttingDown;

  Future<void> _run() async {
    try {
      final String? unsupported =
          request.unsupportedBy(_runtime.capabilities);
      if (unsupported != null) {
        return _finishError(
            DVCaptureState.failed, DVCaptureUnsupported(unsupported));
      }
      if (!_runtime._claim(this)) {
        return _finishError(DVCaptureState.failed, const DVCaptureBusy());
      }
      if (_inBackground(_runtime.lifecycle.value)) {
        return _finishError(DVCaptureState.interrupted,
            const DVCaptureInterrupted(DVCaptureInterruption.backgrounded, null));
      }

      _state.set(DVCaptureState.requestingPermission);
      for (final String permission in request.permissions) {
        final bool granted = await _runtime.permissions.request(permission);
        if (_disposed) return;
        if (!granted) {
          _runtime.diagnostics(
            'DV-MEDIA-104',
            '$permission was refused for a ${request.kind.name} recording',
          );
          return _finishError(
              DVCaptureState.refused, DVCapturePermissionRefused(permission));
        }
      }
      // A permission prompt can outlast the application being on screen.
      if (_inBackground(_runtime.lifecycle.value)) {
        return _finishError(DVCaptureState.interrupted,
            const DVCaptureInterrupted(DVCaptureInterruption.backgrounded, null));
      }

      _state.set(DVCaptureState.starting);
      final String path = await _runtime.files.reserve(request.extension);
      _path = path;
      if (_disposed) {
        await _runtime.files.discard(path);
        return;
      }
      final DVCaptureBackend backend = _runtime.backendFactory();
      _backend = backend;
      _events = backend.events.listen(_onEvent);
      _lifecycle = _runtime.lifecycle.listen(_onLifecycle);
      await backend.start(request, path);
    } catch (error) {
      if (_terminal) return;
      _capturing.set(false);
      await _discardPath();
      await _finishError(DVCaptureState.failed, DVCaptureFailure('$error'));
    }
  }

  void _onLifecycle(DVAppLifecycle app) {
    if (_inBackground(app)) _interrupt(DVCaptureInterruption.backgrounded);
  }

  void _onEvent(DVCaptureBackendEvent event) {
    if (_disposed || _terminal) return;
    switch (event) {
      case DVCaptureStarted():
        _capturing.set(true);
        if (_state.value == DVCaptureState.starting) {
          _state.set(DVCaptureState.recording);
          final Duration? max = request.maxDuration;
          if (max != null) {
            _limit = _runtime.timers.start(max, () {
              _limit = null;
              unawaited(stop());
            });
          }
          if (_stopWhenStarted) unawaited(stop());
        }
      case DVCaptureStopped(:final Duration duration):
        _capturing.set(false);
        unawaited(_finalize(duration));
      case DVCapturePermissionRevoked():
        _interrupt(DVCaptureInterruption.permissionRevoked);
      case DVCaptureDeviceLost():
        _interrupt(DVCaptureInterruption.deviceLost);
      case DVCaptureFailed(:final String message):
        _capturing.set(false);
        unawaited(() async {
          await _discardPath();
          await _finishError(DVCaptureState.failed, DVCaptureFailure(message));
        }());
    }
  }

  void _interrupt(DVCaptureInterruption reason) {
    final DVCaptureState now = _state.value;
    if (now != DVCaptureState.starting &&
        now != DVCaptureState.recording &&
        now != DVCaptureState.stopping) {
      return;
    }
    _interruption ??= reason;
    if (now == DVCaptureState.stopping) return;
    _state.set(DVCaptureState.stopping);
    _limit?.cancel();
    _limit = null;
    unawaited(_backend?.stop());
  }

  /// Stops the recording. Completes once the device has confirmed and the
  /// session has finished, whatever the outcome.
  ///
  /// Before the device has opened, the stop is held until it does, so a
  /// recording stopped early still finishes as a recording.
  Future<void> stop() async {
    if (_disposed || _terminal) return;
    switch (_state.value) {
      case DVCaptureState.checking:
      case DVCaptureState.requestingPermission:
        _stopWhenStarted = true;
      case DVCaptureState.starting:
        if (!_capturing.value) {
          _stopWhenStarted = true;
        } else {
          _state.set(DVCaptureState.stopping);
          await _backend?.stop();
        }
      case DVCaptureState.recording:
        _limit?.cancel();
        _limit = null;
        _state.set(DVCaptureState.stopping);
        await _backend?.stop();
      default:
        break;
    }
    await _completer.future.then((_) {}, onError: (_) {});
  }

  Future<void> _finalize(Duration duration) async {
    final String? path = _path;
    if (path == null || _disposed) return;
    try {
      final int size = await _runtime.files.seal(path);
      final DVFile file = DVFile(
        path: path,
        mimeType: request.mimeType,
        sizeBytes: size,
        duration: duration,
      );
      final DVCaptureInterruption? reason = _interruption;
      if (reason != null) {
        await _finishError(
            DVCaptureState.interrupted, DVCaptureInterrupted(reason, file));
      } else {
        await _release();
        _state.set(DVCaptureState.completed);
        if (!_completer.isCompleted) _completer.complete(file);
      }
    } catch (error) {
      await _discardPath();
      await _finishError(DVCaptureState.failed, DVCaptureFailure('$error'));
    }
  }

  Future<void> _discardPath() async {
    final String? path = _path;
    if (path != null) await _runtime.files.discard(path);
  }

  Future<void> _finishError(DVCaptureState state, Object error) async {
    await _release();
    if (!_disposed) _state.set(state);
    if (!_completer.isCompleted) _completer.completeError(error);
  }

  /// Everything the session holds except its signals.
  Future<void> _release() async {
    _limit?.cancel();
    _limit = null;
    _runtime._free(this);
    final DVCaptureBackend? backend = _backend;
    _backend = null;
    unawaited(_lifecycle?.cancel());
    _lifecycle = null;
    unawaited(_events?.cancel());
    _events = null;
    await backend?.dispose();
  }

  /// Releases the device and everything else this session holds.
  ///
  /// Mid-recording, the device is aborted and the partial file deleted: the
  /// page that started it is gone and nothing will ever pick the file up. A
  /// recording that already finished keeps its file.
  Future<void> dispose() async {
    if (_disposed) return;
    final bool open = !_terminal;
    _disposed = true;
    final DVCaptureBackend? backend = _backend;
    if (open && backend != null) await backend.abort();
    await _release();
    _capturing.set(false);
    if (open) {
      await _discardPath();
      if (!_completer.isCompleted) {
        _completer.completeError(
            const DVCaptureInterrupted(DVCaptureInterruption.disposed, null));
      }
    }
    _state.set(DVCaptureState.disposed);
    await _state.close();
    await _capturing.close();
  }

  @override
  Stream<DVFile> asStream() => _completer.future.asStream();

  @override
  Future<DVFile> catchError(Function onError,
          {bool Function(Object error)? test}) =>
      _completer.future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(DVFile value) onValue,
          {Function? onError}) =>
      _completer.future.then<R>(onValue, onError: onError);

  @override
  Future<DVFile> timeout(Duration timeLimit,
          {FutureOr<DVFile> Function()? onTimeout}) =>
      _completer.future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<DVFile> whenComplete(FutureOr<void> Function() action) =>
      _completer.future.whenComplete(action);
}

/// The capture runtime behind `DV.Platform.Media`.
///
/// One recording at a time: a second is refused with [DVCaptureBusy] rather
/// than handed a device the first still holds.
final class DVMediaCapture {
  DVMediaCapture({
    required this.capabilities,
    required DVCaptureBackend Function() backend,
    required this.permissions,
    required this.files,
    DVLifecycleSignal<DVAppLifecycle>? lifecycle,
    this.timers = const DVSystemMediaTimers(),
    DVMediaDiagnosticSink? diagnostics,
  })  : backendFactory = backend,
        lifecycle = lifecycle ?? dvLifecycle.app,
        diagnostics = diagnostics ?? dvLogMediaDiagnostic;

  /// What this target's capture backend reports it can record.
  final DVCaptureCapabilities capabilities;

  /// Makes the device for one recording. Construction must open nothing; the
  /// session calls `start` once permission is granted, and disposes it when
  /// the recording ends.
  final DVCaptureBackend Function() backendFactory;

  final DVCapturePermissions permissions;
  final DVCaptureFiles files;
  final DVLifecycleSignal<DVAppLifecycle> lifecycle;
  final DVMediaTimers timers;
  final DVMediaDiagnosticSink diagnostics;

  DVCaptureSession? _active;

  /// The recording holding the device, if any.
  DVCaptureSession? get active => _active;

  bool _claim(DVCaptureSession session) {
    if (_active != null && !identical(_active, session)) return false;
    _active = session;
    return true;
  }

  void _free(DVCaptureSession session) {
    if (identical(_active, session)) _active = null;
  }

  DVCaptureSession recordAudio({
    DVAudioFormat format = DVAudioFormat.aac,
    Duration? maxDuration,
  }) =>
      _record(DVCaptureRequest.audio(
          audioFormat: format, maxDuration: maxDuration));

  DVCaptureSession recordVideo({
    DVVideoQuality quality = DVVideoQuality.hd720,
    Duration? maxDuration,
  }) =>
      _record(DVCaptureRequest.video(
          videoQuality: quality, maxDuration: maxDuration));

  DVCaptureSession _record(DVCaptureRequest request) {
    final DVCaptureSession session = DVCaptureSession._(this, request);
    unawaited(session._run());
    return session;
  }
}
