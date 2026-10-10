/// The camera behind `DVBox.camera`: preview, photos, video, lens, flash and
/// torch.
///
/// The same split as the player. A backend is CameraX through JNI,
/// AVCaptureSession, `getUserMedia` in a browser; it reports what the
/// device did, and [DVCameraController] decides what that means. The camera
/// light is the thing people judge a camera API by, so the rule here is that
/// the device is open only while a box showing it is mounted and the
/// application is in the foreground, and `state` says so only once the
/// device has confirmed it.
library;

import 'dart:async';

import '../lifecycle/lifecycle.dart';
import '../storage/file.dart';
import 'capture.dart';
import 'capture_backend.dart';
import 'media_controller.dart' show dvLogMediaDiagnostic;
import 'media_signal.dart';

/// Which camera.
enum DVCameraLens { back, front, external }

/// What the flash does when a photo is taken.
enum DVFlashMode { off, auto, on }

/// Where a camera is.
enum DVCameraState {
  idle,
  requestingPermission,

  /// Asked the device to open; it has not confirmed.
  opening,

  /// Open and previewing.
  ready,
  takingPhoto,
  recording,

  /// Closed because the application went to the background. Reopens when
  /// it comes back.
  paused,

  /// The person said no.
  refused,
  failed,
  disposed,
}

/// What this target's camera can do. Reported, never assumed.
final class DVCameraCapabilities {
  const DVCameraCapabilities({
    this.lenses = const <DVCameraLens>{},
    this.flash = false,
    this.torch = false,
    this.photo = false,
    this.video = false,
    this.preview = false,
    this.videoQualities = const <DVVideoQuality>{},
  });

  /// Nothing: a target with no camera binding.
  static const DVCameraCapabilities none = DVCameraCapabilities();

  final Set<DVCameraLens> lenses;
  final bool flash;
  final bool torch;
  final bool photo;
  final bool video;

  /// Can draw the live picture into the application.
  final bool preview;
  final Set<DVVideoQuality> videoQualities;

  bool get available => lenses.isNotEmpty;
}

/// A camera device.
abstract interface class DVCameraBackend {
  DVCameraCapabilities get capabilities;

  Stream<DVCameraEvent> get events;

  /// Opens [lens] and starts the preview. Confirmed by [DVCameraOpened].
  Future<void> open(DVCameraLens lens);

  /// Closes the device. Confirmed by [DVCameraClosed].
  Future<void> close();

  /// Writes a JPEG into [path], which exists and is private. Confirmed by
  /// [DVCameraPhotoTaken].
  Future<void> takePhoto(String path, {DVFlashMode flash = DVFlashMode.off});

  /// Records into [path]. Confirmed by [DVCameraRecordingStarted].
  Future<void> startRecording(String path,
      {DVVideoQuality quality = DVVideoQuality.hd720, bool audio = true});

  /// Confirmed by [DVCameraRecordingStopped] once the file is finalised.
  Future<void> stopRecording();

  Future<void> setTorch(bool on);

  Future<void> dispose();
}

/// Something the camera reports.
sealed class DVCameraEvent {
  const DVCameraEvent();
}

final class DVCameraOpened extends DVCameraEvent {
  const DVCameraOpened(this.lens, {this.width, this.height});
  final DVCameraLens lens;

  /// The preview's size in pixels, when known.
  final int? width;
  final int? height;
}

final class DVCameraClosed extends DVCameraEvent {
  const DVCameraClosed();
}

final class DVCameraPhotoTaken extends DVCameraEvent {
  const DVCameraPhotoTaken(this.path);
  final String path;
}

final class DVCameraRecordingStarted extends DVCameraEvent {
  const DVCameraRecordingStarted();
}

final class DVCameraRecordingStopped extends DVCameraEvent {
  const DVCameraRecordingStopped(this.duration);
  final Duration duration;
}

/// The device went away: unplugged, taken by another application, or the
/// operating system withdrew the permission.
final class DVCameraDisconnected extends DVCameraEvent {
  const DVCameraDisconnected();
}

final class DVCameraFailed extends DVCameraEvent {
  const DVCameraFailed(this.message);
  final String message;
}

/// The camera is not open, or this target has no camera.
final class DVCameraUnavailable implements Exception {
  const DVCameraUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'DVCameraUnavailable: $reason';
}

/// What a camera is wired to.
final class DVCameraEnvironment {
  DVCameraEnvironment({
    required this.permissions,
    required this.files,
    DVLifecycleSignal<DVAppLifecycle>? lifecycle,
    this.timers = const DVSystemMediaTimers(),
    DVMediaDiagnosticSink? diagnostics,
  })  : lifecycle = lifecycle ?? dvLifecycle.app,
        diagnostics = diagnostics ?? dvLogMediaDiagnostic;

