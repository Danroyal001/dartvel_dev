/// The JSON native players, cameras and now-playing surfaces queue for Dart.
///
/// Native code never calls into Dart: a callback from an AVFoundation queue,
/// a CameraX executor or a Media3 listener thread cannot enter an isolate
/// safely, so each native object keeps a queue of JSON strings and Dart
/// drains it from a timer. This file is the one reading of that queue, shared
/// by every native backend (Apple through FFI, Android through JNI), so a
/// field one platform spells differently is a test failure here rather than a
/// player that silently never leaves "loading".
///
/// Player events, one object each, times in integer milliseconds:
///
/// | `type`          | fields                                  |
/// |-----------------|-----------------------------------------|
/// | `ready`         | `durationMs` (absent or 0 for live)     |
/// | `playing`       |                                         |
/// | `paused`        |                                         |
/// | `buffering`     |                                         |
/// | `position`      | `ms`, `seek` (last completed generation, default 0) |
/// | `buffered`      | `ranges`: `[[startMs, endMs], ...]`     |
/// | `seekCompleted` | `seek`, `ms`                            |
/// | `completed`     |                                         |
/// | `videoSize`     | `width`, `height`                       |
/// | `pip`           | `active`                                |
/// | `failed`        | `message`                               |
///
/// Camera events: `opened` (`lens`: back/front/external, `width`,
/// `height`), `closed`, `photo` (`path`), `recordingStarted`,
/// `recordingStopped` (`durationMs`), `disconnected`, `failed` (`message`).
///
/// Now-playing commands: `{"action": <DVTransportAction name>}`, with `ms`
/// for `seekTo`.
///
/// Anything unrecognised parses to null and is dropped: a newer native half
/// talking to an older Dart half must not crash the player.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

Map<String, Object?>? _object(String json) {
  try {
    final Object? decoded = jsonDecode(json);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

Duration? _ms(Object? value) => value is num
    ? Duration(milliseconds: value.round())
    : value == null
        ? null
        : throw const FormatException('not a number');

int _int(Object? value, [int fallback = 0]) => value is num
    ? value.toInt()
    : value == null
        ? fallback
        : throw const FormatException('not a number');

/// One player event, or null for anything this version does not know.
DVMediaBackendEvent? dvParseMediaEvent(String json) {
  final Map<String, Object?>? event = _object(json);
  if (event == null) return null;
  try {
    return switch (event['type']) {
      'ready' => DVMediaReady(duration: _ms(event['durationMs']) ?? .zero),
      'playing' => const DVMediaPlaying(),
      'paused' => const DVMediaPaused(),
      'buffering' => const DVMediaBuffering(),
      'position' => DVMediaPosition(_ms(event['ms']) ?? .zero,
          seek: _int(event['seek'])),
      'buffered' => DVMediaBuffered(<DVRange>[
          for (final Object? range in (event['ranges'] as List?) ?? const <Object?>[])
            if (range is List && range.length == 2)
              DVRange(_ms(range[0])!, _ms(range[1])!),
        ]),
      'seekCompleted' =>
        DVMediaSeekCompleted(_int(event['seek']), _ms(event['ms']) ?? .zero),
      'completed' => const DVMediaCompleted(),
      'videoSize' =>
        DVMediaVideoSize(_int(event['width']), _int(event['height'])),
      'pip' => DVMediaPictureInPictureChanged(event['active'] == true),
      'failed' => DVMediaFailed('${event['message'] ?? 'the player failed'}'),
      _ => null,
    };
  } on Object {
    return null;
  }
}

DVCameraLens? _lens(Object? name) => switch (name) {
      'back' => DVCameraLens.back,
      'front' => DVCameraLens.front,
      'external' => DVCameraLens.external,
      _ => null,
    };

/// One camera event, or null.
DVCameraEvent? dvParseCameraEvent(String json) {
  final Map<String, Object?>? event = _object(json);
  if (event == null) return null;
  try {
    switch (event['type']) {
      case 'opened':
        final DVCameraLens? lens = _lens(event['lens']);
        if (lens == null) return null;
        final Object? width = event['width'];
        final Object? height = event['height'];
        return DVCameraOpened(lens,
            width: width is num ? width.toInt() : null,
            height: height is num ? height.toInt() : null);
      case 'closed':
        return const DVCameraClosed();
      case 'photo':
        final Object? path = event['path'];
        return path is String ? DVCameraPhotoTaken(path) : null;
      case 'recordingStarted':
        return const DVCameraRecordingStarted();
      case 'recordingStopped':
        return DVCameraRecordingStopped(_ms(event['durationMs']) ?? .zero);
      case 'disconnected':
        return const DVCameraDisconnected();
      case 'failed':
        return DVCameraFailed('${event['message'] ?? 'the camera failed'}');
    }
  } on Object {
    return null;
  }
  return null;
}

/// One now-playing command, or null.
DVMediaCommand? dvParseMediaCommand(String json) {
  final Map<String, Object?>? command = _object(json);
  if (command == null) return null;
  DVTransportAction? action;
  for (final DVTransportAction candidate in DVTransportAction.values) {
    if (candidate.name == command['action']) action = candidate;
  }
  if (action == null) return null;
  if (action == DVTransportAction.seekTo) {
    final Object? ms = command['ms'];
    if (ms is! num) return null;
    return DVMediaCommand(action, position: Duration(milliseconds: ms.round()));
  }
  return DVMediaCommand(action);
}

/// What a native now-playing surface is handed to publish.
String dvEncodeNowPlaying(DVMediaSession session, DVNowPlayingState state) =>
    jsonEncode(<String, Object?>{
      'title': session.title,
      'artist': ?session.artist,
      'album': ?session.album,
      'artworkUrl': ?session.artworkUrl,
      'skipMs': session.skipInterval.inMilliseconds,
      'playing': state.playing,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
    });
