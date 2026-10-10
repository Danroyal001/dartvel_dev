/// The widget half of `DVBox.camera`.
///
/// The box's element owns the camera, as it owns a player: mounting opens it,
/// leaving the page closes it, so the camera light cannot outlive the screen
/// that showed it.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'media_box.dart';
import 'web_media_mapping.dart';

/// Which built-in controls a camera box draws.
enum DVCameraControls {
  /// Shutter, record, switch lens, flash and torch, where the device has
  /// them.
  standard,

  /// None: the application draws its own from the controller's signals.
  none,
}

/// The camera a box makes: the registered backend, or one that has nothing.
DVCameraController dvMakeCameraController({
  DVCameraLens lens = DVCameraLens.back,
  DVFlashMode flash = DVFlashMode.off,
}) =>
    DVCameraController(
      DVMediaBackends.createCamera() ?? const _DVNoCamera(),
      lens: lens,
      flash: flash,
      environment: DVCameraEnvironment(
        permissions: DVMediaBackends.capturePermissions,
        files: DVMediaBackends.captureFiles,
        lifecycle: DVMediaBackends.environment().lifecycle,
      ),
    );

/// A target with no camera bound. Reports nothing, so the controller
/// refuses before asking anybody for permission.
final class _DVNoCamera implements DVCameraBackend {
  const _DVNoCamera();

  @override
  DVCameraCapabilities get capabilities => DVCameraCapabilities.none;

  @override
  Stream<DVCameraEvent> get events => const Stream<DVCameraEvent>.empty();

  Never _none() => throw const DVCameraUnavailable('this target has no camera');

  @override
  Future<void> open(DVCameraLens lens) async => _none();

  @override
  Future<void> close() async {}

  @override
  Future<void> takePhoto(String path, {DVFlashMode flash = DVFlashMode.off}) async =>
      _none();

  @override
  Future<void> startRecording(String path,
          {DVVideoQuality quality = DVVideoQuality.hd720, bool audio = true}) async =>
      _none();

  @override
  Future<void> stopRecording() async {}

  @override
  Future<void> setTorch(bool on) async => _none();

  @override
  Future<void> dispose() async {}
}

/// Built by `DVBox.camera`; application code uses the box.
@internal
class DVCameraView extends StatefulWidget {
  DVCameraView({
    super.key,
    DVCameraLens lens = DVCameraLens.back,
    this.controls = DVCameraControls.standard,
    this.onPhoto,
    this.onVideo,
    DVCameraController? controller,
  })  : ownsController = controller == null,
        controller = controller ?? dvMakeCameraController(lens: lens);

  final DVCameraControls controls;

  /// Called with each photo the standard shutter takes.
  final void Function(DVFile photo)? onPhoto;

  /// Called with each clip the standard record button finishes.
  final void Function(DVFile clip)? onVideo;

  final DVCameraController controller;
  final bool ownsController;

  @override
  State<DVCameraView> createState() => _DVCameraViewState();
}

class _DVCameraViewState extends State<DVCameraView> {
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  DVCaptureSession? _recording;
  String? _message;

  DVCameraController get _camera => widget.controller;

  @override
  void initState() {
    super.initState();
    for (final DVMediaSignal<Object?> signal in <DVMediaSignal<Object?>>[
      _camera.state,
      _camera.lens,
      _camera.flash,
      _camera.torch,
      _camera.previewSize,
    ]) {
      _subscriptions.add(signal.changes.listen((_) {
        if (mounted) setState(() {});
      }));
    }
    unawaited(_camera.open().catchError((Object error) {
      if (mounted) setState(() => _message = _describe(error));
    }));
  }

  static String _describe(Object error) => switch (error) {
        DVCapturePermissionRefused() => 'Camera access was refused',
        DVCameraUnavailable(:final String reason) => 'No camera: $reason',
        _ => 'The camera failed: $error',
      };