  final DVCapturePermissions permissions;
  final DVCaptureFiles files;
  final DVLifecycleSignal<DVAppLifecycle> lifecycle;
  final DVMediaTimers timers;
  final DVMediaDiagnosticSink diagnostics;
}

/// A handle on one camera.
///
/// Made by `DVBox.camera(...)`, which opens it when mounted and disposes it
/// when the page goes. Read `DVBox.camera(...).camera` for the handle.
final class DVCameraController {
  DVCameraController(
    this.backend, {
    required this.environment,
    DVCameraLens lens = DVCameraLens.back,
    DVFlashMode flash = DVFlashMode.off,
  })  : _lens = DVMutableMediaSignal<DVCameraLens>(lens),
        _flash = DVMutableMediaSignal<DVFlashMode>(flash);

  final DVCameraBackend backend;
  final DVCameraEnvironment environment;

  final DVMutableMediaSignal<DVCameraState> _state =
      DVMutableMediaSignal<DVCameraState>(DVCameraState.idle);
  final DVMutableMediaSignal<DVCameraLens> _lens;
  final DVMutableMediaSignal<DVFlashMode> _flash;
  final DVMutableMediaSignal<bool> _torch = DVMutableMediaSignal<bool>(false);
  final DVMutableMediaSignal<String?> _error =
      DVMutableMediaSignal<String?>(null);
  final DVMutableMediaSignal<(int, int)?> _previewSize =
      DVMutableMediaSignal<(int, int)?>(null);

  StreamSubscription<DVCameraEvent>? _events;
  StreamSubscription<DVAppLifecycle>? _lifecycle;
  Completer<void>? _opened;
  Completer<String>? _photo;
  DVCaptureSession? _recording;
  _DVCameraRecorder? _recorder;
  bool _wantOpen = false;

  DVCameraCapabilities get capabilities => backend.capabilities;

  DVMediaSignal<DVCameraState> get state => _state;
  DVMediaSignal<DVCameraLens> get lens => _lens;
  DVMediaSignal<DVFlashMode> get flash => _flash;
  DVMediaSignal<bool> get torch => _torch;
  DVMediaSignal<String?> get error => _error;

  /// The preview's width and height, once the device reports them.
  DVMediaSignal<(int, int)?> get previewSize => _previewSize;

  bool get _disposed => _state.value == DVCameraState.disposed;

  void _check() {
    if (_disposed) throw StateError('This camera has been disposed.');
  }

  /// Asks permission and opens the camera. Throws
  /// [DVCapturePermissionRefused] (state [DVCameraState.refused]) or
  /// [DVCameraUnavailable].
  Future<void> open() async {
    _check();
    if (!capabilities.available) {
      _state.set(DVCameraState.failed);
      _error.set('this target has no camera');
      throw const DVCameraUnavailable('this target has no camera');
    }
    if (!capabilities.lenses.contains(_lens.value)) {
      _lens.set(capabilities.lenses.first);
    }
    _wantOpen = true;
    _events ??= backend.events.listen(_onEvent);
    _lifecycle ??= environment.lifecycle.listen(_onLifecycle);
    _state.set(DVCameraState.requestingPermission);
    final bool granted = await environment.permissions.request('camera');
    if (_disposed) return;
    if (!granted) {
      _wantOpen = false;
      environment.diagnostics(
          'DV-MEDIA-104', 'camera was refused for a camera preview');
      _state.set(DVCameraState.refused);
      throw const DVCapturePermissionRefused('camera');
    }
    if (_inBackground(environment.lifecycle.value)) {
      _state.set(DVCameraState.paused);
      return;
    }
    await _openDevice();
  }

  Future<void> _openDevice() async {
    _state.set(DVCameraState.opening);
    final Completer<void> opened = _opened = Completer<void>();
    await backend.open(_lens.value);
    await opened.future;
  }

  static bool _inBackground(DVAppLifecycle app) =>
      app == DVAppLifecycle.backgrounded ||
      app == DVAppLifecycle.suspended ||
      app == DVAppLifecycle.shuttingDown;

  void _onLifecycle(DVAppLifecycle app) {
    if (_disposed || !_wantOpen) return;
    if (_inBackground(app)) {
      final DVCameraState now = _state.value;
      if (now == DVCameraState.paused || now == DVCameraState.refused) return;
      // The recording ends as interrupted through its own session; the
      // device closes here either way, so the light goes off.
      _state.set(DVCameraState.paused);
      _torch.set(false);
      unawaited(backend.close());
    } else if (app == DVAppLifecycle.ready &&
        _state.value == DVCameraState.paused) {
      unawaited(_openDevice().catchError((Object _) {}));
    }
  }

