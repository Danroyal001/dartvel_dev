/// The widget half of `DVBox.video` and `DVBox.audio`, the registry native
/// bindings put their players in, and remote-control transport keys.
///
/// The player itself -- its state machine, lifecycle and audio-focus coupling,
/// DRM and streaming refusals -- is `DVMediaController` in dartvel_core. This
/// file decides who owns one: the box's element does, so a page that goes
/// away takes its player with it.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../dartvel_flutter.dart' show DV, DVRenderSurface;
import 'caption_file.dart';
import 'image_view.dart';
import 'web_media_mapping.dart';

/// Whether a box plays video or audio.
enum DVMediaKind { video, audio }

/// Makes a platform player for [source].
typedef DVMediaPlayerFactory = DVMediaPlayerBackend Function(
    DVMediaSource source, DVMediaKind kind);

/// A backend that draws frames. A player backend implements this when it
/// renders video into Flutter; one that does not plays audio under a poster.
abstract interface class DVVideoSurface {
  Widget buildSurface(BuildContext context);
}

/// Which built-in controls a media box draws.
enum DVMediaControls {
  /// Play/pause and a scrubber, read from the controller's signals.
  standard,

  /// None: the application draws its own from the same signals.
  none,
}

/// Where native bindings register the players and capture devices they
/// implement.
///
/// Typed rather than routed through `DVNativeBridge`, because a player is an
/// object with a stream of events, not a call that returns a value. Nothing
/// is registered by default: a target whose bindings registered nothing plays
/// nothing, and says so on the controller's `error` signal.
abstract final class DVMediaBackends {
  static DVMediaPlayerFactory? _player;
  static DVMediaCapture? _capture;
  static DVCameraBackend Function()? _camera;
  static DVCameraCapabilities _cameraCapabilities = DVCameraCapabilities.none;
  static DVNowPlaying? _nowPlaying;
  static DVAudioFocus? _focus;
  static DVMediaCache? _cache;
  static Future<void> Function(String url, int? bytes)? _precache;
  static bool _backgroundAudioDeclared = false;

  /// What every controller a box makes is wired to. Replaceable, for tests
  /// and for a generated runtime that declares DRM adapters.
  static DVMediaEnvironment Function() environment = _defaultEnvironment;

  static DVMediaEnvironment _defaultEnvironment() => DVMediaEnvironment(
        focus: _focus,
        nowPlaying: _nowPlaying,
        cache: _cache,
        captionLoader: dvLoadCaptionText,
        backgroundAudioDeclared: _backgroundAudioDeclared,
      );

  /// Binds this target's player. [backgroundAudioDeclared] is whether the
  /// build declared what the platform needs to keep playing in the
  /// background -- `UIBackgroundModes: audio`, a media-playback foreground
  /// service -- as the binding found it in the running application.
  static void registerPlayer(DVMediaPlayerFactory factory,
      {bool? backgroundAudioDeclared}) {
    _player = factory;
    if (backgroundAudioDeclared != null) {
      _backgroundAudioDeclared = backgroundAudioDeclared;
    }
  }

  /// Binds the platform's audio focus.
  static void registerAudioFocus(DVAudioFocusBackend backend) =>
      _focus = DVAudioFocus(backend);

  /// Binds the lock screen and its transport controls.
  static void registerNowPlaying(DVNowPlayingBackend backend) =>
      _nowPlaying = dvNowPlaying = DVNowPlaying(backend);

  /// The disk cache progressive URLs are read through. A binding on a
  /// target with a filesystem sets it at start-up.
  static void useCache(DVMediaCache? cache) => _cache = cache;

  static DVMediaCache? get cache => _cache;

  /// How `DV.Platform.media.precache` fetches where there is no disk cache:
  /// a browser asking its own HTTP cache to fetch.
  static void registerPrecache(
          Future<void> Function(String url, int? bytes) precache) =>
      _precache = precache;

  /// Binds this target's camera. [capabilities] is what the device reports
  /// without opening it; the factory opens nothing until a box asks.
  ///
  /// [directory] is where photos and clips go, made private like
  /// recordings'.
  static void registerCamera(DVCameraBackend Function() factory,
      {required DVCameraCapabilities capabilities, String? directory}) {
    _camera = factory;
    _cameraCapabilities = capabilities;
    if (directory != null) _captureDirectory = directory;
  }

