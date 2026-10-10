/// The player behind `DVBox.video` and `DVBox.audio`.
library;

import 'dart:async';

import '../diagnostics/diagnostics.dart';
import '../lifecycle/lifecycle.dart';
import '../observability/observability.dart';
import 'audio_focus.dart';
import 'captions.dart';
import 'media_cache.dart';
import 'media_signal.dart';
import 'media_source.dart';
import 'now_playing.dart';
import 'player_backend.dart';

/// Where a player is.
enum DVPlaybackState {
  /// Not attached to a backend yet.
  idle,

  /// Attached; the backend is loading the source.
  loading,

  /// Waiting on data, by the backend's own account.
  buffering,

  paused,

  /// Rendering, and the position is advancing.
  playing,

  /// The backend's last word was "playing" and the position has not advanced
  /// for `stallTimeout`. Reported, because a play button that still says
  /// "playing" over a frozen frame is the failure people actually see.
  stalled,

  completed,
  failed,

  /// Released. Nothing on this controller works any more.
  disposed,
}

/// Whether a player may keep playing with the application in the background.
enum DVBackgroundPlayback { none, audio }

/// What a player is wired to. Defaults are the process's own.
final class DVMediaEnvironment {
  DVMediaEnvironment({
    DVLifecycleSignal<DVAppLifecycle>? lifecycle,
    DVAudioFocus? focus,
    DVNowPlaying? nowPlaying,
    this.cache,
    this.captionLoader,
    this.timers = const DVSystemMediaTimers(),
    this.drmAdapters = const <DVDrmAdapter>[],
    this.backgroundAudioDeclared = false,
    DVMediaDiagnosticSink? diagnostics,
    this.stallTimeout = const Duration(seconds: 3),
  })  : lifecycle = lifecycle ?? dvLifecycle.app,
        focus = focus ?? dvAudioFocus,
        nowPlaying = nowPlaying ?? dvNowPlaying,
        diagnostics = diagnostics ?? dvLogMediaDiagnostic;

  final DVLifecycleSignal<DVAppLifecycle> lifecycle;
  final DVAudioFocus focus;

  /// The lock screen and its transport controls. Used by a player given a
  /// [DVMediaSession].
  final DVNowPlaying nowPlaying;

  /// The disk cache progressive `http:` sources are read through, or null
  /// where there is none (a browser, whose HTTP cache does this).
  final DVMediaCache? cache;

  /// Reads a caption file's text. Supplied by the Flutter runtime, which can
  /// read assets as well as URLs; without one a source track cannot load.
  final Future<String> Function(DVMediaSource source)? captionLoader;
  final DVMediaTimers timers;
  final List<DVDrmAdapter> drmAdapters;

  /// Whether the build declared the platform capability background audio
  /// needs -- `UIBackgroundModes: audio`, a media-playback foreground service.
  final bool backgroundAudioDeclared;

  final DVMediaDiagnosticSink diagnostics;
  final Duration stallTimeout;
}

/// Logs [code] at the level the diagnostic registry assigns it.
void dvLogMediaDiagnostic(String code, String message) {
  final String level = DVDiagnostics.find(code)?.level ?? 'warning';
  DVObservability.log(
    '$code: $message',
    level: switch (level) {
      'debug' => DVLogLevel.debug,
      'info' => DVLogLevel.info,
      'error' => DVLogLevel.error,
      _ => DVLogLevel.warn,
    },
    code: code,
  );
}

/// Protected content, and no adapter on this target for its scheme.
final class DVMediaDrmUnavailable implements Exception {
  const DVMediaDrmUnavailable(this.scheme);
  final DVDrmScheme scheme;

  @override
  String toString() => 'DVMediaDrmUnavailable: no DRM adapter for '
      '${scheme.name} is configured for this target (DV-MEDIA-102)';
}

/// Picture-in-picture was asked of a player whose target has none.
final class DVMediaPictureInPictureUnavailable implements Exception {
  const DVMediaPictureInPictureUnavailable();

  @override
  String toString() => 'DVMediaPictureInPictureUnavailable: this target '
      'cannot show this player in picture-in-picture';
}

/// An adaptive stream, a backend that cannot play one, and no progressive
/// rendition to fall back to.
final class DVMediaStreamingUnsupported implements Exception {
  const DVMediaStreamingUnsupported(this.source);
  final DVMediaSource source;