  @override
  void dispose() {
    for (final StreamSubscription<Object?> s in _subscriptions) {
      unawaited(s.cancel());
    }
    if (widget.ownsController) unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _shutter() async {
    try {
      final DVFile photo = await _camera.takePhoto();
      widget.onPhoto?.call(photo);
      if (mounted) setState(() => _message = 'Photo taken');
    } on Object catch (error) {
      if (mounted) setState(() => _message = _describe(error));
    }
  }

  Future<void> _record() async {
    final DVCaptureSession? running = _recording;
    if (running != null) {
      await running.stop();
      return;
    }
    final DVCaptureSession session = _camera.recordVideo();
    setState(() => _recording = session);
    try {
      final DVFile clip = await session;
      widget.onVideo?.call(clip);
      if (mounted) setState(() => _message = 'Recording saved');
    } on Object catch (error) {
      if (mounted) setState(() => _message = _describe(error));
    } finally {
      if (mounted) setState(() => _recording = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DVCameraState state = _camera.state.value;
    final DVCameraCapabilities can = _camera.capabilities;
    final DVCameraBackend backend = _camera.backend;
    final bool live = state == DVCameraState.ready ||
        state == DVCameraState.takingPhoto ||
        state == DVCameraState.recording;
    final (int, int)? size = _camera.previewSize.value;

    final Widget preview = live && backend is DVCameraSurface
        ? (backend as DVCameraSurface).buildPreview(context)
        : ColoredBox(
            color: const Color(0xFF000000),
            child: Center(
              child: Text(
                _message ?? _stateText(state),
                style: const TextStyle(color: Color(0xFFFFFFFF)),
              ),
            ),
          );

    final Widget controls = widget.controls == DVCameraControls.none
        ? const SizedBox.shrink()
        : Material(
            type: .transparency,
            child: Wrap(
              alignment: .center,
              spacing: 8,
              children: <Widget>[
                if (can.photo)
                  IconButton.filled(
                    tooltip: 'Take photo',
                    icon: const Icon(Icons.camera_alt),
                    onPressed: state == DVCameraState.ready ? _shutter : null,
                  ),
                if (can.video)
                  IconButton.filled(
                    tooltip: _recording == null ? 'Record video' : 'Stop recording',
                    icon: Icon(_recording == null
                        ? Icons.fiber_manual_record
                        : Icons.stop),
                    onPressed: live ? _record : null,
                  ),
                if (can.lenses.length > 1)
                  IconButton(
                    tooltip: 'Switch camera (now ${_camera.lens.value.name})',
                    icon: const Icon(Icons.cameraswitch),
                    onPressed: state == DVCameraState.ready
                        ? () => unawaited(
                            _camera.switchLens().catchError((Object _) {}))
                        : null,
                  ),
                if (can.flash)
                  IconButton(
                    tooltip: 'Flash: ${_camera.flash.value.name}',
                    icon: Icon(switch (_camera.flash.value) {
                      DVFlashMode.off => Icons.flash_off,
                      DVFlashMode.auto => Icons.flash_auto,
                      DVFlashMode.on => Icons.flash_on,
                    }),
                    onPressed: () => _camera.setFlash(DVFlashMode.values[
                        (_camera.flash.value.index + 1) %
                            DVFlashMode.values.length]),
                  ),
                if (can.torch)
                  IconButton(
                    tooltip: _camera.torch.value ? 'Torch off' : 'Torch on',
                    isSelected: _camera.torch.value,
                    icon: const Icon(Icons.flashlight_on),
                    onPressed: state == DVCameraState.ready
                        ? () => unawaited(_camera
                            .setTorch(!_camera.torch.value)
                            .catchError((Object _) {}))
                        : null,
                  ),
              ],
            ),
          );

    return Semantics(
      identifier: dvCameraSemanticsIdentifier,
      label: 'Camera',
      value: _message ?? _stateText(state),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: size == null
                ? preview
                : FittedBox(
                    fit: .cover,
                    clipBehavior: .hardEdge,
                    child: SizedBox(
                        width: size.$1.toDouble(),
                        height: size.$2.toDouble(),
                        child: preview),
                  ),
          ),
          Positioned(left: 0, right: 0, bottom: 8, child: controls),
        ],
      ),
    );
  }

  static String _stateText(DVCameraState state) => switch (state) {
        DVCameraState.idle ||
        DVCameraState.opening ||
        DVCameraState.requestingPermission =>
          'Opening the camera',
        DVCameraState.ready => 'Camera ready',
        DVCameraState.takingPhoto => 'Taking photo',
        DVCameraState.recording => 'Recording',
        DVCameraState.paused => 'Camera paused',
        DVCameraState.refused => 'Camera access was refused',
        DVCameraState.failed => 'The camera is unavailable',
        DVCameraState.disposed => 'Camera closed',
      };
}
