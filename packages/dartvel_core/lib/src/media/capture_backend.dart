/// The contract between a capture session and the device.
///
/// A backend is MediaRecorder through JNI, AVCaptureSession, a GStreamer
/// pipeline over FFI, `MediaRecorder` in a browser. It reports what the device
/// did; the session decides what that means for `capturing` and for the
/// recording it hands back.
library;

import 'dart:async';

/// Audio container/codec pairs a recording can be asked for.
enum DVAudioFormat {
  /// AAC in an MPEG-4 container (`.m4a`).
  aac,

  /// Opus in Ogg (`.ogg`).
  opus,

  /// Uncompressed PCM (`.wav`).
  wav,
}

/// Video recording presets.
enum DVVideoQuality { sd480, hd720, hd1080 }

enum DVCaptureKind { audio, video }

/// What this target's capture backend can record. Reported, never assumed.
final class DVCaptureCapabilities {
  const DVCaptureCapabilities({
    this.microphone = false,
    this.camera = false,
    this.audioFormats = const <DVAudioFormat>{},
    this.videoQualities = const <DVVideoQuality>{},
  });

  /// Nothing: the answer on a target with no capture binding.
  static const DVCaptureCapabilities none = DVCaptureCapabilities();

  final bool microphone;
  final bool camera;
  final Set<DVAudioFormat> audioFormats;
  final Set<DVVideoQuality> videoQualities;
}

/// What was asked for.
final class DVCaptureRequest {
  const DVCaptureRequest.audio({
    this.audioFormat = DVAudioFormat.aac,
    this.maxDuration,
  })  : kind = DVCaptureKind.audio,
        videoQuality = null;

  const DVCaptureRequest.video({
    this.videoQuality = DVVideoQuality.hd720,
    this.maxDuration,
  })  : kind = DVCaptureKind.video,
        audioFormat = null;

  final DVCaptureKind kind;
  final DVAudioFormat? audioFormat;
  final DVVideoQuality? videoQuality;

  /// The session stops the device itself when this much has been recorded.
  final Duration? maxDuration;

  /// The runtime permissions this needs, in the order they are asked.
  List<String> get permissions => kind == DVCaptureKind.audio
      ? const <String>['microphone']
      : const <String>['camera', 'microphone'];

  String get extension => switch (kind) {
        DVCaptureKind.video => 'mp4',
        DVCaptureKind.audio => switch (audioFormat!) {
            DVAudioFormat.aac => 'm4a',
            DVAudioFormat.opus => 'ogg',
            DVAudioFormat.wav => 'wav',
          },
      };

  String get mimeType => switch (kind) {
        DVCaptureKind.video => 'video/mp4',
        DVCaptureKind.audio => switch (audioFormat!) {
            DVAudioFormat.aac => 'audio/mp4',
            DVAudioFormat.opus => 'audio/ogg',
            DVAudioFormat.wav => 'audio/wav',
          },
      };

  /// Why [capabilities] cannot satisfy this, or null when they can.
  String? unsupportedBy(DVCaptureCapabilities capabilities) {
    switch (kind) {
      case DVCaptureKind.audio:
        if (!capabilities.microphone) return 'this target has no microphone';
        if (!capabilities.audioFormats.contains(audioFormat)) {
          return 'this target cannot record ${audioFormat!.name} audio';
        }
      case DVCaptureKind.video:
        if (!capabilities.camera) return 'this target has no camera';
        if (!capabilities.videoQualities.contains(videoQuality)) {
          return 'this target cannot record ${videoQuality!.name} video';
        }
    }
    return null;
  }
}

/// A capture device.
abstract interface class DVCaptureBackend {
  DVCaptureCapabilities get capabilities;

  Stream<DVCaptureBackendEvent> get events;

  /// Opens the device and records into [outputPath], which already exists and
  /// is private to the application. Write into it; do not replace it.
  Future<void> start(DVCaptureRequest request, String outputPath);

  /// Stops and finalises the file. Confirmed by [DVCaptureStopped].
  Future<void> stop();

  /// Stops without finalising. The session discards the file.
  Future<void> abort();

  /// Releases the device. After this completes the device is closed.
  Future<void> dispose();
}

/// Something the device reports.
sealed class DVCaptureBackendEvent {
  const DVCaptureBackendEvent();
}

/// The device is open and recording.
final class DVCaptureStarted extends DVCaptureBackendEvent {
  const DVCaptureStarted();
}

/// The device is closed and the file finalised.
final class DVCaptureStopped extends DVCaptureBackendEvent {
  const DVCaptureStopped(this.duration);
  final Duration duration;
}

/// The operating system withdrew the permission while recording.
final class DVCapturePermissionRevoked extends DVCaptureBackendEvent {
  const DVCapturePermissionRevoked();
}

/// The device went away: unplugged, taken by another application.
final class DVCaptureDeviceLost extends DVCaptureBackendEvent {
  const DVCaptureDeviceLost();
}

final class DVCaptureFailed extends DVCaptureBackendEvent {
  const DVCaptureFailed(this.message);
  final String message;
}

/// The runtime permission flow, as capture uses it.
abstract interface class DVCapturePermissions {
  /// Asks for [permission]; true when granted.
  Future<bool> request(String permission);
}

/// Where recordings are written.
abstract interface class DVCaptureFiles {
  /// Creates an empty file only this application can read, and returns its
  /// path.
  Future<String> reserve(String extension);

  /// Makes sure [path] is still private after the device wrote it, and
  /// returns its size.
  Future<int> seal(String path);

  /// Deletes [path], if it exists.
  Future<void> discard(String path);
}
