/// `DVBox.camera` in a browser: getUserMedia into a `<video>` shown as a
/// platform view, photos drawn off it onto a canvas, recordings through
/// MediaRecorder.
///
/// The web has no file paths. Photos and recordings go into
/// [DVWebCaptureStore]: the `DVFile.path` a capture hands back is a
/// `dvcapture:<n>.<ext>` key, and `DVWebCaptureStore.instance.bytesOf(path)`
/// is the bytes. They last as long as the page.
library dartvel_flutter.platform.web.camera;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../media/media_box.dart';
import '../../media/web_media_mapping.dart';
import 'web_interop.dart';

/// Binds the browser camera.
abstract final class DVWebCamera {
  static bool _registered = false;

  /// What the page knows before opening anything. A browser does not say
  /// which cameras exist, or whether one has a torch, until it is asked for
  /// one -- and asking is the permission prompt. So both lenses are offered
  /// (`facingMode` falls back to whatever camera there is) and the torch is
  /// reported once a stream is open and its track says it has one.
  static DVCameraCapabilities get initialCapabilities => DVCameraCapabilities(
        lenses: const <DVCameraLens>{DVCameraLens.back, DVCameraLens.front},
        photo: true,
        video: recorderAvailable,
        preview: true,
        videoQualities: recorderAvailable
            ? const <DVVideoQuality>{
                DVVideoQuality.sd480,
                DVVideoQuality.hd720,
                DVVideoQuality.hd1080,
              }
            : const <DVVideoQuality>{},
      );

  static bool get recorderAvailable => globalContext.has('MediaRecorder');

  static void register() {
    if (_registered) return;
    _registered = true;
    DVMediaBackends.useCaptureFiles(DVWebCaptureStore.instance);
    DVMediaBackends.registerCamera(DVWebCameraBackend.new,
        capabilities: initialCapabilities);
  }
}

int _nextCameraView = 0;

final class DVWebCameraBackend implements DVCameraBackend, DVCameraSurface {
  DVWebCameraBackend()
      : _video = web.document.createElement('video') as web.HTMLVideoElement,
        _viewType = 'dartvel-camera-${_nextCameraView++}' {
    _video
      ..autoplay = true
      ..muted = true;
    _video.setAttribute('playsinline', 'true');
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
  }

  final web.HTMLVideoElement _video;
  final String _viewType;
  final StreamController<DVCameraEvent> _events =
      StreamController<DVCameraEvent>.broadcast();
  web.MediaStream? _stream;
  bool _torch = false;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = <web.Blob>[];
  DateTime? _recordingSince;

