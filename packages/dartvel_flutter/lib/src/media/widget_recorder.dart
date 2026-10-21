/// Recording or streaming what part of the screen shows.
///
/// `DVBox.recorded(recorder: r, child: ...)` marks the subtree; `r.start()`
/// records it to a private MP4 and `r.start(streamTo: rtmpUrl)` sends it live
/// to a streaming service. The pixels are Flutter's own, so whatever the
/// subtree draws -- video, a camera, text, transitions -- is what is recorded,
/// at a fixed size chosen when it starts. Encoding is the target's: a
/// [DVFrameEncoder] registered with [DVMediaBackends].
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'media_box.dart';
import 'video_frame.dart';

/// Where an encoder sends frames: a file, or a live stream.
final class DVFrameEncoderTarget {
  const DVFrameEncoderTarget.file(String this.path) : url = null;
  const DVFrameEncoderTarget.stream(Uri this.url) : path = null;

  final String? path;
  final Uri? url;
}

/// What a target's encoder can do. Reported, never assumed.
final class DVFrameEncoderCapabilities {
  const DVFrameEncoderCapabilities({
    this.file = false,
    this.stream = false,
    this.audio = false,
  });

  static const DVFrameEncoderCapabilities none = DVFrameEncoderCapabilities();

  /// Can write an MP4 file.
  final bool file;

  /// Can send RTMP to a streaming service.
  final bool stream;

  /// Can mix the microphone in.
  final bool audio;
}

/// A target's video encoder: frames in, a file or a stream out.
abstract interface class DVFrameEncoder {
  DVFrameEncoderCapabilities get capabilities;

  /// Why the encoder stopped on its own: a full disk, a stream the server
  /// dropped.
  Stream<String> get failures;

  /// Starts encoding [width] by [height] frames at [fps] into [target].
  Future<void> start(DVFrameEncoderTarget target,
      {required int width, required int height, required int fps, required bool audio});

  /// The next frame, exactly [width] by [height]. Timestamped on arrival.
  void push(DVVideoFrame frame);

  /// Finishes the file or ends the stream; the length recorded.
  Future<Duration> stop();

  Future<void> dispose();
}

/// Recording is not possible here: no encoder is bound, or it cannot do
/// what was asked.
final class DVRecordingUnavailable implements Exception {
  const DVRecordingUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'DVRecordingUnavailable: $reason';
}

/// Where a [DVWidgetRecorder] is.
enum DVWidgetRecorderState { idle, recording, streaming, failed }

/// Records or streams a `DVBox.recorded` subtree.
final class DVWidgetRecorder {
  DVWidgetRecorder({
    this.fps = 30,
    this.quality = DVVideoQuality.hd720,
    this.audio = true,
  }) : assert(fps > 0 && fps <= 60);

  final int fps;
  final DVVideoQuality quality;

  /// Whether the microphone is mixed in, where the encoder can.
  final bool audio;

  final GlobalKey _boundary = GlobalKey(debugLabel: 'DVWidgetRecorder');
  final DVMutableMediaSignal<DVWidgetRecorderState> _state =
      DVMutableMediaSignal<DVWidgetRecorderState>(DVWidgetRecorderState.idle);
  final DVMutableMediaSignal<String?> _error = DVMutableMediaSignal<String?>(null);

  DVFrameEncoder? _encoder;
  StreamSubscription<String>? _failures;
  Timer? _timer;
  bool _capturing = false;
  String? _path;
  int _width = 0;
  int _height = 0;

  DVMediaSignal<DVWidgetRecorderState> get state => _state;

  /// Why the last recording failed; null otherwise.
  DVMediaSignal<String?> get error => _error;

  /// The key `DVBox.recorded` puts on its repaint boundary.
  @internal
  GlobalKey get boundaryKey => _boundary;

  int get _lines => switch (quality) {
        DVVideoQuality.sd480 => 480,
        DVVideoQuality.hd720 => 720,
        DVVideoQuality.hd1080 => 1080,
      };

