/// `media.pick` and `camera.takePhoto` in a browser.
///
/// Picking is `<input type="file">`, which has worked in every browser since
/// before any of the other APIs in this directory existed. Taking a photo is
/// getUserMedia and one frame off the stream.
///
/// The one place the web cannot match the native contract is the path. A
/// desktop picker hands back `/home/somebody/holiday.jpg` and the picked file
/// keeps existing at that path; a browser hands back a File object and
/// nothing else, and there is no name that `files.readBytes` could later
/// open. So a pick here carries the bytes instead of a path, and the `path`
/// key is absent rather than filled with something plausible — an application
/// reading it gets null, which is checkable, instead of a string that fails
/// at the next call.
library dartvel_flutter.platform.web.media;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_interop.dart';

class DVWebMedia {
  const DVWebMedia._();

  static const Set<String> pickerBindings = <String>{'media.pick'};
  static const Set<String> cameraBindings = <String>{'camera.takePhoto'};

  /// Whether this browser can open a camera.
  ///
  /// `navigator.mediaDevices` is undefined outside a secure context, which is
  /// the common case for the check to catch: the same page over http has no
  /// camera at all and the binding must not be registered there.
  static bool get cameraAvailable {
    final JSObject? navigator = dvNavigator;
    if (navigator == null) return false;
    final JSObject? devices = dvJsObject(navigator, 'mediaDevices');
    return devices != null && dvJsMethod(devices, 'getUserMedia') != null;
  }

  /// The kinds a pick can be filtered to, and the accept attribute for each.
  ///
  /// Same vocabulary as the desktop bindings use, so `type: 'image'` means
  /// the same thing on both and the returned `type` can be compared across
  /// targets.
  static const Map<String, String> _accept = <String, String>{
    'image': 'image/*',
    'video': 'video/*',
    'audio': 'audio/*',
  };

