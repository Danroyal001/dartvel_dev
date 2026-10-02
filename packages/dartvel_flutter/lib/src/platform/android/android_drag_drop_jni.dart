/// Drag and drop on Android, through the `DartvelDragDrop` Java class that
/// `dartvel build android` writes.
///
/// Drops are taken by a `View.OnDragListener` on the window, so they arrive
/// from this application and from another one beside it: split screen, a
/// freeform or desktop window, a foldable's two halves, a tablet's taskbar.
/// The listener queues each event as JSON and this side drains the queue,
/// which is how the capture bridge answers too: no callback into Dart from
/// the UI thread.
///
/// A dropped file is a `content://` URI the dropping application granted for
/// this drop. It is read when the application asks, through a descriptor the
/// bridge opens and this side reads by `/proc/self/fd`, so a large video is
/// never copied just because it was dropped.
library dartvel_flutter.platform.android.drag_drop_jni;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:dartvel_core/dartvel.dart' show dvAndroidDragDropClass;
import 'package:jni/jni.dart';

import '../drag_drop.dart';
import 'android_drag_drop_shapes.dart';
import 'android_kiosk_jni.dart' show DVAndroidActivities;

class DVAndroidDragDrop {
  const DVAndroidDragDrop._();

  static const String bridgeClass = dvAndroidDragDropClass;

  static const Set<String> implemented = <String>{
    'dragDrop.accept',
    'dragDrop.stop',
    'dragDrop.startDrag',
  };

  static JClass? _bridge;
  static Timer? _poll;