  static String? _captureDirectory;

  /// Where a camera writes, private to this account.
  static DVCaptureFiles get captureFiles {
    final String? directory = _captureDirectory;
    return directory == null
        ? const _DVNoCaptureFiles()
        : DVPrivateCaptureFiles(directory);
  }

  /// The runtime permission flow, as a camera asks it.
  static DVCapturePermissions get capturePermissions =>
      const _DVPlatformCapturePermissions();

  static DVCameraCapabilities get cameraCapabilities => _cameraCapabilities;

  /// A camera, or null where none is bound.
  static DVCameraBackend? createCamera() => _camera?.call();

  /// Fetches [source] ahead of playback. Returns false where this target
  /// can neither cache nor ask anything else to.
  static Future<bool> precache(DVMediaSource source, {int? bytes}) async {
    if (source.kind != DVMediaSourceKind.url || source.isAdaptive) return false;
    final DVMediaCache? cache = _cache;
    if (cache != null && source.cache) {
      await cache.precache(source.reference, bytes: bytes);
      return true;
    }
    final Future<void> Function(String, int?)? fetch = _precache;
    if (fetch == null) return false;
    await fetch(source.reference, bytes);
    return true;
  }

  static void unregisterPlayer() => _player = null;

  static bool get hasPlayer => _player != null;

  /// A player for [source], or null when this target has none bound.
  static DVMediaPlayerBackend? createPlayer(
          DVMediaSource source, DVMediaKind kind) =>
      _player?.call(source, kind);

  /// Binds capture. [directory] is where recordings go; it is made private
  /// to this account and must not be shared with anything else.
  static void registerCapture({
    required DVCaptureCapabilities capabilities,
    required DVCaptureBackend Function() backend,
    required String directory,
    DVCapturePermissions permissions = const _DVPlatformCapturePermissions(),
  }) {
    _captureDirectory = directory;
    _capture = DVMediaCapture(
      capabilities: capabilities,
      backend: backend,
      permissions: permissions,
      files: DVPrivateCaptureFiles(directory),
      lifecycle: environment().lifecycle,
    );
  }

  /// The capture runtime `DV.Platform.media` records through.
  static DVMediaCapture get capture => _capture ??= DVMediaCapture(
        capabilities: DVCaptureCapabilities.none,
        backend: () => throw StateError('No capture backend is registered.'),
        permissions: const _DVPlatformCapturePermissions(),
        files: const _DVNoCaptureFiles(),
        lifecycle: environment().lifecycle,
      );

  /// Unbinds everything. For tests.
  @visibleForTesting
  static void reset() {
    _player = null;
    _capture = null;
    _camera = null;
    _cameraCapabilities = DVCameraCapabilities.none;
    _captureDirectory = null;
    _nowPlaying = null;
    _focus = null;
    _cache = null;
    _precache = null;
    _backgroundAudioDeclared = false;
    dvNowPlaying = DVNowPlaying();
    environment = _defaultEnvironment;
  }
}

/// Where recordings go on a target with no capture bound: nowhere. Never
/// reached, because the capability report refuses first. Not a filesystem
/// type, because this file is compiled for the web too.
final class _DVNoCaptureFiles implements DVCaptureFiles {
  const _DVNoCaptureFiles();

  Never _none() => throw StateError('No capture backend is registered.');

  @override
  Future<String> reserve(String extension) async => _none();

  @override
  Future<int> seal(String path) async => _none();

  @override
  Future<void> discard(String path) async {}
}

/// `DV.Platform.permissions`, as capture asks it.
final class _DVPlatformCapturePermissions implements DVCapturePermissions {
  const _DVPlatformCapturePermissions();

  @override
  Future<bool> request(String permission) =>
      DV.Platform.permissions.request(permission);
}

/// A player for a target with nothing to play through. Fails on open, with
/// the reason, so the controller's state says what happened.
final class _DVUnavailablePlayer implements DVMediaPlayerBackend {
  _DVUnavailablePlayer(this.reason);

  final String reason;
  final StreamController<DVMediaBackendEvent> _events =
      StreamController<DVMediaBackendEvent>.broadcast();

  @override
  DVMediaBackendCapabilities get capabilities =>
      const DVMediaBackendCapabilities(adaptiveStreaming: false, video: false);