  @override
  String toString() => 'DVMediaStreamingUnsupported: this target cannot play '
      'the adaptive stream ${source.reference} and the source names no '
      'progressive rendition';
}

/// A handle on a player.
///
/// Signals read the session this handle drives or follows. A handle and a
/// session are separate so `DVBox.video(source).controller` can be taken
/// before the box is mounted, and a box rebuilt by its parent can hand its new
/// handle to the player already running instead of starting another one.
final class DVMediaController {
  DVMediaController(
    this.source, {
    this.background = DVBackgroundPlayback.none,
    this.session,
    this.captions,
    DVMediaEnvironment? environment,
  }) : environment = environment ?? DVMediaEnvironment() {
    _own = _DVMediaSession(this);
    _session = _own;
    _state = DVForwardingMediaSignal<DVPlaybackState>(_own.state);
    _position = DVForwardingMediaSignal<Duration>(_own.position);
    _duration = DVForwardingMediaSignal<Duration>(_own.duration);
    _buffered = DVForwardingMediaSignal<List<DVRange>>(_own.buffered);
    _error = DVForwardingMediaSignal<String?>(_own.error);
    _videoSize = DVForwardingMediaSignal<(int, int)?>(_own.videoSize);
    _pip = DVForwardingMediaSignal<bool>(_own.pictureInPicture);
    _captionTrack = DVForwardingMediaSignal<String?>(_own.captionTrack);
    _caption = DVForwardingMediaSignal<String?>(_own.caption);
    _captionError = DVForwardingMediaSignal<String?>(_own.captionError);
  }

  final DVMediaSource source;
  final DVBackgroundPlayback background;
  final DVMediaEnvironment environment;

  /// What the lock screen shows while this player holds it. Null keeps the
  /// player off the now-playing surface.
  final DVMediaSession? session;

  /// The caption tracks this player offers.
  final DVCaptions? captions;

  late final _DVMediaSession _own;
  late _DVMediaSession _session;
  late final DVForwardingMediaSignal<DVPlaybackState> _state;
  late final DVForwardingMediaSignal<Duration> _position;
  late final DVForwardingMediaSignal<Duration> _duration;
  late final DVForwardingMediaSignal<List<DVRange>> _buffered;
  late final DVForwardingMediaSignal<String?> _error;
  late final DVForwardingMediaSignal<(int, int)?> _videoSize;
  late final DVForwardingMediaSignal<bool> _pip;
  late final DVForwardingMediaSignal<String?> _captionTrack;
  late final DVForwardingMediaSignal<String?> _caption;
  late final DVForwardingMediaSignal<String?> _captionError;
  bool _released = false;

  /// How long "playing" may go without the position advancing before the
  /// state says [DVPlaybackState.stalled].
  Duration get stallTimeout => environment.stallTimeout;

  DVMediaSignal<DVPlaybackState> get state => _state;

  /// Where playback is. Moves to a seek's target the moment it is issued and
  /// ignores reports measured before the backend completed that seek.
  DVMediaSignal<Duration> get position => _position;

  /// Zero until the source is loaded, and for a live stream.
  DVMediaSignal<Duration> get duration => _duration;

  DVMediaSignal<List<DVRange>> get buffered => _buffered;

  /// Why the player failed, or null.
  DVMediaSignal<String?> get error => _error;

  /// The decoded picture's width and height, once the backend reports it.
  DVMediaSignal<(int, int)?> get videoSize => _videoSize;

  /// Whether the video is floating in picture-in-picture, as the platform
  /// reports it.
  DVMediaSignal<bool> get pictureInPicture => _pip;

  /// The language of the captions showing, or null when none are.
  DVMediaSignal<String?> get captionTrack => _captionTrack;

  /// The caption text for the current position, or null.
  DVMediaSignal<String?> get caption => _caption;

  /// Why the last caption track asked for could not be shown, or null.
  DVMediaSignal<String?> get captionError => _captionError;

  /// Whether [enterPictureInPicture] can work on this target.
  bool get canPictureInPicture {
    final DVMediaPlayerBackend? b = _session.backend;
    return b is DVMediaPictureInPictureBackend &&
        b.capabilities.pictureInPicture;
  }

  /// Floats the video over other applications. Throws
  /// [DVMediaPictureInPictureUnavailable] where the target has no such
  /// thing; [pictureInPicture] moves when the platform confirms.
  Future<void> enterPictureInPicture() async {
    _checkUsable();
    if (!canPictureInPicture) {
      throw const DVMediaPictureInPictureUnavailable();
    }
    final bool accepted = await (_session.backend!
            as DVMediaPictureInPictureBackend)
        .enterPictureInPicture();
    if (!accepted) throw const DVMediaPictureInPictureUnavailable();
  }

