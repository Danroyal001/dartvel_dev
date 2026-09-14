/// In-memory capture backends and permissions, for tests.
library;

import 'dart:async';

import 'capture_backend.dart';

/// A capture device the test drives.
///
/// Writes into the file it was given when it is told the recording stopped,
/// so a test sees a real file of a known size.
final class DVFakeCaptureBackend implements DVCaptureBackend {
  DVFakeCaptureBackend({
    this.capabilities = const DVCaptureCapabilities(
      microphone: true,
      camera: true,
      audioFormats: <DVAudioFormat>{DVAudioFormat.opus, DVAudioFormat.wav},
      videoQualities: <DVVideoQuality>{DVVideoQuality.hd720},
    ),
    this.replaceFile = false,
    this.writeFile,
  });

  @override
  final DVCaptureCapabilities capabilities;

  /// Simulates a device that deletes and recreates its output file, which
  /// gives the new file the process's default permissions.
  final bool replaceFile;

  /// Writes [bytes] to [path], replacing it when [replace]. Supplied by a
  /// test with a filesystem; without one nothing is written.
  final Future<void> Function(String path, List<int> bytes, bool replace)?
      writeFile;

  final StreamController<DVCaptureBackendEvent> _events =
      StreamController<DVCaptureBackendEvent>.broadcast();

  final List<(DVCaptureRequest, String)> starts =
      <(DVCaptureRequest, String)>[];
  int stops = 0;
  int aborts = 0;
  bool disposed = false;
  int bytesWritten = 0;

  @override
  Stream<DVCaptureBackendEvent> get events => _events.stream;

  void _emit(DVCaptureBackendEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void confirmStarted() => _emit(const DVCaptureStarted());

  /// The device closes; writes the recording first.
  Future<void> confirmStopped(Duration duration) async {
    final List<int> bytes = List<int>.filled(1024, 7);
    final Future<void> Function(String, List<int>, bool)? write = writeFile;
    if (write != null && starts.isNotEmpty) {
      await write(starts.last.$2, bytes, replaceFile);
      bytesWritten = bytes.length;
    }
    _emit(DVCaptureStopped(duration));
  }

  void revokePermission() => _emit(const DVCapturePermissionRevoked());

  void loseDevice() => _emit(const DVCaptureDeviceLost());

  void fail(String message) => _emit(DVCaptureFailed(message));

  @override
  Future<void> start(DVCaptureRequest request, String outputPath) async {
    starts.add((request, outputPath));
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> abort() async => aborts++;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Permissions granted by name.
final class DVFakeCapturePermissions implements DVCapturePermissions {
  DVFakeCapturePermissions(this.granted);

  final Set<String> granted;
  final List<String> asked = <String>[];

  @override
  Future<bool> request(String permission) async {
    asked.add(permission);
    return granted.contains(permission);
  }
}