  @override
  Stream<DVMediaBackendEvent> get events => _events.stream;

  @override
  Future<void> open(DVMediaSource source, {Object? license}) async =>
      _events.add(DVMediaFailed(reason));

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position, int generation) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() => _events.close();
}

/// Reads a caption file: a bundled asset, a URL or a file.
Future<String> dvLoadCaptionText(DVMediaSource source) async {
  switch (source.kind) {
    case DVMediaSourceKind.asset:
      return rootBundle.loadString(source.reference);
    case DVMediaSourceKind.url:
      final http.Response response =
          await http.get(Uri.parse(source.reference));
      if (response.statusCode >= 400) {
        throw StateError('the captions at ${source.reference} answered '
            '${response.statusCode}');
      }
      return response.body;
    case DVMediaSourceKind.file:
      return dvReadCaptionFile(source.reference);
  }
}

/// A backend that draws a camera's live picture.
abstract interface class DVCameraSurface {
  Widget buildPreview(BuildContext context);
}

/// Remote-control keys, mapped to the controller by default.
///
/// Media keys work everywhere. Select and the arrow keys only on a
/// television, and only while the player has keyboard focus: on a television
/// the arrows are how focus moves between tiles, and a player that took them
/// from every screen would trap the person on it.
abstract final class DVMediaTransportKeys {
  /// How far a seek key moves.
  static const Duration seekStep = Duration(seconds: 10);

  static DVTransportAction? actionFor(
    LogicalKeyboardKey key, {
    required bool television,
  }) {
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      return DVTransportAction.togglePlay;
    }
    if (key == LogicalKeyboardKey.mediaPlay) return DVTransportAction.play;
    if (key == LogicalKeyboardKey.mediaPause) return DVTransportAction.pause;
    if (key == LogicalKeyboardKey.mediaStop) return DVTransportAction.stop;
    if (key == LogicalKeyboardKey.mediaFastForward) {
      return DVTransportAction.seekForward;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      return DVTransportAction.seekBackward;
    }
    if (!television) return null;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      return DVTransportAction.togglePlay;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return DVTransportAction.seekForward;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return DVTransportAction.seekBackward;
    }
    return null;
  }

  /// Applies [action] to [controller].
  static Future<void> apply(
      DVTransportAction action, DVMediaController controller) async {
    final DVPlaybackState state = controller.state.value;
    final bool active = state == DVPlaybackState.playing ||
        state == DVPlaybackState.buffering ||
        state == DVPlaybackState.stalled;
    switch (action) {
      case DVTransportAction.togglePlay:
        await (active ? controller.pause() : controller.play());
      case DVTransportAction.play:
        await controller.play();
      case DVTransportAction.pause:
        await controller.pause();
      case DVTransportAction.stop:
        await controller.pause();
        unawaited(controller.seek(.zero));
      case DVTransportAction.seekForward:
        unawaited(controller.seek(controller.position.value + seekStep));
      case DVTransportAction.seekBackward:
        final Duration back = controller.position.value - seekStep;
        unawaited(
            controller.seek(back < Duration.zero ? Duration.zero : back));
      case DVTransportAction.seekTo:
        break;
    }
  }
}

/// Reading a player's signals in a build.
extension DVMediaSignalWatch<T> on DVMediaSignal<T> {
  /// The current value, rebuilding the reading element when it changes.
  T watch(BuildContext context) {
    final Element element = context as Element;
    final Map<DVMediaSignal<Object?>, StreamSubscription<Object?>> subs =
        _watchers[element] ??=
            <DVMediaSignal<Object?>, StreamSubscription<Object?>>{};
    subs.putIfAbsent(this, () {
      late final StreamSubscription<T> subscription;
      subscription = changes.listen((T _) {
        if (element.mounted) {
          element.markNeedsBuild();
          return;
        }
        // Nothing tells a signal an element went away; the first change
        // after it did is when the subscription goes.
        subs.remove(this);
        unawaited(subscription.cancel());
      });
      return subscription;
    });
    return value;
  }
}

final Expando<Map<DVMediaSignal<Object?>, StreamSubscription<Object?>>>
    _watchers = Expando<
        Map<DVMediaSignal<Object?>, StreamSubscription<Object?>>>(
  'dartvel media signal watchers',
);