  Future<void> exitPictureInPicture() async {
    _checkUsable();
    final DVMediaPlayerBackend? b = _session.backend;
    if (b is DVMediaPictureInPictureBackend) await b.exitPictureInPicture();
  }

  /// Shows the captions in [language], or none when null. Throws
  /// [ArgumentError] for a language [captions] does not offer.
  Future<void> setCaptionTrack(String? language) {
    _checkUsable();
    if (language != null && _session.owner.captions?.trackFor(language) == null) {
      throw ArgumentError.value(language, 'language', 'no such caption track');
    }
    return _session.selectCaptions(language);
  }

  /// Whether this handle drives a session rather than following another's.
  bool get isAttached => identical(_session, _own) && _own.backend != null;

  /// Loads [source] into [backend] and starts observing the application.
  ///
  /// Refuses protected content with no adapter for its scheme
  /// ([DVMediaDrmUnavailable], `DV-MEDIA-102`), and an adaptive stream this
  /// backend cannot play with no progressive rendition
  /// ([DVMediaStreamingUnsupported]); in both cases the backend is never
  /// handed the source.
  Future<void> attach(DVMediaPlayerBackend backend) async {
    _checkUsable();
    if (!identical(_session, _own)) {
      throw StateError('This controller follows another player; it has no '
          'session of its own to attach.');
    }
    return _own.attach(backend);
  }

  /// Makes this handle read and drive [owner]'s session.
  ///
  /// Signals already taken from this handle move with it. When the owner is
  /// disposed, this handle reads [DVPlaybackState.disposed].
  void follow(DVMediaController owner) {
    _checkUsable();
    if (_own.backend != null) {
      throw StateError('An attached controller cannot follow another.');
    }
    final _DVMediaSession target = owner._session;
    if (identical(target, _own)) return;
    _session = target;
    _state.retarget(target.state);
    _position.retarget(target.position);
    _duration.retarget(target.duration);
    _buffered.retarget(target.buffered);
    _error.retarget(target.error);
    _videoSize.retarget(target.videoSize);
    _pip.retarget(target.pictureInPicture);
    _captionTrack.retarget(target.captionTrack);
    _caption.retarget(target.caption);
    _captionError.retarget(target.captionError);
  }

  Future<void> play() async {
    _checkUsable();
    return _session.play();
  }

  Future<void> pause() async {
    _checkUsable();
    return _session.pause();
  }

  /// Moves to [position], clamped to the duration once it is known.
  ///
  /// Completes when the backend confirms this seek or a later one.
  Future<void> seek(Duration position) async {
    _checkUsable();
    return _session.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _checkUsable();
    return _session.setVolume(volume);
  }

  /// Releases this handle. A handle that owns its session releases the
  /// backend, audio focus, timers and the lifecycle subscription; one that
  /// follows another stops following and leaves that player alone.
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    if (!identical(_session, _own)) {
      _session = _own;
      _state.retarget(_own.state);
      _position.retarget(_own.position);
      _duration.retarget(_own.duration);
      _buffered.retarget(_own.buffered);
      _error.retarget(_own.error);
    _videoSize.retarget(_own.videoSize);
    _pip.retarget(_own.pictureInPicture);
    _captionTrack.retarget(_own.captionTrack);
    _caption.retarget(_own.caption);
    _captionError.retarget(_own.captionError);
    }
    await _own.dispose();
  }

  void _checkUsable() {
    if (_released || _session.isDisposed) {
      throw StateError('This media controller has been disposed.');
    }
  }
}

final class _DVMediaSession {
  _DVMediaSession(this.owner);

  final DVMediaController owner;

