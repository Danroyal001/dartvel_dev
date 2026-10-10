/// The parts of the browser player and camera that need no browser.
///
/// The JS-facing classes in `platform/web/web_player_js.dart` and
/// `web_camera_js.dart` read a media element's state and hand it here; what
/// it means for the player -- which event, which seek generation, what a
/// lock-screen action asks for -- is decided in plain Dart, where a test can
/// reach it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';

import 'media_box.dart' show DVMediaKind;

/// Where a browser can load [source] from, or null when it cannot: a file on
/// a device has no address a page could fetch.
///
/// An asset is where `flutter build web` serves it, `assets/<key>`, relative
/// to the page's base.
String? dvMediaAddress(DVMediaSource source) => switch (source.kind) {
      DVMediaSourceKind.url => source.reference,
      DVMediaSourceKind.asset => 'assets/${source.reference}',
      DVMediaSourceKind.file => null,
    };

String? _imageAddress(DVImage? image) {
  if (image == null) return null;
  return switch (image.source) {
    DVImageSource.network => image.reference,
    DVImageSource.asset => 'assets/${image.reference}',
    _ => null,
  };
}

/// The semantics identifier a player box carries, which the page capture
/// turns into a real `<video>`/`<audio>` in the server-rendered document.
///
/// `dartvel:<kind>|<json>`: the role, then what a browser needs to play it
/// with no JavaScript -- the source, the poster and the caption files.
/// Adaptive streams are offered as their progressive rendition when they
/// have one, because a `<video>` given an HLS manifest plays only in Safari.
String dvMediaSemanticsIdentifier({
  required DVMediaKind kind,
  required DVMediaSource source,
  DVImage? poster,
  DVCaptions? captions,
}) {
  final DVMediaSource playable =
      source.isAdaptive ? (source.progressiveRendition ?? source) : source;
  final String? src = dvMediaAddress(playable);
  final String? posterSrc = kind == DVMediaKind.video ? _imageAddress(poster) : null;
  final List<Map<String, Object?>> tracks = <Map<String, Object?>>[
    for (final DVCaptionTrack track
        in captions?.tracks ?? const <DVCaptionTrack>[])
      if (track.source case final DVMediaSource trackSource
          when dvMediaAddress(trackSource) != null)
        <String, Object?>{
          'srclang': track.language,
          'label': track.label,
          'src': dvMediaAddress(trackSource),
        },
  ];
  final Map<String, Object?> media = <String, Object?>{
    'src': ?src,
    'poster': ?posterSrc,
    if (tracks.isNotEmpty) 'tracks': tracks,
  };
  return 'dartvel:${kind.name}|${jsonEncode(media)}';
}

/// The identifier a camera box carries: a camera, with nothing to load.
const String dvCameraSemanticsIdentifier = 'dartvel:camera|{}';

/// What a media element says about itself when an event fires.
final class DVWebMediaSnapshot {
  const DVWebMediaSnapshot({
    required this.duration,
    required this.currentTime,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.buffered = const <(double, double)>[],
    this.error,
  });

  /// Seconds. NaN before metadata, infinity for a live stream.
  final double duration;
  final double currentTime;
  final int videoWidth;
  final int videoHeight;
  final List<(double, double)> buffered;
  final String? error;
}

Duration _seconds(double seconds) => seconds.isFinite && seconds > 0
    ? Duration(microseconds: (seconds * 1000000).round())
    : Duration.zero;

/// Media element events, as player reports.
final class DVWebMediaEventMapper {
  int _issued = 0;
  int _completed = 0;

  /// A seek was handed to the element; its `seeked` confirms [generation].
  void seekIssued(int generation) => _issued = generation;