/// The widget a media box renders. Built by `DVBox.video`/`DVBox.audio`;
/// application code uses the box.
@internal
class DVMediaView extends StatefulWidget {
  DVMediaView({
    super.key,
    required this.source,
    required this.kind,
    this.poster,
    this.controls = DVMediaControls.standard,
    this.background = DVBackgroundPlayback.none,
    this.autoplay = false,
    this.aspectRatio,
    this.session,
    this.captions,
    DVMediaController? controller,
  })  : ownsController = controller == null,
        controller = controller ??
            DVMediaController(
              source,
              background: background,
              session: session,
              captions: captions,
              environment: DVMediaBackends.environment(),
            );

  DVMediaView._copy(DVMediaView from, {required this.aspectRatio})
      : source = from.source,
        kind = from.kind,
        poster = from.poster,
        controls = from.controls,
        background = from.background,
        autoplay = from.autoplay,
        session = from.session,
        captions = from.captions,
        controller = from.controller,
        ownsController = from.ownsController,
        super(key: from.key);

  final DVMediaSource source;
  final DVMediaKind kind;
  final DVImage? poster;
  final DVMediaControls controls;
  final DVBackgroundPlayback background;
  final bool autoplay;
  final double? aspectRatio;
  final DVMediaSession? session;
  final DVCaptions? captions;
  final DVMediaController controller;

  /// Whether the box made [controller], and so disposes it with the page. A
  /// controller the application passed in outlives the box.
  final bool ownsController;

  DVMediaView withAspectRatio(double ratio) =>
      DVMediaView._copy(this, aspectRatio: ratio);

  @override
  State<DVMediaView> createState() => _DVMediaViewState();
}

class _DVMediaViewState extends State<DVMediaView> {
  static final List<_DVMediaViewState> _mounted = <_DVMediaViewState>[];

