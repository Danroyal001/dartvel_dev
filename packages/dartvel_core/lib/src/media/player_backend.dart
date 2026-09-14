/// The contract between the player state machine and whatever decodes.
///
/// A backend is a platform player -- ExoPlayer through JNI, AVPlayer, a
/// GStreamer pipeline over FFI, a `<video>` element, a vendor television
/// player. It reports what happened; the controller decides what that means
/// for the signals. Keeping the judgement out of the backends is what stops
/// six of them each deciding differently whether a stalled decoder is
/// "playing".
library;

import 'dart:async';

import 'media_source.dart';

/// What a backend on this target can do. Reported, never assumed.
final class DVMediaBackendCapabilities {
  const DVMediaBackendCapabilities({
    this.adaptiveStreaming = true,
    this.backgroundAudio = false,
    this.pictureInPicture = false,
    this.video = true,
  });

  /// Plays HLS/DASH manifests itself.
  final bool adaptiveStreaming;

  /// Can keep playing while the application is in the background.
  final bool backgroundAudio;

  final bool pictureInPicture;

  /// Can render frames rather than audio alone.
  final bool video;
}

/// A platform player.
abstract interface class DVMediaPlayerBackend {
  DVMediaBackendCapabilities get capabilities;

  /// What happened. Subscribed once per attach; cancelled on dispose.
  Stream<DVMediaBackendEvent> get events;

  /// Loads [source]. [license] is whatever a `DVDrmAdapter` produced.
  Future<void> open(DVMediaSource source, {Object? license});

  Future<void> play();

  Future<void> pause();

  /// Moves to [position]. [generation] is echoed back on the
  /// [DVMediaSeekCompleted] that confirms it and on every [DVMediaPosition]
  /// after, which is how a report that was already in flight when the seek
  /// was issued is told apart from one that describes where playback now is.
  Future<void> seek(Duration position, int generation);

  Future<void> setVolume(double volume);

  /// Releases the decoder, the surface and anything else the player holds.
  Future<void> dispose();
}

/// Something a backend reports.
sealed class DVMediaBackendEvent {
  const DVMediaBackendEvent();
}

/// Loaded and able to play; paused.
final class DVMediaReady extends DVMediaBackendEvent {
  const DVMediaReady({required this.duration});

  /// Zero for a live stream with no end.
  final Duration duration;
}

/// Frames or samples are actually being rendered.
final class DVMediaPlaying extends DVMediaBackendEvent {
  const DVMediaPlaying();
}

final class DVMediaPaused extends DVMediaBackendEvent {
  const DVMediaPaused();
}

/// Waiting on data, by the backend's own account.
final class DVMediaBuffering extends DVMediaBackendEvent {
  const DVMediaBuffering();
}

/// Where playback is, as of the last seek the backend has completed.
final class DVMediaPosition extends DVMediaBackendEvent {
  const DVMediaPosition(this.position, {this.seek = 0});

  final Duration position;

  /// The generation of the most recent seek this backend had completed when
  /// it measured [position]. Zero before any seek.
  final int seek;
}

final class DVMediaBuffered extends DVMediaBackendEvent {
  const DVMediaBuffered(this.ranges);
  final List<DVRange> ranges;
}

final class DVMediaSeekCompleted extends DVMediaBackendEvent {
  const DVMediaSeekCompleted(this.generation, this.position);
  final int generation;
  final Duration position;
}

final class DVMediaCompleted extends DVMediaBackendEvent {
  const DVMediaCompleted();
}

final class DVMediaFailed extends DVMediaBackendEvent {
  const DVMediaFailed(this.message);
  final String message;
}
