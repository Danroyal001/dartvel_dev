/// Browser implementations of the `DV.Platform` bindings.
///
/// Ordinary web APIs through `dart:js_interop` — no FFI, no toolchain, no
/// vendor SDK. The web is the one platform where the whole gap is closeable in
/// Dart, which is why it is the first one filled in after Linux.
///
/// Only what the browser genuinely does is registered; see
/// `web_capabilities.dart` for why the rest is left throwing.
library dartvel_flutter.platform.web.js;

import 'dart:async' show unawaited;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import '../../pwa/install_prompt.dart';
import 'web_capabilities.dart';
import 'web_kiosk_js.dart';

/// Registers the browser bindings.
class DVWebBindings {
  const DVWebBindings._();

  static bool _registered = false;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvWebImplementedBindings;

  /// Listens for the browser's install offer.
  ///
  /// `beforeinstallprompt` fires once, at whatever moment the browser decides
  /// the app qualifies -- which is not first frame -- and only when the app is
  /// not already installed. preventDefault stops the browser's own mini
  /// infobar so the application can place the affordance itself, which is the
  /// entire reason to capture the event rather than leave it alone.
  static void _wireInstallPrompt() {
    web.window.addEventListener(
      'beforeinstallprompt',
      (web.Event event) {
        event.preventDefault();
        _deferred = event;
        DVInstallPrompt.offer();
      }.toJS,
    );

    web.window.addEventListener(
      'appinstalled',
      (web.Event _) {
        _deferred = null;
        DVInstallPrompt.markInstalled();
      }.toJS,
    );

    // Already running as an installed app: display-mode is standalone. The
    // browser will never fire beforeinstallprompt here, so without this check
    // canPrompt stays false for the right reason rather than by accident.
    final web.MediaQueryList standalone =
        web.window.matchMedia('(display-mode: standalone)');
    if (standalone.matches) DVInstallPrompt.markInstalled();
  }

  /// The captured event, kept because prompt() has to be called on it.
  static web.Event? _deferred;

  /// Shows the browser prompt, from a user gesture.
  static Future<void> showInstallPrompt() async {
    final web.Event? event = _deferred;
    if (event == null) return;
    _deferred = null;
    (event as JSObject).callMethod<JSAny?>('prompt'.toJS);
  }

