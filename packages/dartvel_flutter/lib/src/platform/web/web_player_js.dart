/// `DVBox.video` and `DVBox.audio` in a browser: the page's own `<video>` and
/// `<audio>` elements, `navigator.mediaSession` for the lock screen and media
/// keys, picture-in-picture, and precache through the browser's HTTP cache.
///
/// The element is created by the backend, before any widget shows it, and is
/// handed to Flutter as a platform view. A player can therefore load and play
/// before its box has laid out, and audio plays from an element that is never
/// in the page at all. What the element's events mean is decided in
/// `media/web_media_mapping.dart`, where a test can reach it.
library dartvel_flutter.platform.web.player;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../media/media_box.dart';
import '../../media/web_media_mapping.dart';
import 'web_interop.dart';

/// Binds the browser player, the media session and precache.
abstract final class DVWebPlayer {
  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    DVMediaBackends.registerPlayer(
      (DVMediaSource source, DVMediaKind kind) => DVWebMediaElementPlayer(kind),
      // A tab keeps playing with the page hidden; nothing to declare.
      backgroundAudioDeclared: true,
    );
    if (DVWebMediaSession.available) {
      DVMediaBackends.registerNowPlaying(DVWebMediaSession());
    }
    DVMediaBackends.registerPrecache(precache);
  }

  /// Asks the browser to fetch [url] so its HTTP cache holds it. The browser
  /// decides how long that lasts -- its own eviction, the server's
  /// Cache-Control -- which is the honest limit of caching on the web.
  static Future<void> precache(String url, int? bytes) async {
    final web.Headers headers = web.Headers();
    if (bytes != null) headers.set('Range', 'bytes=0-${bytes - 1}');
    final web.Response response = await web.window
        .fetch(url.toJS, web.RequestInit(headers: headers))
        .toDart;
    if (!response.ok) {
      throw StateError('precache of $url answered ${response.status}');
    }
    // Read to the end: a response nobody reads may not be stored.
    await response.arrayBuffer().toDart;
  }
}

int _nextView = 0;