  void _emit(DVCameraEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  DVCameraCapabilities get capabilities {
    final DVCameraCapabilities base = DVWebCamera.initialCapabilities;
    return DVCameraCapabilities(
      lenses: base.lenses,
      photo: base.photo,
      video: base.video,
      preview: base.preview,
      videoQualities: base.videoQualities,
      torch: _torch,
    );
  }

  @override
  Stream<DVCameraEvent> get events => _events.stream;

  web.MediaStreamTrack? get _videoTrack {
    final web.MediaStream? stream = _stream;
    if (stream == null) return null;
    final List<web.MediaStreamTrack> tracks = stream.getVideoTracks().toDart;
    return tracks.isEmpty ? null : tracks.first;
  }

  void _stopStream() {
    final web.MediaStream? stream = _stream;
    _stream = null;
    if (stream == null) return;
    for (final web.MediaStreamTrack track in stream.getTracks().toDart) {
      track.stop();
    }
    _video.srcObject = null;
  }

  @override
  Future<void> open(DVCameraLens lens) async {
    _stopStream();
    try {
      final JSObject video = JSObject()
        ..setProperty('facingMode'.toJS,
            (JSObject()..setProperty('ideal'.toJS,
                (lens == DVCameraLens.front ? 'user' : 'environment').toJS)));
      final web.MediaStream stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: video))
          .toDart;
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      final web.MediaStreamTrack? track = _videoTrack;
      int? width;
      int? height;
      if (track != null) {
        final JSObject settings = track.getSettings() as JSObject;
        width = dvJsNum(settings, 'width')?.toInt();
        height = dvJsNum(settings, 'height')?.toInt();
        final JSObject capabilities = dvJsMethod(track as JSObject, 'getCapabilities') == null
            ? JSObject()
            : track.getCapabilities() as JSObject;
        _torch = dvJsHas(capabilities, 'torch');
      }
      _emit(DVCameraOpened(lens, width: width, height: height));
    } on Object catch (error) {
      _emit(DVCameraFailed(dvJsReason(error)));
    }
  }

  @override
  Future<void> close() async {
    _stopStream();
    _emit(const DVCameraClosed());
  }

  @override
  Future<void> takePhoto(String path,
      {DVFlashMode flash = DVFlashMode.off}) async {
    try {
      final int width = _video.videoWidth;
      final int height = _video.videoHeight;
      if (width == 0 || height == 0) {
        throw StateError('the camera has sent no frame yet');
      }
      final web.HTMLCanvasElement canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = width
            ..height = height;
      (canvas.getContext('2d')! as web.CanvasRenderingContext2D)
          .drawImage(_video, 0, 0);
      final Completer<web.Blob?> encoded = Completer<web.Blob?>();
      canvas.toBlob(
          ((web.Blob? blob) => encoded.complete(blob)).toJS, 'image/jpeg', 0.92.toJS);
      final web.Blob? blob = await encoded.future;
      if (blob == null) throw StateError('the frame could not be encoded');
      DVWebCaptureStore.instance.write(path, await _bytes(blob));
      _emit(DVCameraPhotoTaken(path));
    } on Object catch (error) {
      _emit(DVCameraFailed('$error'));
    }
  }

  static Future<Uint8List> _bytes(web.Blob blob) async =>
      (await blob.arrayBuffer().toDart).toDart.asUint8List();

  String _recordingPath = '';

  @override
  Future<void> startRecording(String path,
      {DVVideoQuality quality = DVVideoQuality.hd720, bool audio = true}) async {
    final web.MediaStream? stream = _stream;
    if (stream == null) {
      _emit(const DVCameraFailed('the camera is not open'));
      return;
    }
    try {
      final List<web.MediaStreamTrack> tracks = <web.MediaStreamTrack>[
        ...stream.getVideoTracks().toDart,
      ];
      if (audio) {
        final web.MediaStream microphone = await web.window.navigator
            .mediaDevices
            .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
            .toDart;
        tracks.addAll(microphone.getAudioTracks().toDart);
      }
      final web.MediaStream recorded = web.MediaStream(tracks.toJS);
      // MP4 where the browser can write it, so the file matches the
      // request's video/mp4; WebM otherwise.
      final String type = web.MediaRecorder.isTypeSupported('video/mp4')
          ? 'video/mp4'
          : 'video/webm';
      final web.MediaRecorder recorder = web.MediaRecorder(
          recorded, web.MediaRecorderOptions(mimeType: type));
      _chunks.clear();
      _recordingPath = path;
      recorder.addEventListener(
          'dataavailable',
          ((web.BlobEvent event) {
            if (event.data.size > 0) _chunks.add(event.data);
          }).toJS);
      recorder.addEventListener(
          'stop',
          ((web.Event _) {
            unawaited(_finishRecording(recorded, audio));
          }).toJS);
      recorder.start();
      _recorder = recorder;
      _recordingSince = DateTime.now();
      _emit(const DVCameraRecordingStarted());
    } on Object catch (error) {
      _emit(DVCameraFailed(dvJsReason(error)));
    }
  }

  Future<void> _finishRecording(web.MediaStream recorded, bool audio) async {
    if (audio) {
      for (final web.MediaStreamTrack track
          in recorded.getAudioTracks().toDart) {
        track.stop();
      }
    }
    final web.Blob blob = web.Blob(_chunks.toJS);
    _chunks.clear();
    final Duration duration = DateTime.now()
        .difference(_recordingSince ?? DateTime.now());
    try {
      DVWebCaptureStore.instance.write(_recordingPath, await _bytes(blob));
      _emit(DVCameraRecordingStopped(duration));
    } on Object catch (error) {
      _emit(DVCameraFailed('$error'));
    }
  }

  @override
  Future<void> stopRecording() async {
    final web.MediaRecorder? recorder = _recorder;
    _recorder = null;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();
  }

  @override
  Future<void> setTorch(bool on) async {
    final web.MediaStreamTrack? track = _videoTrack;
    if (track == null) return;
    final JSObject constraint = JSObject()
      ..setProperty('torch'.toJS, on.toJS);
    final JSObject constraints = JSObject()
      ..setProperty('advanced'.toJS, <JSObject>[constraint].toJS);
    await track
        .applyConstraints(constraints as web.MediaTrackConstraints)
        .toDart;
  }

  @override
  Widget buildPreview(BuildContext context) =>
      HtmlElementView(viewType: _viewType);

  @override
  Future<void> dispose() async {
    await stopRecording();
    _stopStream();
    await _events.close();
  }
}
