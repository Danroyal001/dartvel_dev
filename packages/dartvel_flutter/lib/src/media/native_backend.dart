/// Internal adapters for a polled native media bridge. JNI and FFI stay in
/// platform files; the lifecycle and controller contract can be tested here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

import 'media_box.dart';
import 'native_events.dart';

abstract interface class DVNativeMediaBridge {
  Object? call(String method, List<Object?> arguments);
}

final class DVNativePlayerBackend
    implements DVMediaPlayerBackend, DVVideoSurface {
  DVNativePlayerBackend(
    this.bridge, {
    required int engineId,
    required bool video,
    this.capabilities = const DVMediaBackendCapabilities(),
  }) {
    _handle = bridge.call('create', [engineId, video]) as int;
    if (_handle <= 0) throw StateError('Native player creation failed');
    _events = StreamController<DVMediaBackendEvent>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
  }
  final DVNativeMediaBridge bridge;
  @override
  final DVMediaBackendCapabilities capabilities;
  late final int _handle;
  late final StreamController<DVMediaBackendEvent> _events;
  Timer? _timer;
  bool _disposed = false;
  Object? _call(String name, [List<Object?> args = const []]) {
    if (_disposed) throw StateError('Native player is disposed');
    return bridge.call(name, [_handle, ...args]);
  }

  void _startPolling() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      try {
        for (final event in dvParseMediaEvents(_call('poll') as String?)) {
          _events.add(event);
        }
      } on Object catch (error) {
        _stopPolling();
        _events.add(DVMediaFailed('$error'));
      }
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Stream<DVMediaBackendEvent> get events => _events.stream;
  @override
  Future<void> open(DVMediaSource source, {Object? license}) async {
    if (license != null) throw UnsupportedError('Native DRM is not configured');
    final uri = switch (source.kind) {
      DVMediaSourceKind.url => source.reference,
      DVMediaSourceKind.file => Uri.file(source.reference).toString(),
      DVMediaSourceKind.asset => 'asset:///flutter_assets/${source.reference}',
    };
    _call('open', [uri]);
  }

  @override
  Future<void> play() async {
    _call('play');
  }

  @override
  Future<void> pause() async {
    _call('pause');
  }

  @override
  Future<void> seek(Duration position, int generation) async {
    _call('seek', [position.inMilliseconds, generation]);
  }

  @override
  Future<void> setVolume(double volume) async {
    _call('setVolume', [volume]);
  }

  @override
  Widget buildSurface(BuildContext context) {
    final id = _call('textureId') as int;
    return id < 0 ? const SizedBox.shrink() : Texture(textureId: id);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _stopPolling();
    try {
      _call('dispose');
    } finally {
      _disposed = true;
      await _events.close();
    }
  }
}

final class DVNativeCameraBackend implements DVCameraBackend, DVCameraSurface {
  DVNativeCameraBackend(
    this.bridge, {
    required this.engineId,
    required this.capabilities,
  }) {
    _events = StreamController<DVCameraEvent>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
  }
  final DVNativeMediaBridge bridge;
  final int engineId;
  @override
  final DVCameraCapabilities capabilities;
  late final StreamController<DVCameraEvent> _events;
  int? _handle;
  bool _disposed = false;
  Timer? _timer;
  void _check() {
    if (_disposed) throw StateError('Native camera is disposed');
  }

  Object? _call(String name, [List<Object?> args = const []]) {
    _check();
    final handle = _handle;
    if (handle == null) throw StateError('Native camera is not open');
    return bridge.call(name, [handle, ...args]);
  }

  void _startPolling() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_handle == null) return;
      try {
        for (final event in dvParseCameraEvents(
          _call('pollCamera') as String?,
        )) {
          _events.add(event);
        }
      } on Object catch (error) {
        _stopPolling();
        _events.add(DVCameraFailed('$error'));
      }
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Stream<DVCameraEvent> get events => _events.stream;
  @override
  Future<List<DVCameraDevice>> devices() async {
    _check();
    final decoded = jsonDecode(bridge.call('devices', []) as String? ?? '[]');
    if (decoded is! List) throw const FormatException('Invalid camera list');
    return [
      for (final item in decoded)
        if (item is Map && item['id'] is String && item['name'] is String)
          for (final lens in DVCameraLens.values)
            if (lens.name == item['lens'])
              DVCameraDevice(
                id: item['id'] as String,
                name: item['name'] as String,
                lens: lens,
              ),
    ];
  }

  @override
  Future<void> open(DVCameraLens lens, {String? device}) async {
    _check();
    if (!capabilities.lenses.contains(lens)) {
      throw UnsupportedError('Native camera does not support ${lens.name}');
    }
    _handle ??= bridge.call('createCamera', [engineId]) as int;
    if (_handle! <= 0) {
      _handle = null;
      throw StateError('Native camera creation failed');
    }
    _call('openCamera', [lens.name, device]);
  }

  @override
  Future<void> close() async {
    _check();
    if (_handle != null) _call('closeCamera');
  }

  @override
  Future<void> takePhoto(String path, {DVFlashMode flash = .off}) async {
    _call('takePhoto', [path, flash.name]);
  }

  @override
  Future<void> startRecording(
    String path, {
    DVVideoQuality quality = .hd720,
    bool audio = true,
  }) async {
    _call('startRecording', [path, quality.name, audio]);
  }

  @override
  Future<void> stopRecording() async {
    _call('stopRecording');
  }

  @override
  Future<void> setTorch(bool on) async {
    _call('setTorch', [on]);
  }

  @override
  Widget buildPreview(BuildContext context) {
    if (_handle == null || _disposed) return const SizedBox.shrink();
    final id = _call('cameraTextureId') as int;
    return id < 0 ? const SizedBox.shrink() : Texture(textureId: id);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _stopPolling();
    try {
      if (_handle != null) _call('disposeCamera');
    } finally {
      _disposed = true;
      await _events.close();
    }
  }
}
