/// The widget half of `DVBox.video` and `DVBox.audio`, the registry native
/// bindings put their players in, and remote-control transport keys.
///
/// The player itself -- its state machine, lifecycle and audio-focus coupling,
/// DRM and streaming refusals -- is `DVMediaController` in dartvel_core. This
/// file decides who owns one: the box's element does, so a page that goes
/// away takes its player with it.
library;

import 'dart:async';
import 'dart:io' show Directory;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dartvel_flutter.dart' show DV, DVRenderSurface;
import 'image_view.dart';

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

  /// What every controller a box makes is wired to. Replaceable, for tests
  /// and for a generated runtime that declares DRM adapters or background
  /// audio.
  static DVMediaEnvironment Function() environment = DVMediaEnvironment.new;

  static void registerPlayer(DVMediaPlayerFactory factory) => _player = factory;

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
    _capture = DVMediaCapture(
      capabilities: capabilities,
      backend: backend,
      permissions: permissions,
      files: DVPrivateCaptureFiles(directory),
      lifecycle: environment().lifecycle,
    );
  }

  /// The capture runtime `DV.Platform.Media` records through.
  static DVMediaCapture get capture => _capture ??= DVMediaCapture(
        capabilities: DVCaptureCapabilities.none,
        backend: () => throw StateError('No capture backend is registered.'),
        permissions: const _DVPlatformCapturePermissions(),
        files: DVPrivateCaptureFiles(Directory.systemTemp.path),
        lifecycle: environment().lifecycle,
      );

  /// Unbinds everything. For tests.
  @visibleForTesting
  static void reset() {
    _player = null;
    _capture = null;
    environment = DVMediaEnvironment.new;
  }
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

/// What a remote-control or keyboard key does to a player.
enum DVTransportAction { togglePlay, play, pause, stop, seekForward, seekBackward }

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
        unawaited(controller.seek(Duration.zero));
      case DVTransportAction.seekForward:
        unawaited(controller.seek(controller.position.value + seekStep));
      case DVTransportAction.seekBackward:
        final Duration back = controller.position.value - seekStep;
        unawaited(
            controller.seek(back < Duration.zero ? Duration.zero : back));
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
    DVMediaController? controller,
  })  : ownsController = controller == null,
        controller = controller ??
            DVMediaController(
              source,
              background: background,
              environment: DVMediaBackends.environment(),
            );

  DVMediaView._copy(DVMediaView from, {required this.aspectRatio})
      : source = from.source,
        kind = from.kind,
        poster = from.poster,
        controls = from.controls,
        background = from.background,
        autoplay = from.autoplay,
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
      ..add(_current.duration.listen((_) => _changed()));
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
    if (event is! KeyDownEvent || !DV.Platform.isTV) {
      return KeyEventResult.ignored;
    }
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
        Positioned.fill(child: DVImageView(widget.poster)),
      if (widget.controls == DVMediaControls.standard && _playable(state))
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _DVStandardControls(controller: _current, state: state),
        ),
    ];

    final Widget content = Focus(
      onKeyEvent: _onFocusedKey,
      child: Semantics(
        label: video ? 'Video player' : 'Audio player',
        value: state.name,
        child: video
            ? Stack(children: layers)
            : Stack(children: <Widget>[
                if (widget.poster != null)
                  Positioned.fill(child: DVImageView(widget.poster)),
                if (widget.controls == DVMediaControls.standard &&
                    _playable(state))
                  _DVStandardControls(controller: _current, state: state)
                else
                  const SizedBox(height: 48),
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

class _DVStandardControls extends StatelessWidget {
  const _DVStandardControls({required this.controller, required this.state});

  final DVMediaController controller;
  final DVPlaybackState state;

  @override
  Widget build(BuildContext context) {
    final bool active = state == DVPlaybackState.playing ||
        state == DVPlaybackState.buffering ||
        state == DVPlaybackState.stalled;
    final Duration duration = controller.duration.value;
    final Duration position = controller.position.value;
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: active ? 'Pause' : 'Play',
            icon: Icon(active ? Icons.pause : Icons.play_arrow),
            onPressed: () => unawaited(
                (active ? controller.pause() : controller.play())
                    .catchError((Object _) {})),
          ),
          if (duration > Duration.zero)
            Expanded(
              child: Slider(
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                max: duration.inMilliseconds.toDouble(),
                onChanged: (double ms) => unawaited(controller
                    .seek(Duration(milliseconds: ms.round()))
                    .catchError((Object _) {})),
              ),
            ),
        ],
      ),
    );
  }
}