  static bool register() {
    if (_registered) return true;

    _wireInstallPrompt();

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

    // navigator.bluetooth.getAvailability(), where it exists. Answering
    // false is the honest result on a browser without Web Bluetooth; it is
    // not the same as the call being unimplemented, which is what the caller
    // used to get.
    DVNativeBridge.register('bluetooth.isEnabled', (Object? _) async {
      final JSObject? navigator = _property(globalContext, 'navigator');
      final JSObject? bluetooth =
          navigator == null ? null : _property(navigator, 'bluetooth');
      if (bluetooth == null) return false;
      final JSFunction? available = _method(bluetooth, 'getAvailability');
      if (available == null) return false;
      final JSAny? result = available.callAsFunction(bluetooth);
      if (result.isA<JSPromise<JSAny?>>()) {
        final JSAny? value = await (result! as JSPromise<JSAny?>).toDart;
        return value.dartify() == true;
      }
      return result.dartify() == true;
    });

    // NDEFReader is Chrome on Android and nowhere else, so this is false on a
    // desktop browser -- which is the platform reporting itself rather than
    // Dartvel guessing.
    DVNativeBridge.register(
      'nfc.isAvailable',
      (Object? _) async => _property(globalContext, 'NDEFReader') != null,
    );

    // PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().
    // A browser with no platform authenticator answers false; one without
    // WebAuthn at all answers false too, because both mean the same thing to
    // a caller deciding whether to offer the option.
    DVNativeBridge.register(
      'biometrics.canAuthenticate',
      (Object? _) async => _platformAuthenticator(),
    );

    // WebAuthn with userVerification required: the browser's own platform
    // biometric prompt. It resolves with an assertion or throws, and there is
    // no third outcome -- no authenticator, or a person who declines, both
    // reach the caller as a failure rather than as a quiet false.
    //
    // Like every platform's local biometric API this gates the interface and
    // proves nothing to a server; a passkey sign-in verifies its assertion
    // server-side and is a different flow.
    DVNativeBridge.register('biometrics.authenticate', (Object? _) async {
      final JSObject? navigator = _property(globalContext, 'navigator');
      final JSObject? credentials =
          navigator == null ? null : _property(navigator, 'credentials');
      final JSFunction? get =
          credentials == null ? null : _method(credentials, 'get');
      if (credentials == null || get == null) {
        throw StateError(
          'This browser has no credentials API, so it cannot authenticate.',
        );
      }

      // Asked first, and refused here. With no platform authenticator
      // navigator.credentials.get does not reject -- it waits out its own
      // timeout, a minute of nothing, and the caller cannot tell that from a
      // person taking their time. The same probe canAuthenticate reports, so
      // the answer and the behaviour cannot disagree.
      if (!await _platformAuthenticator()) {
        throw StateError(
          'This browser has no platform authenticator, so there is nothing '
          'to authenticate against.',
        );
      }

      // Random rather than fixed. A constant challenge is a replayable one,
      // and habits from a local gate end up in flows that are not local.
      final Uint8List challenge = Uint8List(32);
      final JSObject? crypto = _property(globalContext, 'crypto');
      final JSFunction? fill =
          crypto == null ? null : _method(crypto, 'getRandomValues');
      if (fill != null) {
        fill.callAsFunction(crypto, challenge.toJS);
      }

      final JSObject publicKey = JSObject()
        ..setProperty('challenge'.toJS, challenge.toJS)
        ..setProperty('userVerification'.toJS, 'required'.toJS)
        ..setProperty('timeout'.toJS, 60000.toJS);
      final JSObject options = JSObject()
        ..setProperty('publicKey'.toJS, publicKey);

      final JSAny? call = get.callAsFunction(credentials, options);
      if (!call.isA<JSPromise<JSAny?>>()) {
        throw StateError('credentials.get did not return a promise.');
      }
      final JSAny? assertion = await (call! as JSPromise<JSAny?>).toDart;
      if (assertion == null) {
        throw StateError('No assertion was returned.');
      }
      return true;
    });

    DVWebKiosk.register(DVNativeBridge.register);

    _registered = true;
    return true;
  }

  static bool _vibrate(int milliseconds) =>
      web.window.navigator.vibrate(milliseconds.toJS);

  static void unregister() {
    unawaited(DVWebKiosk.release());
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _registered = false;
  }
}

/// A property of [object], or null when it is absent or undefined.
///
/// Written out rather than reached through a typed binding because these APIs
/// are the ones browsers most often do not have, and a missing one has to be
/// an answer rather than a crash.
JSObject? _property(JSObject object, String name) {
  if (!object.has(name)) return null;
  final JSAny? value = object.getProperty(name.toJS);
  return value.isA<JSObject>() ? value! as JSObject : null;
}

/// A callable property of [object], or null when it is absent.
JSFunction? _method(JSObject object, String name) {
  if (!object.has(name)) return null;
  final JSAny? value = object.getProperty(name.toJS);
  return value.isA<JSFunction>() ? value! as JSFunction : null;
}

/// Whether the browser has a user-verifying platform authenticator.
///
/// One definition for both `biometrics.canAuthenticate` and the gate in
/// `biometrics.authenticate`, so the answer a caller is given and the
/// behaviour it then gets cannot disagree.
Future<bool> _platformAuthenticator() async {
  final JSObject? credential = _property(globalContext, 'PublicKeyCredential');
  if (credential == null) return false;
  final JSFunction? probe =
      _method(credential, 'isUserVerifyingPlatformAuthenticatorAvailable');
  if (probe == null) return false;
  final JSAny? result = probe.callAsFunction(credential);
  if (result.isA<JSPromise<JSAny?>>()) {
    final JSAny? value = await (result! as JSPromise<JSAny?>).toDart;
    return value.dartify() == true;
  }
  return result.dartify() == true;
}