  late DVMediaController _current;
  bool _owns = false;
  bool _muted = false;
  DVMediaPlayerBackend? _backend;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    if (_mounted.isEmpty) HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _mounted.add(this);
    _adopt(widget);
  }

  void _adopt(DVMediaView view) {
    _current = view.controller;
    _owns = view.ownsController;
    _backend = null;
    _listen();
    if (_current.isAttached) return;

    final DVMediaPlayerBackend backend;
    if (DV.Platform.surface == DVRenderSurface.terminal) {
      backend = _DVUnavailablePlayer(
          'media playback is unsupported on the terminal; showing the poster');
    } else {
      backend = DVMediaBackends.createPlayer(view.source, view.kind) ??
          _DVUnavailablePlayer(
              'no media player is bound for this target; register one with '
              'DVMediaBackends.registerPlayer');
    }
    _backend = backend;
    final DVMediaController controller = _current;
    unawaited(() async {
      try {
        await controller.attach(backend);
        if (view.autoplay && mounted && identical(controller, _current)) {
          await controller.play();
        }
      } catch (_) {
        // Refusals (DRM, streaming, focus) are already on the controller's
        // state and error signals, which is where the box reads them.
      }
    }());
  }

  void _listen() {
    for (final StreamSubscription<Object?> s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions
      ..clear()
      ..add(_current.state.listen((_) => _changed()))
      ..add(_current.position.listen((_) => _changed()))
      ..add(_current.duration.listen((_) => _changed()))
      ..add(_current.caption.listen((_) => _changed()))
      ..add(_current.captionTrack.listen((_) => _changed()))
      ..add(_current.pictureInPicture.listen((_) => _changed()))
      ..add(_current.videoSize.listen((_) => _changed()));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(DVMediaView old) {
    super.didUpdateWidget(old);
    final DVMediaView next = widget;
    if (identical(next.controller, _current) ||
        identical(next.controller, old.controller)) {
      return;
    }
    final bool sameContent =
        next.source == _current.source && next.kind == old.kind;
    if (sameContent && next.ownsController && !next.controller.isAttached) {
      // A parent rebuilt the box. Its new handle joins the running player.
      next.controller.follow(_current);
      return;
    }
    if (_owns) unawaited(_current.dispose());
    _adopt(next);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    if (_mounted.isEmpty) {
      HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    }
    for (final StreamSubscription<Object?> s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    if (_owns) unawaited(_current.dispose());
    super.dispose();
  }

  /// Media keys go to the player holding audio focus, or else to the most
  /// recently mounted one that can play.
  static bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final DVTransportAction? action =
        DVMediaTransportKeys.actionFor(event.logicalKey, television: false);
    if (action == null) return false;
    _DVMediaViewState? target;
    for (final _DVMediaViewState s in _mounted) {
      if (identical(s._current.environment.focus.holder, s._current)) {
        target = s;
      }
    }
    if (target == null) {
      for (final _DVMediaViewState s in _mounted.reversed) {
        if (_playable(s._current.state.value)) {
          target = s;
          break;
        }
      }
    }
    if (target == null) return false;
    unawaited(DVMediaTransportKeys.apply(action, target._current)
        .catchError((Object _) {}));
    return true;
  }

  static bool _playable(DVPlaybackState state) =>
      state != DVPlaybackState.idle &&
      state != DVPlaybackState.failed &&
      state != DVPlaybackState.disposed;

  KeyEventResult _onFocusedKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // The keys a person expects of any player with keyboard focus, on every
    // target: k and space toggle, j and l skip, m mutes, c cycles captions.
    // Only while the player itself is focused, so typing on the page is
    // never taken.
    if (node.hasPrimaryFocus) {
      final DVMediaKeyAction? key = DVMediaKeys.actionFor(event.logicalKey);
      if (key != null) {
        unawaited(DVMediaKeys.apply(key, _current, muted: _muted,
            onMuted: (bool muted) => setState(() => _muted = muted))
            .catchError((Object _) {}));
        return KeyEventResult.handled;
      }
    }
    if (!DV.Platform.isTV) return KeyEventResult.ignored;
    final DVTransportAction? action =
        DVMediaTransportKeys.actionFor(event.logicalKey, television: true);
    // Media keys arrive through the global handler already.
    if (action == null ||
        DVMediaTransportKeys.actionFor(event.logicalKey, television: false) !=
            null) {
      return KeyEventResult.ignored;
    }
    unawaited(
        DVMediaTransportKeys.apply(action, _current).catchError((Object _) {}));
    return KeyEventResult.handled;
  }

  Widget _controls(DVPlaybackState state) => DVMediaStandardControls(
        controller: _current,
        state: state,
        muted: _muted,
        onMuted: (bool muted) {
          setState(() => _muted = muted);
          unawaited(_current.setVolume(muted ? 0 : 1).catchError((Object _) {}));
        },
      );

  @override
  Widget build(BuildContext context) {
    final DVPlaybackState state = _current.state.value;
    final bool video = widget.kind == DVMediaKind.video;
    final DVMediaPlayerBackend? backend = _backend;
    final bool failed = state == DVPlaybackState.failed ||
        state == DVPlaybackState.disposed;
    final bool started = state == DVPlaybackState.playing ||
        _current.position.value > Duration.zero;

    final List<Widget> layers = <Widget>[
      if (video && !failed && backend is DVVideoSurface)
        Positioned.fill(
            child: (backend as DVVideoSurface).buildSurface(context)),
      if (widget.poster != null && (failed || !started || !video))
        Positioned.fill(child: DVImageRender(widget.poster)),
      if (_current.caption.value != null)
        Positioned(
          left: 16,
          right: 16,
          bottom: widget.controls == DVMediaControls.standard ? 56 : 16,
          child: DVCaptionLine(_current.caption.value!),
        ),
      if (widget.controls == DVMediaControls.standard && _playable(state))
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _controls(state),
        ),
    ];

    final String? title = widget.session?.title;
    final Widget content = Focus(
      onKeyEvent: _onFocusedKey,
      child: Semantics(
        // What the server-rendered document turns into a real <video> or
        // <audio>: the page capture reads it off the semantics tree.
        identifier: dvMediaSemanticsIdentifier(
          kind: widget.kind,
          source: widget.source,
          poster: widget.poster,
          captions: widget.captions,
        ),
        label: title == null
            ? (video ? 'Video player' : 'Audio player')
            : '${video ? 'Video' : 'Audio'}: $title',
        value: _stateLabel(state),
        child: video
            ? Stack(children: layers)
            : Stack(children: <Widget>[
                if (widget.poster != null)
                  Positioned.fill(child: DVImageRender(widget.poster)),
                if (widget.controls == DVMediaControls.standard &&
                    _playable(state))
                  _controls(state)
                else
                  const SizedBox(height: 48),
                if (_current.caption.value != null)
                  DVCaptionLine(_current.caption.value!),
              ]),
      ),
    );

    final double? ratio = widget.aspectRatio;
    if (ratio != null) {
      return AspectRatio(aspectRatio: ratio, child: content);
    }
    if (!video) return content;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.hasBoundedHeight && constraints.hasBoundedWidth) {
          return SizedBox.expand(child: content);
        }
        return AspectRatio(aspectRatio: 16 / 9, child: content);
      },
    );
  }
}