  void _onEvent(DVCameraEvent event) {
    if (_disposed) return;
    switch (event) {
      case DVCameraOpened(:final DVCameraLens lens, :final width, :final height):
        _lens.set(lens);
        if (width != null && height != null) _previewSize.set((width, height));
        _error.set(null);
        if (_state.value == DVCameraState.opening) {
          _state.set(DVCameraState.ready);
        }
        _complete(_opened);
      case DVCameraClosed():
        _torch.set(false);
        if (_state.value != DVCameraState.paused &&
            _state.value != DVCameraState.opening) {
          _state.set(DVCameraState.idle);
        }
      case DVCameraPhotoTaken(:final String path):
        final Completer<String>? photo = _photo;
        _photo = null;
        if (_state.value == DVCameraState.takingPhoto) {
          _state.set(DVCameraState.ready);
        }
        if (photo != null && !photo.isCompleted) photo.complete(path);
      case DVCameraRecordingStarted():
        _state.set(DVCameraState.recording);
        _recorder?.emit(const DVCaptureStarted());
      case DVCameraRecordingStopped(:final Duration duration):
        if (_state.value == DVCameraState.recording) {
          _state.set(DVCameraState.ready);
        }
        _recorder?.emit(DVCaptureStopped(duration));
      case DVCameraDisconnected():
        _recorder?.emit(const DVCaptureDeviceLost());
        _fail('the camera was disconnected');
      case DVCameraFailed(:final String message):
        _recorder?.emit(DVCaptureFailed(message));
        _fail(message);
    }
  }

  void _fail(String message) {
    _error.set(message);
    _state.set(DVCameraState.failed);
    _torch.set(false);
    final Completer<void>? opened = _opened;
    _opened = null;
    if (opened != null && !opened.isCompleted) {
      opened.completeError(DVCameraUnavailable(message));
    }
    final Completer<String>? photo = _photo;
    _photo = null;
    if (photo != null && !photo.isCompleted) {
      photo.completeError(DVCaptureFailure(message));
    }
  }

  static void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _requireReady(String what) {
    _check();
    if (_state.value != DVCameraState.ready) {
      throw DVCameraUnavailable(
          'cannot $what while the camera is ${_state.value.name}');
    }
  }

  /// Switches to [to], or to the next lens this device has.
  Future<void> switchLens([DVCameraLens? to]) async {
    _requireReady('switch lens');
    final List<DVCameraLens> lenses = capabilities.lenses.toList();
    final DVCameraLens next = to ??
        lenses[(lenses.indexOf(_lens.value) + 1) % lenses.length];
    if (!capabilities.lenses.contains(next)) {
      throw DVCameraUnavailable('this device has no ${next.name} camera');
    }
    if (next == _lens.value) return;
    _torch.set(false);
    _lens.set(next);
    await _openDevice();
  }

  void setFlash(DVFlashMode mode) {
    _check();
    if (mode != DVFlashMode.off && !capabilities.flash) {
      throw const DVCameraUnavailable('this camera has no flash');
    }
    _flash.set(mode);
  }

  Future<void> setTorch(bool on) async {
    _requireReady('change the torch');
    if (on && !capabilities.torch) {
      throw const DVCameraUnavailable('this camera has no torch');
    }
    await backend.setTorch(on);
    _torch.set(on);
  }

  /// Takes a photo. The JPEG is written where only this application can
  /// read it.
  Future<DVFile> takePhoto() async {
    _requireReady('take a photo');
    if (!capabilities.photo) {
      throw const DVCameraUnavailable('this camera cannot take photos');
    }
    final String path = await environment.files.reserve('jpg');
    final Completer<String> taken = _photo = Completer<String>();
    _state.set(DVCameraState.takingPhoto);
    try {
      await backend.takePhoto(path, flash: _flash.value);
      await taken.future;
      final int size = await environment.files.seal(path);
      return DVFile(path: path, mimeType: 'image/jpeg', sizeBytes: size);
    } on Object {
      await environment.files.discard(path);
      if (_state.value == DVCameraState.takingPhoto) {
        _state.set(DVCameraState.ready);
      }
      rethrow;
    }
  }

  /// Records video from this camera. Await the session for the file; hold
  /// it to stop. The same session `DV.Platform.media.recordVideo` returns,
  /// with the same refusals and the same private file.
  DVCaptureSession recordVideo({
    DVVideoQuality quality = DVVideoQuality.hd720,
    Duration? maxDuration,
  }) {
    _requireReady('record');
    final DVMediaCapture capture = DVMediaCapture(
      capabilities: DVCaptureCapabilities(
        camera: capabilities.video,
        videoQualities: capabilities.videoQualities,
      ),
      backend: () => _recorder = _DVCameraRecorder(this),
      permissions: environment.permissions,
      files: environment.files,
      lifecycle: environment.lifecycle,
      timers: environment.timers,
      diagnostics: environment.diagnostics,
    );
    final DVCaptureSession session =
        _recording = capture.recordVideo(quality: quality, maxDuration: maxDuration);
    return session;
  }