  final DVMutableMediaSignal<DVPlaybackState> state =
      DVMutableMediaSignal<DVPlaybackState>(DVPlaybackState.idle);
  final DVMutableMediaSignal<Duration> position =
      DVMutableMediaSignal<Duration>(Duration.zero);
  final DVMutableMediaSignal<Duration> duration =
      DVMutableMediaSignal<Duration>(Duration.zero);
  final DVMutableMediaSignal<List<DVRange>> buffered =
      DVMutableMediaSignal<List<DVRange>>(const <DVRange>[]);
  final DVMutableMediaSignal<String?> error =
      DVMutableMediaSignal<String?>(null);
  final DVMutableMediaSignal<(int, int)?> videoSize =
      DVMutableMediaSignal<(int, int)?>(null);
  final DVMutableMediaSignal<bool> pictureInPicture =
      DVMutableMediaSignal<bool>(false);
  final DVMutableMediaSignal<String?> captionTrack =
      DVMutableMediaSignal<String?>(null);
  final DVMutableMediaSignal<String?> caption =
      DVMutableMediaSignal<String?>(null);
  final DVMutableMediaSignal<String?> captionError =
      DVMutableMediaSignal<String?>(null);

  final Map<String, DVCaptionTrack> _loadedTracks = <String, DVCaptionTrack>{};
  DVCaptionTrack? _shownTrack;
  StreamSubscription<DVPlaybackState>? _nowPlayingStates;

  DVMediaPlayerBackend? backend;
  StreamSubscription<DVMediaBackendEvent>? _events;
  StreamSubscription<DVAppLifecycle>? _lifecycle;
  DVMediaTimer? _watchdog;

  /// The generation of the last seek issued, and of the last one the backend
  /// confirmed.
  int _seekIssued = 0;
  final Map<int, Completer<void>> _seeks = <int, Completer<void>>{};

  /// Whether the application asked for playback and has not since paused.
  bool _wantsPlayback = false;

  DVMediaEnvironment get _env => owner.environment;

  bool get isDisposed => state.value == DVPlaybackState.disposed;

  Future<void> attach(DVMediaPlayerBackend backend) async {
    if (this.backend != null) {
      throw StateError('This controller is already attached to a backend.');
    }
    final DVMediaSource source = owner.source;

    DVDrmAdapter? adapter;
    final DVDrmProtection? protection = source.protection;
    if (protection != null) {
      for (final DVDrmAdapter candidate in _env.drmAdapters) {
        if (candidate.schemes.contains(protection.scheme)) {
          adapter = candidate;
          break;
        }
      }
      if (adapter == null) {
        _fail('no DRM adapter for ${protection.scheme.name}');
        _env.diagnostics(
          'DV-MEDIA-102',
          '${source.reference} is protected by ${protection.scheme.name} and '
              'no DRM adapter for it is configured for this target',
        );
        throw DVMediaDrmUnavailable(protection.scheme);
      }
    }

    DVMediaSource resolved = source;
    if (source.isAdaptive && !backend.capabilities.adaptiveStreaming) {
      final DVMediaSource? progressive = source.progressiveRendition;
      if (progressive == null) {
        _fail('adaptive streaming is not supported on this target');
        throw DVMediaStreamingUnsupported(source);
      }
      resolved = progressive;
      _env.diagnostics(
        'DV-MEDIA-101',
        '${source.reference} is adaptive and this target has no streaming '
            'support; playing ${progressive.reference}',
      );
    }

    if (owner.background != DVBackgroundPlayback.none &&
        !_env.backgroundAudioDeclared) {
      _env.diagnostics(
        'DV-MEDIA-103',
        'background audio requested for ${source.reference} but the platform '
            'capability is not declared; playback pauses in the background',
      );
    }

    final DVMediaCache? cache = _env.cache;
    if (cache != null &&
        resolved.kind == DVMediaSourceKind.url &&
        resolved.cache &&
        !resolved.isAdaptive) {
      resolved = DVMediaSource.url(
        await cache.playbackAddress(resolved.reference),
        streaming: DVMediaStreaming.progressive,
        protection: resolved.protection,
        cache: false,
      );
    }

    this.backend = backend;
    state.set(DVPlaybackState.loading);
    final String? firstTrack = owner.captions?.initialTrack?.language;
    if (firstTrack != null) unawaited(selectCaptions(firstTrack));
    _events = backend.events.listen(_onEvent);
    _lifecycle = _env.lifecycle.listen(_onLifecycle);

    final Object? license =
        adapter == null ? null : await adapter.license(source);
    if (isDisposed) return;
    await backend.open(resolved, license: license);
  }

  bool get _mayPlayInBackground =>
      owner.background == DVBackgroundPlayback.audio &&
      _env.backgroundAudioDeclared &&
      (backend?.capabilities.backgroundAudio ?? false);

