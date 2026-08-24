/// Browser implementations of the `DV.Platform` bindings.
///
/// Ordinary web APIs through `dart:js_interop` — no FFI, no toolchain, no
/// vendor SDK. The web is the one platform where the whole gap is closeable in
/// Dart, which is why it is the first one filled in after Linux.
///
/// Only what the browser genuinely does is registered; see
/// `web_capabilities.dart` for why the rest is left throwing.
library dartvel_flutter.platform.web.js;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'web_capabilities.dart';

/// Registers the browser bindings.
class DVWebBindings {
  const DVWebBindings._();

  static bool _registered = false;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvWebImplementedBindings;

  static bool register() {
    if (_registered) return true;

    DVNativeBridge.register('clipboard.copy', (Object? arguments) async {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      await web.window.navigator.clipboard.writeText(text).toDart;
      return true;
    });

    DVNativeBridge.register('clipboard.paste', (Object? _) async {
      // Reading needs a secure context and, in most browsers, a user gesture.
      // The rejection is allowed to propagate: a caller that asked for the
      // clipboard and got an empty string would report it as a clipboard bug.
      final text = await web.window.navigator.clipboard.readText().toDart;
      return text.toDart;
    });

    DVNativeBridge.register('screen.geometry', (Object? _) {
      final screen = web.window.screen;
      return <String, Object?>{
        'width': screen.width,
        'height': screen.height,
        'devicePixelRatio': web.window.devicePixelRatio,
      };
    });

    DVNativeBridge.register('notifications.sendLocal', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      // Permission is the caller's to obtain. Requesting it here would pop a
      // browser prompt from whatever code path happened to send a
      // notification, which is exactly the pattern browsers added the
      // user-gesture requirement to discourage.
      if (web.Notification.permission != 'granted') {
        throw StateError(
          'Notification permission has not been granted. Request it from a '
          'user gesture before calling notifications.sendLocal.',
        );
      }
      web.Notification(
        '${map['title'] ?? ''}',
        web.NotificationOptions(body: '${map['body'] ?? ''}'),
      );
      return true;
    });

    DVNativeBridge.register('share.text', (Object? arguments) async {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      await web.window.navigator
          .share(web.ShareData(
            title: '${map['title'] ?? ''}',
            text: '${map['text'] ?? ''}',
          ))
          .toDart;
      return true;
    });

    // navigator.vibrate is the only haptic primitive the web has. It takes a
    // duration and knows nothing of impact weight, so the three names differ
    // only in how long they buzz rather than pretending to a fidelity that is
    // not there.
    DVNativeBridge.register('haptics.lightVibrate', (Object? _) => _vibrate(10));
    DVNativeBridge.register('haptics.impact', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final weight = '${map['style'] ?? 'medium'}';
      return _vibrate(switch (weight) {
        'light' => 10,
        'heavy' => 50,
        _ => 25,
      });
    });
    DVNativeBridge.register('haptics.vibrate', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final duration = map['duration'];
      return _vibrate(duration is int ? duration : 25);
    });

    DVNativeBridge.register('window.setTitle', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      web.document.title = '${map['title'] ?? ''}';
      return true;
    });

    _registered = true;
    return true;
  }

  static bool _vibrate(int milliseconds) =>
      web.window.navigator.vibrate(milliseconds.toJS);

  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _registered = false;
  }
}