  /// Why the bridge cannot be reached, or null when it can.
  static String? lastFailure;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    try {
      _bridge = JClass.forName(bridgeClass);
      lastFailure = null;
    } on Object catch (error) {
      _bridge = null;
      lastFailure = 'the class $bridgeClass is not in this application ($error). '
          '`dartvel build android` writes it; an APK built with plain '
          '`flutter build` has no drag and drop listener.';
    }
    bind('dragDrop.accept', (Object? _) {
      final bool ok = _callWithActivity('accept');
      if (ok) _startPolling();
      return ok;
    });
    bind('dragDrop.stop', (Object? _) {
      _poll?.cancel();
      _poll = null;
      return _callWithActivity('stop');
    });
    bind('dragDrop.startDrag', (Object? arguments) async {
      final Map<Object?, Object?> payload =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return _startDrag(await _withFilesWritten(payload));
    });
  }

  static JClass _class() {
    final JClass? bridge = _bridge;
    if (bridge == null) throw StateError(lastFailure ?? 'no drag and drop bridge');
    return bridge;
  }

  static JObject _activity() {
    final JObject? activity = DVAndroidActivities.current;
    if (activity == null) {
      throw StateError('No Activity is resumed, so there is no window to drag '
          'into or out of.');
    }
    return activity;
  }

  static bool _callWithActivity(String method) {
    final JClass bridge = _class();
    final bool ok = bridge
        .staticMethodId(method, '(Landroid/app/Activity;)Z')
        .call(bridge, jboolean.type, <dynamic>[_activity()]);
    if (!ok) throw StateError('Android drag and drop $method failed: ${_lastError()}');
    return ok;
  }

  static String? _lastError() {
    final JClass bridge = _class();
    return bridge
        .staticMethodId('lastError', '()Ljava/lang/String;')
        .callNullable(bridge, JString.type, <dynamic>[])
        ?.toDartString(releaseOriginal: true);
  }

  /// Drains the bridge's queue. Quick while a drag is over the window, so a
  /// target's highlight follows the finger; slow otherwise, because nothing
  /// is happening and the check costs a wake-up.
  static void _startPolling() {
    _poll?.cancel();
    const Duration idle = Duration(milliseconds: 200);
    const Duration dragging = Duration(milliseconds: 32);
    Duration gap = idle;
    void schedule() {
      _poll = Timer(gap, () {
        gap = _drain() ? dragging : (gap == dragging ? dragging : idle);
        schedule();
      });
    }

    schedule();
  }

  /// Delivers every queued event; true while a drag is over the window.
  static bool _drain() {
    final JClass bridge = _class();
    final JStaticMethodId next = bridge.staticMethodId('next', '()Ljava/lang/String;');
    bool hovering = false;
    while (true) {
      final String? json =
          next.callNullable(bridge, JString.type, <dynamic>[])?.toDartString(releaseOriginal: true);
      if (json == null) break;
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map) continue;
      final double ratio = PlatformDispatcher.instance.views.isEmpty
          ? 1
          : PlatformDispatcher.instance.views.first.devicePixelRatio;
      switch (decoded['kind']) {
        case 'hover':
          hovering = true;
          DVDragDrop.dispatchHover(
            ((decoded['x'] as num?) ?? 0) / ratio,
            ((decoded['y'] as num?) ?? 0) / ratio,
          );
        case 'leave':
          hovering = false;
          DVDragDrop.dispatchLeave();
        case 'drop':
          hovering = false;
          final Map<String, Object?> map = dvAndroidDropMap(decoded, devicePixelRatio: ratio);
          final List<Object?> files = map['files']! as List<Object?>;
          DVDragDrop.dispatch(DVDropEvent.fromMap(map, readers: (int index) {
            return _read('${(files[index]! as Map<Object?, Object?>)['uri']}');
          }));
      }
    }
    return hovering;
  }

  /// A dropped file's bytes, through a descriptor the bridge opens under the
  /// drop's grant.
  static Future<Uint8List> _read(String uri) async {
    final JClass bridge = _class();
    final int descriptor = bridge
        .staticMethodId('open', '(Landroid/app/Activity;Ljava/lang/String;)I')
        .call(bridge, jint.type, <dynamic>[_activity(), uri.toJString()]);
    if (descriptor < 0) {
      throw StateError('Android would not open the dropped file: ${_lastError()}');
    }
    try {
      return await File('/proc/self/fd/$descriptor').readAsBytes();
    } finally {
      bridge
          .staticMethodId('close', '(I)V')
          .call(bridge, jvoid.type, <dynamic>[descriptor]);
    }
  }

  /// Writes the files a drag carries as bytes into the directory the
  /// capture provider serves, so the receiving application reads them by
  /// `content://` URI.
  static Future<Map<Object?, Object?>> _withFilesWritten(Map<Object?, Object?> payload) async {
    final List<Object?> files = (payload['files'] as List?) ?? const <Object?>[];
    if (files.isEmpty) return payload;
    final JClass bridge = _class();
    final String directory = bridge
        .staticMethodId('outgoingDirectory', '(Landroid/content/Context;)Ljava/lang/String;')
        .call(bridge, JString.type, <dynamic>[_activity()])
        .toDartString(releaseOriginal: true);
    final List<Map<String, Object?>> written = <Map<String, Object?>>[];
    for (final Object? raw in files) {
      if (raw is! Map) continue;
      String? path = raw['path'] as String?;
      final List<Object?>? bytes = raw['bytes'] as List?;
      if (bytes != null) {
        final String name = '${raw['name']}'.replaceAll(RegExp(r'[/\\]|\.\.'), '_');
        path = '$directory/$name';
        await File(path).writeAsBytes(bytes.cast<int>(), flush: true);
      } else if (path != null && !path.startsWith(directory)) {
        // The provider serves one directory and nothing outside it.
        final String name = path.split('/').last;
        final String copy = '$directory/$name';
        await File(path).copy(copy);
        path = copy;
      }
      if (path == null) continue;
      written.add(<String, Object?>{
        'name': raw['name'],
        'mimeType': raw['mimeType'],
        'path': path,
      });
    }
    return <Object?, Object?>{...payload, 'files': written};
  }

  static bool _startDrag(Map<Object?, Object?> payload) {
    final JClass bridge = _class();
    final bool started = bridge
        .staticMethodId('startDrag', '(Landroid/app/Activity;Ljava/lang/String;)Z')
        .call(bridge, jboolean.type, <dynamic>[_activity(), jsonEncode(payload).toJString()]);
    return started;
  }

  static void unregister() {
    _poll?.cancel();
    _poll = null;
    _bridge = null;
  }
}