  List<DVMediaBackendEvent> map(String type, DVWebMediaSnapshot element) {
    switch (type) {
      case 'loadedmetadata':
        return <DVMediaBackendEvent>[
          DVMediaReady(duration: _seconds(element.duration)),
          if (element.videoWidth > 0 && element.videoHeight > 0)
            DVMediaVideoSize(element.videoWidth, element.videoHeight),
        ];
      case 'playing':
        return const <DVMediaBackendEvent>[DVMediaPlaying()];
      case 'pause':
        return const <DVMediaBackendEvent>[DVMediaPaused()];
      case 'waiting':
        return const <DVMediaBackendEvent>[DVMediaBuffering()];
      case 'timeupdate':
        return <DVMediaBackendEvent>[
          DVMediaPosition(_seconds(element.currentTime), seek: _completed),
        ];
      case 'seeked':
        _completed = _issued;
        return <DVMediaBackendEvent>[
          DVMediaSeekCompleted(_completed, _seconds(element.currentTime)),
        ];
      case 'progress':
        return <DVMediaBackendEvent>[
          DVMediaBuffered(<DVRange>[
            for (final (double start, double end) in element.buffered)
              DVRange(_seconds(start), _seconds(end)),
          ]),
        ];
      case 'ended':
        return const <DVMediaBackendEvent>[DVMediaCompleted()];
      case 'error':
        return <DVMediaBackendEvent>[
          DVMediaFailed('the browser could not play this source'
              '${element.error == null ? '' : ' (${element.error})'}'),
        ];
      case 'enterpictureinpicture':
        return const <DVMediaBackendEvent>[DVMediaPictureInPictureChanged(true)];
      case 'leavepictureinpicture':
        return const <DVMediaBackendEvent>[
          DVMediaPictureInPictureChanged(false),
        ];
    }
    return const <DVMediaBackendEvent>[];
  }
}

/// The element events [DVWebMediaEventMapper] reads.
const List<String> dvWebMediaEvents = <String>[
  'loadedmetadata',
  'playing',
  'pause',
  'waiting',
  'timeupdate',
  'seeked',
  'progress',
  'ended',
  'error',
  'enterpictureinpicture',
  'leavepictureinpicture',
];

/// The `navigator.mediaSession` actions a published player answers.
const List<String> dvMediaSessionActions = <String>[
  'play',
  'pause',
  'stop',
  'seekto',
  'seekforward',
  'seekbackward',
];

/// What a media session action asks of the player, or null.
DVMediaCommand? dvMediaSessionCommand(String action, {double? seekTime}) =>
    switch (action) {
      'play' => const DVMediaCommand(DVTransportAction.play),
      'pause' => const DVMediaCommand(DVTransportAction.pause),
      'stop' => const DVMediaCommand(DVTransportAction.stop),
      'seekforward' => const DVMediaCommand(DVTransportAction.seekForward),
      'seekbackward' => const DVMediaCommand(DVTransportAction.seekBackward),
      'seekto' when seekTime != null && seekTime.isFinite =>
        DVMediaCommand(DVTransportAction.seekTo,
            position: _seconds(seekTime)),
      _ => null,
    };

/// Where photos and recordings live in a browser.
///
/// The web has no file paths. A browser records into a Blob, and the
/// `DVFile.path` of a capture on the web is a key in this store,
/// `dvcapture:<n>.<ext>` -- not a path any file API can open. Read the bytes
/// with [bytesOf]; they last as long as the page.
final class DVWebCaptureStore implements DVCaptureFiles {
  DVWebCaptureStore();

  /// The page's store, which the web camera writes into.
  static final DVWebCaptureStore instance = DVWebCaptureStore();

  final Map<String, Uint8List?> _files = <String, Uint8List?>{};
  int _next = 0;

  @override
  Future<String> reserve(String extension) async {
    final String key = 'dvcapture:${_next++}.$extension';
    _files[key] = null;
    return key;
  }

  /// Puts what the device recorded under [key].
  void write(String key, Uint8List bytes) {
    if (!_files.containsKey(key)) {
      throw StateError('$key was not reserved for a recording');
    }
    _files[key] = bytes;
  }

  @override
  Future<int> seal(String key) async {
    final Uint8List? bytes = _files[key];
    if (bytes == null) throw StateError('nothing was recorded into $key');
    return bytes.length;
  }

  @override
  Future<void> discard(String key) async => _files.remove(key);

  /// The bytes of a capture, or null when there is none under [key].
  Uint8List? bytesOf(String key) => _files[key];
}
