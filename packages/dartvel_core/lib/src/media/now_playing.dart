/// The operating system's now-playing surface: the lock screen, the control
/// centre, a notification with transport buttons, a headset's buttons, a
/// car's display.
///
/// One player at a time, like audio focus, and the same one: the player that
/// last started is what the lock screen shows and what its buttons drive. A
/// player that publishes nothing is not on it. The failure being prevented is
/// a lock screen that shows an episode the application stopped playing an
/// hour ago, whose play button starts nothing -- or starts the wrong thing.
library;

import 'dart:async';

/// What a remote-control key, a lock-screen button or a headset asks of a
/// player.
enum DVTransportAction {
  togglePlay,
  play,
  pause,
  stop,
  seekForward,
  seekBackward,

  /// To an absolute position: a lock-screen scrubber.
  seekTo,
}

/// One request from the now-playing surface.
final class DVMediaCommand {
  const DVMediaCommand(this.action, {this.position});

  final DVTransportAction action;

  /// For [DVTransportAction.seekTo].
  final Duration? position;

  @override
  bool operator ==(Object other) =>
      other is DVMediaCommand &&
      other.action == action &&
      other.position == position;

  @override
  int get hashCode => Object.hash(action, position);

  @override
  String toString() => 'DVMediaCommand(${action.name}'
      '${position == null ? '' : ', $position'})';
}

/// What a player publishes to the now-playing surface.
///
/// `DVBox.audio(source, session: DVMediaSession(title: episode.title))`.
/// Declared on the player rather than pushed from a page, so the lock screen
/// is never out of step with what is playing.
final class DVMediaSession {
  const DVMediaSession({
    required this.title,
    this.artist,
    this.album,
    this.artworkUrl,
    this.skipInterval = const Duration(seconds: 10),
  });

  final String title;
  final String? artist;
  final String? album;

  /// An `https:` URL or a file path the platform can read the artwork from.
  final String? artworkUrl;

  /// How far the skip buttons move.
  final Duration skipInterval;

  @override
  bool operator ==(Object other) =>
      other is DVMediaSession &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artworkUrl == artworkUrl &&
      other.skipInterval == skipInterval;

  @override
  int get hashCode => Object.hash(title, artist, album, artworkUrl, skipInterval);
}

/// Where playback is, for the now-playing surface. The platform extrapolates
/// the position from [playing] between updates, so this is published when
/// something changes rather than on every position report.
final class DVNowPlayingState {
  const DVNowPlayingState({
    required this.playing,
    required this.position,
    required this.duration,
  });

  final bool playing;
  final Duration position;

  /// Zero for a live stream.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is DVNowPlayingState &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(playing, position, duration);

  @override
  String toString() =>
      'DVNowPlayingState(playing: $playing, $position / $duration)';
}

/// The platform half: MediaSession on Android, MPNowPlayingInfoCenter on
/// Apple platforms, `navigator.mediaSession` in a browser, MPRIS on Linux.
abstract interface class DVNowPlayingBackend {
  Future<void> publish(DVMediaSession session, DVNowPlayingState state);

  /// Takes the application off the now-playing surface.
  Future<void> clear();

  /// What the person pressed.
  Stream<DVMediaCommand> get commands;
}

/// A target with no now-playing surface. Publishing is a no-op, which is the
/// truth: there is nowhere to publish to.
final class DVNoNowPlayingBackend implements DVNowPlayingBackend {
  const DVNoNowPlayingBackend();

  @override
  Future<void> publish(DVMediaSession session, DVNowPlayingState state) async {}

  @override
  Future<void> clear() async {}

  @override
  Stream<DVMediaCommand> get commands => const Stream<DVMediaCommand>.empty();
}

/// Who is on the now-playing surface.
final class DVNowPlaying {
  DVNowPlaying([DVNowPlayingBackend backend = const DVNoNowPlayingBackend()])
      : _backend = backend {
    _commands = backend.commands.listen(_command);
  }

  final DVNowPlayingBackend _backend;
  late final StreamSubscription<DVMediaCommand> _commands;

  Object? _owner;
  void Function(DVMediaCommand)? _onCommand;
  DVMediaSession? _session;
  DVNowPlayingState? _last;

  /// The player on the surface, or null.
  Object? get owner => _owner;

  /// Puts [owner] on the surface with [session]; the previous owner, if any,
  /// stops receiving commands.
  Future<void> claim(
    Object owner,
    DVMediaSession session,
    DVNowPlayingState state, {
    required void Function(DVMediaCommand command) onCommand,
  }) async {
    _owner = owner;
    _onCommand = onCommand;
    _session = session;
    _last = state;
    await _backend.publish(session, state);
  }

  /// Publishes [state] if [owner] is on the surface and anything changed.
  Future<void> update(Object owner, DVNowPlayingState state) async {
    final DVMediaSession? session = _session;
    if (!identical(owner, _owner) || session == null || state == _last) return;
    _last = state;
    await _backend.publish(session, state);
  }

  /// Takes [owner] off the surface. A no-op for a player that is not on it,
  /// so one that lost the surface to another cannot clear that one.
  Future<void> release(Object owner) async {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _onCommand = null;
    _session = null;
    _last = null;
    await _backend.clear();
  }

  void _command(DVMediaCommand command) => _onCommand?.call(command);

  Future<void> dispose() => _commands.cancel();
}

/// The process's now-playing surface, used by players that were not given
/// one. Nothing is published until a binding supplies a backend.
DVNowPlaying dvNowPlaying = DVNowPlaying();