  static void registerPicker(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('media.pick', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final String type = '${map['type'] ?? 'image'}';
      final bool multiple = map['multiple'] == true;

      final web.HTMLInputElement input =
          web.document.createElement('input') as web.HTMLInputElement;
      input.type = 'file';
      input.multiple = multiple;
      final String? accept = _accept[type];
      if (accept != null) input.accept = accept;
      // Off-screen rather than display:none. A hidden input is ignored by
      // some engines when it is clicked from script, and the failure is a
      // picker that never opens and never errors.
      input.style.position = 'fixed';
      input.style.left = '-10000px';
      web.document.body?.append(input);

      final Completer<List<Map<String, Object?>>> done =
          Completer<List<Map<String, Object?>>>();

      void finish(List<Map<String, Object?>> picked) {
        if (!done.isCompleted) done.complete(picked);
      }

      // Sync, because a function handed to `toJS` may not return a Future.
      // The reading itself is asynchronous and runs on its own; the completer
      // is what the binding waits on.
      final JSFunction onChange = (web.Event _) {
        unawaited(_read(input.files).then(finish, onError: (Object error) {
          if (!done.isCompleted) done.completeError(error);
        }));
      }.toJS;

      // Cancelling is not a failure and not an error: the desktop bindings
      // answer an empty list for a dialog somebody closed, and so does this.
      final JSFunction onCancel = (web.Event _) {
        finish(const <Map<String, Object?>>[]);
      }.toJS;

      input.addEventListener('change', onChange);
      input.addEventListener('cancel', onCancel);
      try {
        input.click();
        return await done.future;
      } on Object catch (error) {
        // Chrome and Safari refuse a programmatic click on a file input
        // without a user gesture. That is a refusal, and saying so points at
        // the call site rather than at the picker.
        dvJsRefused('media.pick', error);
      } finally {
        input.removeEventListener('change', onChange);
        input.removeEventListener('cancel', onCancel);
        input.remove();
      }
    });
  }

  /// Every file in [files], read into memory.
  static Future<List<Map<String, Object?>>> _read(web.FileList? files) async {
    final List<Map<String, Object?>> picked = <Map<String, Object?>>[];
    for (int i = 0; i < (files?.length ?? 0); i++) {
      final web.File? file = files!.item(i);
      if (file == null) continue;
      picked.add(await describe(file));
    }
    return picked;
  }

  /// One picked file, in the shape `DVMedia.pick` hands to an application.
  ///
  /// `name` and `type` match what the desktop bindings return for the same
  /// pick; `mimeType`, `size` and `bytes` are what the web has instead of a
  /// path.
  static Future<Map<String, Object?>> describe(web.File file) async {
    final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
    return <String, Object?>{
      'name': file.name,
      'type': kindOf(file.type, file.name),
      'mimeType': file.type,
      'size': file.size,
      'bytes': buffer.toDart.asUint8List(),
    };
  }

  /// image, video, audio or other, from the MIME type and the extension.
  ///
  /// The MIME type first because the browser usually knows it, the extension
  /// second because sometimes it does not and answers with an empty string.
  static String kindOf(String mimeType, String name) {
    for (final String kind in _accept.keys) {
      if (mimeType.startsWith('$kind/')) return kind;
    }
    const Map<String, String> byExtension = <String, String>{
      'png': 'image', 'jpg': 'image', 'jpeg': 'image', 'gif': 'image',
      'webp': 'image', 'bmp': 'image', 'svg': 'image',
      'mp4': 'video', 'webm': 'video', 'mkv': 'video', 'mov': 'video',
      'avi': 'video',
      'mp3': 'audio', 'wav': 'audio', 'ogg': 'audio', 'flac': 'audio',
      'm4a': 'audio',
    };
    final String extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return byExtension[extension] ?? 'other';
  }

  static void registerCamera(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('camera.takePhoto', (Object? _) => takePhoto());
  }

  /// One frame from the camera, as PNG bytes.
  ///
  /// The stream is stopped in a finally. A camera left running is the
  /// recording light staying on after the photo, which people notice and
  /// report as spying rather than as a leak.
  static Future<Uint8List> takePhoto() async {
    web.MediaStream? stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
          .toDart;
      return await _frame(stream);
    } on Object catch (error) {
      final String reason = dvJsReason(error);
      // A machine with no camera in it is not somebody saying no, and the two
      // want opposite things from an application: one hides the button, the
      // other asks again from a tap.
      if (reason.contains('NotFoundError') ||
          reason.contains('DevicesNotFoundError')) {
        throw StateError(
          'camera.takePhoto failed: this machine has no camera the browser '
          'can open ($reason).',
        );
      }
      dvJsRefused('camera.takePhoto', error);
    } finally {
      final web.MediaStream? open = stream;
      if (open != null) {
        final JSArray<web.MediaStreamTrack> tracks = open.getTracks();
        for (int i = 0; i < tracks.length; i++) {
          tracks.toDart[i].stop();
        }
      }
    }
  }

  /// Draws the first frame of [stream] onto a canvas and encodes it.
  static Future<Uint8List> _frame(web.MediaStream stream) async {
    final web.HTMLVideoElement video =
        web.document.createElement('video') as web.HTMLVideoElement;
    video.autoplay = true;
    video.muted = true;
    // Required on iOS, where a video that is not inline goes fullscreen the
    // moment it plays and the photo becomes a takeover of the screen.
    video.setAttribute('playsinline', 'true');
    video.srcObject = stream;

    final Completer<void> ready = Completer<void>();
    final JSFunction onLoaded = (web.Event _) {
      if (!ready.isCompleted) ready.complete();
    }.toJS;
    video.addEventListener('loadeddata', onLoaded);
    try {
      await video.play().toDart;
      await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          'The camera opened but sent no frame within five seconds.',
        ),
      );
    } finally {
      video.removeEventListener('loadeddata', onLoaded);
    }

    final int width = video.videoWidth;
    final int height = video.videoHeight;
    if (width == 0 || height == 0) {
      throw StateError('The camera reported a frame with no size.');
    }

    final web.HTMLCanvasElement canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = width;
    canvas.height = height;
    final web.CanvasRenderingContext2D context =
        canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.drawImage(video, 0, 0);
    video.srcObject = null;

    final Completer<web.Blob> encoded = Completer<web.Blob>();
    canvas.toBlob(
      (web.Blob? blob) {
        if (encoded.isCompleted) return;
        if (blob == null) {
          encoded.completeError(
            StateError('The frame could not be encoded as a PNG.'),
          );
        } else {
          encoded.complete(blob);
        }
      }.toJS,
      'image/png',
    );
    final web.Blob blob = await encoded.future;
    final JSArrayBuffer buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}
