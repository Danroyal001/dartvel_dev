/// What a native player, camera or media session queues, read into the
/// events the controllers in dartvel_core act on.
///
/// One shape for every target that talks JSON across the boundary -- the
/// Android Java and the Apple Swift both emit it -- so the reading is
/// written, and tested, once. Plain Dart with no JNI or FFI, so it runs in a
/// VM test.
///
/// Anything unreadable is dropped rather than thrown: these are read in a
/// poll loop, and one malformed event must not stop every player.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

Map<String, Object?>? _object(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> _array(String? json) {
  if (json == null || json.isEmpty) return const <Object?>[];
  try {
    final Object? decoded = jsonDecode(json);
    return decoded is List ? decoded : const <Object?>[];
  } on FormatException {
    return const <Object?>[];
  }
}

Map<String, Object?>? _decodeObject(String json) {
  try {
    return _object(jsonDecode(json));
  } on FormatException {
    return null;
  }
}

Duration? _ms(Object? value) =>
    value is num ? Duration(milliseconds: value.round()) : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

/// One player event, or null.
DVMediaBackendEvent? dvParseMediaEvent(String json) {
  final Map<String, Object?>? event = _decodeObject(json);
  return event == null ? null : _mediaEvent(event);
}

/// A JSON array of player events. Empty for null.
List<DVMediaBackendEvent> dvParseMediaEvents(String? json) => <DVMediaBackendEvent>[
      for (final Object? item in _array(json))
        if (_object(item) case final Map<String, Object?> event)
          if (_mediaEvent(event) case final DVMediaBackendEvent parsed) parsed,
    ];

DVMediaBackendEvent? _mediaEvent(Map<String, Object?> event) {
  switch (event['type']) {
    case 'ready':
      return DVMediaReady(duration: _ms(event['durationMs']) ?? Duration.zero);
    case 'playing':
      return const DVMediaPlaying();
    case 'paused':
      return const DVMediaPaused();
    case 'buffering':
      return const DVMediaBuffering();
    case 'completed':
      return const DVMediaCompleted();
    case 'position':
      final Duration? at = _ms(event['ms']);
      return at == null ? null : DVMediaPosition(at, seek: _int(event['seek']) ?? 0);
    case 'buffered':
      final Duration? to = _ms(event['ms']);
      return to == null
          ? null
          : DVMediaBuffered(<DVRange>[DVRange(Duration.zero, to)]);
    case 'seekCompleted':
      final int? generation = _int(event['gen']);
      final Duration? at = _ms(event['ms']);
      return generation == null || at == null
          ? null
          : DVMediaSeekCompleted(generation, at);
    case 'videoSize':
      final int? width = _int(event['width']);
      final int? height = _int(event['height']);
      return width == null || height == null
          ? null
          : DVMediaVideoSize(width, height);
    case 'pip':
      return DVMediaPictureInPictureChanged(event['active'] == true);
    case 'failed':
      return DVMediaFailed('${event['message'] ?? 'the player failed'}');
  }
  return null;
}

DVCameraLens? _lens(Object? name) => switch (name) {
      'back' => DVCameraLens.back,
      'front' => DVCameraLens.front,
      'external' => DVCameraLens.external,
      _ => null,
    };

/// One camera event, or null.
DVCameraEvent? dvParseCameraEvent(String json) {
  final Map<String, Object?>? event = _decodeObject(json);
  return event == null ? null : _cameraEvent(event);
}

/// A JSON array of camera events. Empty for null.
List<DVCameraEvent> dvParseCameraEvents(String? json) => <DVCameraEvent>[
      for (final Object? item in _array(json))
        if (_object(item) case final Map<String, Object?> event)
          if (_cameraEvent(event) case final DVCameraEvent parsed) parsed,
    ];

DVCameraEvent? _cameraEvent(Map<String, Object?> event) {
  switch (event['type']) {
    case 'opened':
      final DVCameraLens? lens = _lens(event['lens']);
      return lens == null
          ? null
          : DVCameraOpened(lens,
              width: _int(event['width']), height: _int(event['height']));
    case 'closed':
      return const DVCameraClosed();
    case 'photo':
      final Object? path = event['path'];
      return path is String ? DVCameraPhotoTaken(path) : null;
    case 'recordingStarted':
      return const DVCameraRecordingStarted();
    case 'recordingStopped':
      return DVCameraRecordingStopped(_ms(event['ms']) ?? Duration.zero);
    case 'disconnected':
      return const DVCameraDisconnected();
    case 'failed':
      return DVCameraFailed('${event['message'] ?? 'the camera failed'}');
  }
  return null;
}

/// One lock-screen command, or null.
DVMediaCommand? dvParseMediaCommand(String json) {
  final Map<String, Object?>? command = _decodeObject(json);
  return command == null ? null : _command(command);
}

/// A JSON array of lock-screen commands. Empty for null.
List<DVMediaCommand> dvParseMediaCommands(String? json) => <DVMediaCommand>[
      for (final Object? item in _array(json))
        if (_object(item) case final Map<String, Object?> command)
          if (_command(command) case final DVMediaCommand parsed) parsed,
    ];

DVMediaCommand? _command(Map<String, Object?> command) {
  final Object? action = command['action'];
  for (final DVTransportAction known in DVTransportAction.values) {
    if (known.name != action) continue;
    if (known == DVTransportAction.seekTo) {
      final Duration? to = _ms(command['ms']);
      return to == null ? null : DVMediaCommand(known, position: to);
    }
    return DVMediaCommand(known);
  }
  return null;
}

/// What a device's camera report says it has. Nothing, for no report.
DVCameraCapabilities dvParseCameraCapabilities(String? json) {
  final Map<String, Object?>? report = json == null ? null : _decodeObject(json);
  if (report == null || report['error'] != null) return DVCameraCapabilities.none;
  final Set<DVCameraLens> lenses = <DVCameraLens>{
    for (final Object? name in (report['lenses'] as List?) ?? const <Object?>[])
      if (_lens(name) case final DVCameraLens lens) lens,
  };
  if (lenses.isEmpty) return DVCameraCapabilities.none;
  final Set<DVVideoQuality> qualities = <DVVideoQuality>{
    for (final Object? name in (report['qualities'] as List?) ?? const <Object?>[])
      for (final DVVideoQuality quality in DVVideoQuality.values)
        if (quality.name == name) quality,
  };
  return DVCameraCapabilities(
    lenses: lenses,
    flash: report['flash'] == true,
    torch: report['torch'] == true,
    photo: true,
    preview: true,
    video: qualities.isNotEmpty,
    videoQualities: qualities,
  );
}