String _stateLabel(DVPlaybackState state) => switch (state) {
      DVPlaybackState.idle || DVPlaybackState.loading => 'Loading',
      DVPlaybackState.buffering => 'Buffering',
      DVPlaybackState.paused => 'Paused',
      DVPlaybackState.playing => 'Playing',
      DVPlaybackState.stalled => 'Stalled',
      DVPlaybackState.completed => 'Finished',
      DVPlaybackState.failed => 'Could not play',
      DVPlaybackState.disposed => 'Closed',
    };

/// `1:05` or `1:02:05`.
String dvMediaClock(Duration time) {
  final int hours = time.inHours;
  final String minutes = (time.inMinutes % 60).toString();
  final String seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// What a key does to a focused player.
enum DVMediaKeyAction {
  togglePlay,
  seekForward,
  seekBackward,
  toggleMute,
  cycleCaptions,
}

/// The keyboard of a focused player, on every target.
abstract final class DVMediaKeys {
  static const Duration step = Duration(seconds: 5);

  static DVMediaKeyAction? actionFor(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      return DVMediaKeyAction.togglePlay;
    }
    if (key == LogicalKeyboardKey.keyL) return DVMediaKeyAction.seekForward;
    if (key == LogicalKeyboardKey.keyJ) return DVMediaKeyAction.seekBackward;
    if (key == LogicalKeyboardKey.keyM) return DVMediaKeyAction.toggleMute;
    if (key == LogicalKeyboardKey.keyC) return DVMediaKeyAction.cycleCaptions;
    return null;
  }

  static Future<void> apply(
    DVMediaKeyAction action,
    DVMediaController controller, {
    required bool muted,
    required void Function(bool muted) onMuted,
  }) async {
    switch (action) {
      case DVMediaKeyAction.togglePlay:
        await DVMediaTransportKeys.apply(
            DVTransportAction.togglePlay, controller);
      case DVMediaKeyAction.seekForward:
        unawaited(controller.seek(controller.position.value + step));
      case DVMediaKeyAction.seekBackward:
        final Duration back = controller.position.value - step;
        unawaited(controller.seek(back < Duration.zero ? Duration.zero : back));
      case DVMediaKeyAction.toggleMute:
        onMuted(!muted);
        await controller.setVolume(muted ? 1 : 0);
      case DVMediaKeyAction.cycleCaptions:
        await controller.setCaptionTrack(nextCaptionTrack(controller));
    }
  }

  /// Off, then each track in turn, then off again.
  static String? nextCaptionTrack(DVMediaController controller) {
    final List<DVCaptionTrack> tracks =
        controller.captions?.tracks ?? const <DVCaptionTrack>[];
    if (tracks.isEmpty) return null;
    final String? now = controller.captionTrack.value;
    final int index =
        tracks.indexWhere((DVCaptionTrack t) => t.language == now);
    if (now == null) return tracks.first.language;
    return index + 1 < tracks.length ? tracks[index + 1].language : null;
  }
}