/// One `<video>` or `<audio>` element.
final class DVWebMediaElementPlayer
    implements DVMediaPictureInPictureBackend, DVVideoSurface {
  DVWebMediaElementPlayer(this.kind)
      : _element = (kind == DVMediaKind.video
            ? web.document.createElement('video')
            : web.document.createElement('audio')) as web.HTMLMediaElement,
        _viewType = 'dartvel-media-${_nextView++}' {
    _element
      ..preload = 'auto'
      ..controls = false;
    // Inline on iOS, where a video that is not plays fullscreen.
    _element.setAttribute('playsinline', 'true');
    _element.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..backgroundColor = 'black';
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _element);
    for (final String type in dvWebMediaEvents) {
      final JSFunction listener = ((web.Event _) => _on(type)).toJS;
      _listeners[type] = listener;
      _element.addEventListener(type, listener);
    }
  }

  final DVMediaKind kind;
  final web.HTMLMediaElement _element;
  final String _viewType;
  final Map<String, JSFunction> _listeners = <String, JSFunction>{};
  final DVWebMediaEventMapper _mapper = DVWebMediaEventMapper();

  // Not `is HTMLVideoElement`: on a JS interop extension type that checks
  // the representation, which every element shares, and is always true.
  bool get _isVideo => kind == DVMediaKind.video;
  final StreamController<DVMediaBackendEvent> _events =
      StreamController<DVMediaBackendEvent>.broadcast();

  static bool get _hls =>
      (web.document.createElement('video') as web.HTMLMediaElement)
          .canPlayType('application/vnd.apple.mpegurl')
          .isNotEmpty;

  static bool get _pipEnabled =>
      dvJsHas(web.document as JSObject, 'pictureInPictureEnabled') &&
      web.document.pictureInPictureEnabled;

  @override
  DVMediaBackendCapabilities get capabilities => DVMediaBackendCapabilities(
        adaptiveStreaming: _hls,
        backgroundAudio: true,
        pictureInPicture: kind == DVMediaKind.video && _pipEnabled,
        video: kind == DVMediaKind.video,
      );

  @override
  Stream<DVMediaBackendEvent> get events => _events.stream;

  void _on(String type) {
    final web.TimeRanges ranges = _element.buffered;
    final web.HTMLMediaElement element = _element;
    final DVWebMediaSnapshot snapshot = DVWebMediaSnapshot(
      duration: _element.duration,
      currentTime: _element.currentTime,
      videoWidth: _isVideo ? (element as web.HTMLVideoElement).videoWidth : 0,
      videoHeight:
          _isVideo ? (element as web.HTMLVideoElement).videoHeight : 0,
      buffered: <(double, double)>[
        for (int i = 0; i < ranges.length; i++) (ranges.start(i), ranges.end(i)),
      ],
      error: _element.error == null
          ? null
          : '${_element.error!.code}: ${_element.error!.message}',
    );
    for (final DVMediaBackendEvent event in _mapper.map(type, snapshot)) {
      if (!_events.isClosed) _events.add(event);
    }
  }

  @override
  Future<void> open(DVMediaSource source, {Object? license}) async {
    final String? address = dvMediaAddress(source);
    if (address == null) {
      _events.add(const DVMediaFailed(
          'a browser cannot open a file path; use DVMediaSource.url or '
          'DVMediaSource.asset'));
      return;
    }
    _element.src = address;
    _element.load();
  }

  @override
  Future<void> play() async {
    try {
      await _element.play().toDart;
    } on Object catch (error) {
      // Autoplay with sound is refused until the person has interacted with
      // the page. That is a pause, not a failure: a tap starts it.
      _events.add(const DVMediaPaused());
      if (!dvJsReason(error).contains('NotAllowedError')) rethrow;
    }
  }

  @override
  Future<void> pause() async => _element.pause();

  @override
  Future<void> seek(Duration position, int generation) async {
    _mapper.seekIssued(generation);
    _element.currentTime = position.inMicroseconds / 1000000;
  }

  @override
  Future<void> setVolume(double volume) async {
    _element.volume = volume;
    _element.muted = volume == 0;
  }

  @override
  Future<bool> enterPictureInPicture() async {
    final JSFunction? request =
        dvJsMethod(_element as JSObject, 'requestPictureInPicture');
    if (request == null) return false;
    try {
      await dvJsCall(_element as JSObject, 'requestPictureInPicture');
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> exitPictureInPicture() async {
    final JSObject document = web.document as JSObject;
    if (!dvJsHas(document, 'pictureInPictureElement')) return;
    await dvJsCall(document, 'exitPictureInPicture');
  }

  @override
  Widget buildSurface(BuildContext context) =>
      HtmlElementView(viewType: _viewType);

  @override
  Future<void> dispose() async {
    _listeners.forEach(_element.removeEventListener);
    _listeners.clear();
    _element.pause();
    _element.removeAttribute('src');
    _element.load();
    await _events.close();
  }
}

/// `navigator.mediaSession`: the lock screen, the browser's media hub and
/// hardware media keys.
final class DVWebMediaSession implements DVNowPlayingBackend {
  DVWebMediaSession() {
    for (final String action in dvMediaSessionActions) {
      try {
        _session.setActionHandler(
          action,
          ((JSObject details) {
            final num? seekTime = dvJsNum(details, 'seekTime');
            final DVMediaCommand? command = dvMediaSessionCommand(action,
                seekTime: seekTime?.toDouble());
            if (command != null && !_commands.isClosed) {
              _commands.add(command);
            }
          }).toJS,
        );
      } on Object {
        // An action this browser does not support. The others still work.
      }
    }
  }

  static bool get available {
    final JSObject? navigator = dvNavigator;
    return navigator != null && dvJsObject(navigator, 'mediaSession') != null;
  }

  web.MediaSession get _session => web.window.navigator.mediaSession;

  final StreamController<DVMediaCommand> _commands =
      StreamController<DVMediaCommand>.broadcast();

  @override
  Stream<DVMediaCommand> get commands => _commands.stream;

  @override
  Future<void> publish(DVMediaSession session, DVNowPlayingState state) async {
    final String? artwork = session.artworkUrl;
    _session.metadata = web.MediaMetadata(web.MediaMetadataInit(
      title: session.title,
      artist: session.artist ?? '',
      album: session.album ?? '',
      artwork: <web.MediaImage>[
        if (artwork != null) web.MediaImage(src: artwork),
      ].toJS,
    ));
    _session.playbackState = state.playing ? 'playing' : 'paused';
    final double duration = state.duration.inMicroseconds / 1000000;
    if (duration > 0) {
      final double position =
          (state.position.inMicroseconds / 1000000).clamp(0, duration);
      try {
        _session.setPositionState(web.MediaPositionState(
          duration: duration,
          position: position,
          playbackRate: 1,
        ));
      } on Object {
        // A browser with no position state still shows the metadata.
      }
    }
  }

  @override
  Future<void> clear() async {
    _session.metadata = null;
    _session.playbackState = 'none';
  }
}

/// Exposed for the registration in `web_bindings_js.dart`.
void dvRegisterWebPlayer() => DVWebPlayer.register();