  /// Starts recording into a private MP4, or streaming to [streamTo], an
  /// `rtmp://` or `rtmps://` URL with its key, as a streaming service gives
  /// it. Throws [DVRecordingUnavailable] where this target cannot, and a
  /// [StateError] when no `DVBox.recorded` with this recorder is on screen.
  Future<void> start({Uri? streamTo}) async {
    if (_state.value == DVWidgetRecorderState.recording ||
        _state.value == DVWidgetRecorderState.streaming) {
      return;
    }
    if (streamTo != null && streamTo.scheme != 'rtmp' && streamTo.scheme != 'rtmps') {
      throw ArgumentError.value(
          streamTo, 'streamTo', 'a live stream is an rtmp:// or rtmps:// URL');
    }
    final DVFrameEncoderCapabilities can = DVMediaBackends.frameEncoderCapabilities;
    if (streamTo == null ? !can.file : !can.stream) {
      throw DVRecordingUnavailable(streamTo == null
          ? 'this target cannot record video'
          : 'this target cannot stream video');
    }
    final RenderObject? render = _boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary || !render.hasSize || render.size.isEmpty) {
      throw StateError('Nothing to record: no DVBox.recorded with this '
          'recorder is on screen.');
    }
    final DVFrameEncoder? encoder = DVMediaBackends.createFrameEncoder();
    if (encoder == null) {
      throw const DVRecordingUnavailable('no video encoder is bound');
    }
    _height = _lines;
    _width = (render.size.width / render.size.height * _height).round();
    if (_width.isOdd) _width++;
    String? path;
    if (streamTo == null) path = await DVMediaBackends.captureFiles.reserve('mp4');
    _path = path;
    _encoder = encoder;
    _error.set(null);
    _failures = encoder.failures.listen(_fail);
    try {
      await encoder.start(
          path == null ? DVFrameEncoderTarget.stream(streamTo!) : DVFrameEncoderTarget.file(path),
          width: _width,
          height: _height,
          fps: fps,
          audio: audio && can.audio);
    } on Object catch (error) {
      await _release();
      if (path != null) await DVMediaBackends.captureFiles.discard(path);
      _path = null;
      _fail('$error');
      rethrow;
    }
    _state.set(path == null
        ? DVWidgetRecorderState.streaming
        : DVWidgetRecorderState.recording);
    _timer = Timer.periodic(
        Duration(microseconds: Duration.microsecondsPerSecond ~/ fps),
        (_) => _capture());
  }

  Future<void> _capture() async {
    if (_capturing) return; // a slow frame drops the next, never queues it
    final DVFrameEncoder? encoder = _encoder;
    final RenderObject? render = _boundary.currentContext?.findRenderObject();
    if (encoder == null || render is! RenderRepaintBoundary || !render.hasSize) {
      return;
    }
    // A boundary waiting to repaint has no current layer; in a debug build
    // toImage asserts on it, so wait for the next tick. A release build reads
    // the last painted layer, at most one frame old.
    if (_waitingToPaint(render)) return;
    _capturing = true;
    try {
      final double ratio = _height / render.size.height;
      final ui.Image shot = await render.toImage(pixelRatio: ratio);
      final ui.Image sized;
      if (shot.width == _width && shot.height == _height) {
        sized = shot;
      } else {
        // Rounded to the encoder's even width.
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        Canvas(recorder).drawImageRect(
            shot,
            Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
            Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
            Paint()..filterQuality = FilterQuality.medium);
        sized = await recorder.endRecording().toImage(_width, _height);
        shot.dispose();
      }
      final ByteData? bytes =
          await sized.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      sized.dispose();
      if (bytes == null || !identical(encoder, _encoder)) return;
      encoder.push(DVVideoFrame(
          width: _width, height: _height, rgba: bytes.buffer.asUint8List()));
    } finally {
      _capturing = false;
    }
  }

  static bool _waitingToPaint(RenderRepaintBoundary render) {
    bool waiting = false;
    assert(() {
      waiting = render.debugNeedsPaint;
      return true;
    }());
    return waiting;
  }

  void _fail(String message) {
    _error.set(message);
    _state.set(DVWidgetRecorderState.failed);
    _timer?.cancel();
    _timer = null;
    final DVFrameEncoder? encoder = _encoder;
    if (encoder != null) unawaited(encoder.stop().then((_) => _release(), onError: (_) => _release()));
  }

  /// Stops. A recording's file, or null for a stream.
  Future<DVFile?> stop() async {
    final DVFrameEncoder? encoder = _encoder;
    if (encoder == null) return null;
    _timer?.cancel();
    _timer = null;
    final Duration length = await encoder.stop();
    await _release();
    final String? path = _path;
    _path = null;
    if (_state.value != DVWidgetRecorderState.failed) {
      _state.set(DVWidgetRecorderState.idle);
    }
    if (path == null) return null;
    final int size = await DVMediaBackends.captureFiles.seal(path);
    return DVFile(path: path, mimeType: 'video/mp4', sizeBytes: size, duration: length);
  }

  Future<void> _release() async {
    await _failures?.cancel();
    _failures = null;
    final DVFrameEncoder? encoder = _encoder;
    _encoder = null;
    await encoder?.dispose();
  }

  /// Stops without keeping a file.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    final DVFrameEncoder? encoder = _encoder;
    if (encoder != null) {
      await encoder.stop();
      await _release();
    }
    final String? path = _path;
    _path = null;
    if (path != null) await DVMediaBackends.captureFiles.discard(path);
  }
}

/// Built by `DVBox.recorded`.
@internal
class DVRecordedView extends StatelessWidget {
  const DVRecordedView({super.key, required this.recorder, required this.child});

  final DVWidgetRecorder recorder;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: recorder.boundaryKey, child: child);
}