/// One caption cue over the picture: real text, so a screen reader reads it
/// as it changes, Ctrl+F finds it and it follows the theme's type.
class DVCaptionLine extends StatelessWidget {
  const DVCaptionLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        label: text,
        child: ExcludeSemantics(
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const .symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  text,
                  textAlign: .center,
                  style: const TextStyle(
                      color: Color(0xFFFFFFFF), fontSize: 18, height: 1.3),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The built-in controls of `DVBox.video`/`DVBox.audio`: play/pause, a
/// labelled scrubber, the time, mute, captions and picture-in-picture where
/// the target has it. Every control is a real button with a label, in Tab
/// order, and the scrubber moves with the arrow keys.
class DVMediaStandardControls extends StatelessWidget {
  const DVMediaStandardControls({
    super.key,
    required this.controller,
    required this.state,
    required this.muted,
    required this.onMuted,
  });

  final DVMediaController controller;
  final DVPlaybackState state;
  final bool muted;
  final void Function(bool muted) onMuted;

  @override
  Widget build(BuildContext context) {
    final bool active = state == DVPlaybackState.playing ||
        state == DVPlaybackState.buffering ||
        state == DVPlaybackState.stalled;
    final Duration duration = controller.duration.value;
    final Duration position = controller.position.value;
    final bool hasCaptions = controller.captions?.tracks.isNotEmpty ?? false;
    final String? track = controller.captionTrack.value;
    return Material(
      type: .transparency,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: active ? 'Pause' : 'Play',
            icon: Icon(active ? Icons.pause : Icons.play_arrow),
            onPressed: () => unawaited(
                (active ? controller.pause() : controller.play())
                    .catchError((Object _) {})),
          ),
          if (duration > Duration.zero) ...<Widget>[
            Expanded(
              child: Slider(
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                max: duration.inMilliseconds.toDouble(),
                semanticFormatterCallback: (double ms) =>
                    '${dvMediaClock(Duration(milliseconds: ms.round()))} '
                    'of ${dvMediaClock(duration)}',
                onChanged: (double ms) => unawaited(controller
                    .seek(Duration(milliseconds: ms.round()))
                    .catchError((Object _) {})),
              ),
            ),
            // The slider already says this to a screen reader.
            ExcludeSemantics(
              child: Text(
                  '${dvMediaClock(position)} / ${dvMediaClock(duration)}'),
            ),
          ] else
            const Spacer(),
          IconButton(
            tooltip: muted ? 'Unmute' : 'Mute',
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () => onMuted(!muted),
          ),
          if (hasCaptions)
            IconButton(
              tooltip: track == null ? 'Turn captions on' : 'Captions: $track',
              isSelected: track != null,
              icon: Icon(track == null
                  ? Icons.closed_caption_off
                  : Icons.closed_caption),
              onPressed: () => unawaited(controller
                  .setCaptionTrack(DVMediaKeys.nextCaptionTrack(controller))
                  .catchError((Object _) {})),
            ),
          if (controller.canPictureInPicture)
            IconButton(
              tooltip: controller.pictureInPicture.value
                  ? 'Exit picture-in-picture'
                  : 'Picture-in-picture',
              icon: const Icon(Icons.picture_in_picture_alt),
              onPressed: () => unawaited((controller.pictureInPicture.value
                      ? controller.exitPictureInPicture()
                      : controller.enterPictureInPicture())
                  .catchError((Object _) {})),
            ),
        ],
      ),
    );
  }
}

/// The video behind a box: `DVBox(...).modifier(DVModifier().backgroundVideo(
/// DVAsset.marketingVideo))`.
///
/// Muted and without controls, because a background is not something anybody
/// scrubs; a video somebody watches is `DVBox.video`. It plays only where a
/// player binding is registered and shows nothing where none is, which is
/// what a background should do on a target that cannot decode it.
class DVBackgroundVideo extends StatefulWidget {
  const DVBackgroundVideo({super.key, required this.source});

  /// What plays. A bundled file resolves through `DVAsset`.
  final DVMediaSource source;

  @override
  State<DVBackgroundVideo> createState() => _DVBackgroundVideoState();
}

class _DVBackgroundVideoState extends State<DVBackgroundVideo> {
  late final DVMediaController _controller = DVMediaController(
    widget.source,
    background: DVBackgroundPlayback.none,
    environment: DVMediaBackends.environment(),
  );

  @override
  void initState() {
    super.initState();
    // After the box is mounted: a controller has no backend until the view
    // that owns it attaches one, and a background that made a sound for one
    // frame would be worse than one that never played.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _controller.setVolume(0);
      } on Object {
        // No player on this target. Nothing plays, and nothing is heard.
      }
    });
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: DVMediaView(
          source: widget.source,
          kind: DVMediaKind.video,
          controls: DVMediaControls.none,
          background: DVBackgroundPlayback.none,
          autoplay: true,
          controller: _controller,
        ),
      );
}