  void _onLifecycle(DVAppLifecycle app) {
    if (isDisposed) return;
    if (app != DVAppLifecycle.backgrounded &&
        app != DVAppLifecycle.suspended &&
        app != DVAppLifecycle.shuttingDown) {
      return;
    }
    if (app != DVAppLifecycle.shuttingDown && _mayPlayInBackground) return;
    final bool active = _wantsPlayback ||
        state.value == DVPlaybackState.playing ||
        state.value == DVPlaybackState.buffering ||
        state.value == DVPlaybackState.stalled;
    if (active) unawaited(_pauseInternal());
  }

  void _onEvent(DVMediaBackendEvent event) {
    // Failed is terminal for this session. A report that arrives after it --
    // a backend answering a play request, one already queued -- describes
    // nothing the application can use, and reviving the state would show a
    // Pause button over a decoder that is not there.
    if (isDisposed || state.value == DVPlaybackState.failed) return;
    switch (event) {
      case DVMediaReady(:final Duration duration):
        this.duration.set(duration);
        if (state.value == DVPlaybackState.loading) {
          state.set(DVPlaybackState.paused);
        }
      case DVMediaPlaying():
        state.set(DVPlaybackState.playing);
        _armWatchdog();
      case DVMediaPaused():
        _cancelWatchdog();
        state.set(DVPlaybackState.paused);
      case DVMediaBuffering():
        _cancelWatchdog();
        state.set(DVPlaybackState.buffering);
      case DVMediaPosition(:final Duration position, :final int seek):
        if (seek < _seekIssued) return;
        final bool advanced = position != this.position.value;
        this.position.set(position);
        _updateCue();
        if (!advanced) return;
        if (state.value == DVPlaybackState.stalled) {
          state.set(DVPlaybackState.playing);
        }
        if (state.value == DVPlaybackState.playing) _armWatchdog();
      case DVMediaBuffered(:final List<DVRange> ranges):
        buffered.set(List<DVRange>.unmodifiable(ranges));
      case DVMediaSeekCompleted(:final int generation, :final Duration position):
        if (generation >= _seekIssued) {
          this.position.set(position);
          _updateCue();
          _publishNowPlaying();
          if (state.value == DVPlaybackState.playing ||
              state.value == DVPlaybackState.stalled) {
            state.set(DVPlaybackState.playing);
            _armWatchdog();
          }
        }
        final List<int> done =
            _seeks.keys.where((int g) => g <= generation).toList();
        for (final int g in done) {
          _seeks.remove(g)!.complete();
        }
      case DVMediaCompleted():
        _cancelWatchdog();
        _wantsPlayback = false;
        state.set(DVPlaybackState.completed);
        unawaited(_env.focus.release(owner));
      case DVMediaFailed(:final String message):
        _fail(message);
      case DVMediaVideoSize(:final int width, :final int height):
        videoSize.set((width, height));
      case DVMediaPictureInPictureChanged(:final bool active):
        pictureInPicture.set(active);
    }
  }

  // --- captions --------------------------------------------------------

  Future<void> selectCaptions(String? language) async {
    if (language == null) {
      _shownTrack = null;
      captionTrack.set(null);
      caption.set(null);
      return;
    }
    DVCaptionTrack? track = _loadedTracks[language];
    if (track == null) {
      final DVCaptionTrack? offered = owner.captions?.trackFor(language);
      if (offered == null) return;
      if (offered.isLoaded) {
        track = offered;
      } else {
        final Future<String> Function(DVMediaSource)? load = _env.captionLoader;
        if (load == null) {
          captionError.set('no caption loader is bound for this target');
          return;
        }
        try {
          final String text = await load(offered.source!);
          track = offered.withCues(DVCaptions.parse(text));
        } on Object catch (error) {
          if (!isDisposed) captionError.set('$error');
          return;
        }
      }
      _loadedTracks[language] = track;
    }
    if (isDisposed) return;
    captionError.set(null);
    _shownTrack = track;
    captionTrack.set(language);
    _updateCue();
  }

  void _updateCue() {
    final DVCaptionTrack? track = _shownTrack;
    caption.set(track?.cueAt(position.value)?.text);
  }

  // --- now playing -----------------------------------------------------

  DVNowPlayingState get _nowPlayingState => DVNowPlayingState(
        playing: state.value == DVPlaybackState.playing ||
            state.value == DVPlaybackState.buffering,
        position: position.value,
        duration: duration.value,
      );

  Future<void> _claimNowPlaying() async {
    final DVMediaSession? session = owner.session;
    if (session == null || isDisposed) return;
    _nowPlayingStates ??= state.changes.listen((_) => _publishNowPlaying());
    await _env.nowPlaying.claim(owner, session, _nowPlayingState,
        onCommand: _onCommand);
  }