  /// Closes the camera and releases everything. A recording in progress is
  /// aborted and its file deleted.
  Future<void> dispose() async {
    if (_disposed) return;
    _wantOpen = false;
    final DVCaptureSession? recording = _recording;
    _recording = null;
    if (recording != null) await recording.dispose();
    _state.set(DVCameraState.disposed);
    final Completer<String>? photo = _photo;
    _photo = null;
    if (photo != null && !photo.isCompleted) {
      photo.completeError(const DVCameraUnavailable('the camera was disposed'));
    }
    _complete(_opened);
    unawaited(_events?.cancel());
    unawaited(_lifecycle?.cancel());
    await backend.close();
    await backend.dispose();
    await Future.wait(<Future<void>>[
      _state.close(),
      _lens.close(),
      _flash.close(),
      _torch.close(),
      _error.close(),
      _previewSize.close(),
    ]);
  }
}

/// A recording on an open camera, as the capture session sees a device.
final class _DVCameraRecorder implements DVCaptureBackend {
  _DVCameraRecorder(this.camera);

  final DVCameraController camera;
  final StreamController<DVCaptureBackendEvent> _events =
      StreamController<DVCaptureBackendEvent>.broadcast();

  void emit(DVCaptureBackendEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  DVCaptureCapabilities get capabilities => DVCaptureCapabilities(
        camera: camera.capabilities.video,
        videoQualities: camera.capabilities.videoQualities,
      );

  @override
  Stream<DVCaptureBackendEvent> get events => _events.stream;

  @override
  Future<void> start(DVCaptureRequest request, String outputPath) =>
      camera.backend.startRecording(outputPath,
          quality: request.videoQuality ?? DVVideoQuality.hd720);

  @override
  Future<void> stop() => camera.backend.stopRecording();

  @override
  Future<void> abort() => camera.backend.stopRecording();

  @override
  Future<void> dispose() async {
    if (identical(camera._recorder, this)) camera._recorder = null;
    await _events.close();
  }
}

/// A camera the test drives.
final class DVFakeCameraBackend implements DVCameraBackend {
  DVFakeCameraBackend({
    this.capabilities = const DVCameraCapabilities(
      lenses: <DVCameraLens>{DVCameraLens.back, DVCameraLens.front},
      flash: true,
      torch: true,
      photo: true,
      video: true,
      preview: true,
      videoQualities: <DVVideoQuality>{DVVideoQuality.hd720},
    ),
    this.autoConfirm = true,
  });

  @override
  final DVCameraCapabilities capabilities;

  /// Confirms every request at once, as a working device would.
  final bool autoConfirm;

  final List<String> calls = <String>[];
  final List<DVCameraLens> opened = <DVCameraLens>[];
  final List<DVFlashMode> flashes = <DVFlashMode>[];
  bool isOpen = false;
  bool disposed = false;

  final StreamController<DVCameraEvent> _events =
      StreamController<DVCameraEvent>.broadcast();

  void emit(DVCameraEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<DVCameraEvent> get events => _events.stream;

  void _confirm(DVCameraEvent event) {
    if (autoConfirm) scheduleMicrotask(() => emit(event));
  }

  @override
  Future<void> open(DVCameraLens lens) async {
    calls.add('open:${lens.name}');
    opened.add(lens);
    isOpen = true;
    _confirm(DVCameraOpened(lens, width: 1280, height: 720));
  }

  @override
  Future<void> close() async {
    calls.add('close');
    isOpen = false;
    _confirm(const DVCameraClosed());
  }

  @override
  Future<void> takePhoto(String path,
      {DVFlashMode flash = DVFlashMode.off}) async {
    calls.add('photo');
    flashes.add(flash);
    _confirm(DVCameraPhotoTaken(path));
  }

  @override
  Future<void> startRecording(String path,
      {DVVideoQuality quality = DVVideoQuality.hd720, bool audio = true}) async {
    calls.add('record');
    _confirm(const DVCameraRecordingStarted());
  }

  @override
  Future<void> stopRecording() async {
    calls.add('stopRecording');
    _confirm(const DVCameraRecordingStopped(Duration(seconds: 3)));
  }

  @override
  Future<void> setTorch(bool on) async => calls.add('torch:$on');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
    await _events.close();
  }
}