  void _publishNowPlaying() {
    if (owner.session == null || isDisposed) return;
    unawaited(_env.nowPlaying.update(owner, _nowPlayingState));
  }

  void _onCommand(DVMediaCommand command) {
    if (isDisposed || backend == null) return;
    final Duration step = owner.session?.skipInterval ?? const Duration(seconds: 10);
    final bool active = state.value == DVPlaybackState.playing ||
        state.value == DVPlaybackState.buffering ||
        state.value == DVPlaybackState.stalled;
    Future<void> run() async {
      switch (command.action) {
        case DVTransportAction.play:
          await play();
        case DVTransportAction.pause:
          await pause();
        case DVTransportAction.togglePlay:
          await (active ? pause() : play());
        case DVTransportAction.stop:
          await pause();
          unawaited(seek(Duration.zero));
        case DVTransportAction.seekForward:
          unawaited(seek(position.value + step));
        case DVTransportAction.seekBackward:
          unawaited(seek(position.value - step));
        case DVTransportAction.seekTo:
          final Duration? to = command.position;
          if (to != null) unawaited(seek(to));
      }
    }

    unawaited(run().catchError((Object _) {}));
  }

  void _fail(String message) {
    _cancelWatchdog();
    _wantsPlayback = false;
    error.set(message);
    state.set(DVPlaybackState.failed);
    unawaited(_env.focus.release(owner));
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = _env.timers.start(_env.stallTimeout, () {
      _watchdog = null;
      if (state.value == DVPlaybackState.playing) {
        state.set(DVPlaybackState.stalled);
      }
    });
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  DVMediaPlayerBackend _attached() {
    final DVMediaPlayerBackend? b = backend;
    if (b == null) {
      throw StateError('This media controller is not attached to a backend; '
          'mount the box that owns it first.');
    }
    return b;
  }

  Future<void> play() async {
    final DVMediaPlayerBackend b = _attached();
    final bool granted = await _env.focus.acquire(owner, onLoss: () {
      if (!isDisposed) unawaited(_pauseInternal(releaseFocus: false));
    });
    if (!granted) throw const DVAudioFocusRefused();
    if (isDisposed) return;
    _wantsPlayback = true;
    await _claimNowPlaying();
    await b.play();
  }

  Future<void> pause() {
    _attached();
    return _pauseInternal();
  }

  Future<void> _pauseInternal({bool releaseFocus = true}) async {
    final DVMediaPlayerBackend? b = backend;
    _wantsPlayback = false;
    if (releaseFocus) await _env.focus.release(owner);
    if (b == null || isDisposed) return;
    await b.pause();
  }

  Future<void> seek(Duration target) {
    final DVMediaPlayerBackend b = _attached();
    Duration clamped = target < Duration.zero ? Duration.zero : target;
    final Duration known = duration.value;
    if (known > Duration.zero && clamped > known) clamped = known;
    final int generation = ++_seekIssued;
    final Completer<void> done = Completer<void>();
    _seeks[generation] = done;
    position.set(clamped);
    _updateCue();
    unawaited(b.seek(clamped, generation));
    return done.future;
  }

  Future<void> setVolume(double volume) =>
      _attached().setVolume(volume.clamp(0.0, 1.0));

  Future<void> dispose() async {
    if (isDisposed) return;
    _cancelWatchdog();
    _wantsPlayback = false;
    state.set(DVPlaybackState.disposed);
    for (final Completer<void> pending in _seeks.values) {
      pending.complete();
    }
    _seeks.clear();
    // Not awaited. A cancel returns an already-completed future from the
    // root zone, and waiting on it here held the backend open until some
    // unrelated turn of the event loop -- forever, under a fake clock.
    unawaited(_lifecycle?.cancel());
    unawaited(_events?.cancel());
    unawaited(_nowPlayingStates?.cancel());
    await _env.nowPlaying.release(owner);
    await _env.focus.release(owner);
    final DVMediaPlayerBackend? b = backend;
    if (b != null) await b.dispose();
    await Future.wait(<Future<void>>[
      state.close(),
      position.close(),
      duration.close(),
      buffered.close(),
      error.close(),
      videoSize.close(),
      pictureInPicture.close(),
      captionTrack.close(),
      caption.close(),
      captionError.close(),
    ]);
  }
}
