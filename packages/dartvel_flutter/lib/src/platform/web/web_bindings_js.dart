/// Browser implementations of the `DV.Platform` bindings.
///
/// Ordinary web APIs through `dart:js_interop` — no FFI, no toolchain, no
/// vendor SDK. The web is the one platform where the whole gap is closeable
/// in Dart, which is why it is the first one filled in after Linux.
///
/// Two rules run through every registration below.
///
/// **Probe before binding.** A name is registered only where this browser has
/// the API behind it. Web NFC, Web Bluetooth, the Contact Picker and the
/// Generic Sensor API are Chromium-only; `navigator.share` is missing on
/// desktop Firefox; `navigator.vibrate` is missing on every Safari. Binding
/// them everywhere and answering null off Chromium would read as support,
/// which is worse than no binding at all — so on those browsers the name goes
/// unregistered and `DVNativeBridge.isRegistered` reports the truth.
///
/// **A refusal is not an absence.** An unregistered name throws
/// `DVNativeBridge`'s own "not registered" error. A capability the browser
/// has and refuses — Deny, no user gesture, an insecure origin — throws
/// [DVWebPermissionDenied] with what the browser said. An application that
/// cannot tell those apart either offers a feature that can never work, or
/// hides one that a second tap would turn on.
///
/// See `web_capabilities.dart` for the full list, including the names the web
/// cannot serve and the reason for each.
library dartvel_flutter.platform.web.js;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import '../../pwa/install_prompt.dart';
import 'web_bluetooth_js.dart';
import 'web_capabilities.dart';
import 'web_contacts_js.dart';
import 'web_device_js.dart';
import 'web_files_js.dart';
import 'web_interop.dart';
import 'web_kiosk_js.dart';
import 'web_media_js.dart';
import 'web_nfc_js.dart';
import 'web_permissions_js.dart';
import 'web_sensors_js.dart';

// Re-exported so the capability lists and DVWebPermissionDenied reach an
// application through the package barrel, on this branch and on the stub's.
// Without it an application could catch nothing more specific than Exception
// for a refusal, which is the distinction these files exist to make.
export 'web_capabilities.dart';

/// Registers the browser bindings.
class DVWebBindings {
  const DVWebBindings._();

  static bool _registered = false;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvWebImplementedBindings;

  /// What this browser actually bound.
  ///
  /// [implemented] is the web platform's capability list and does not change;
  /// this is the subset that survived the feature probes in [register], and
  /// it is what a caller deciding whether to offer a feature should read.
  /// Chrome on Android fills nearly all of it. Firefox on a desktop leaves
  /// out NFC, Bluetooth, contacts, the motion sensors and sharing.
  static Set<String> get registeredNames => Set<String>.unmodifiable(_names);

  static final Set<String> _names = <String>{};

  /// The URL this tab was opened at, captured before the router changes it.
  static String? _initialLink;

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

  /// Shows the browser prompt from a user gesture, and waits for the answer.
  ///
  /// Returns `accepted` or `dismissed`, which is what the browser calls them.
  /// Waiting is the whole point: prompt() only opens the dialog, and the
  /// choice arrives on userChoice afterwards. Returning without it reported
  /// an acceptance whatever the person at the screen chose.
  static Future<String> showInstallPrompt() async {
    final web.Event? event = _deferred;
    // Nothing was shown, so nobody accepted anything.
    if (event == null) return 'dismissed';
    _deferred = null;

    final JSObject deferred = event as JSObject;
    deferred.callMethod<JSAny?>('prompt'.toJS);

    final JSAny? choice = deferred.getProperty<JSAny?>('userChoice'.toJS);
    // A browser that fired beforeinstallprompt always has it; a polyfill or
    // an older engine might not, and guessing acceptance there would install
    // nothing and say it had.
    if (choice == null) return 'dismissed';

    final JSObject result = await (choice as JSPromise<JSObject>).toDart;
    final JSAny? outcome = result.getProperty<JSAny?>('outcome'.toJS);
    return outcome == null ? 'dismissed' : (outcome as JSString).toDart;
  }

  static bool register() {
    if (_registered) return true;

    // Named `register` so every binding name sits beside the word the
    // declaration scanner looks for. A helper called anything else hides the
    // literal from it, which is how four names the specification pins went
    // undeclared and unregistered with both directions of the check reading
    // clean.
    void register(String name, FutureOr<Object?> Function(Object?) handler) {
      DVNativeBridge.register(name, handler);
      _names.add(name);
    }

    _wireInstallPrompt();
    _initialLink = web.window.location.href;

    // The prompt itself. This binding existed and was called by nothing, so
    // DVInstallPrompt.show() flipped its own flags and never opened the
    // browser's dialog at all.
    register('install.prompt', (Object? _) => showInstallPrompt());

    final JSObject? clipboard = _clipboard();
    if (clipboard != null && dvJsMethod(clipboard, 'writeText') != null) {
      register('clipboard.copy', (Object? arguments) async {
        final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
        try {
          await web.window.navigator.clipboard.writeText(text).toDart;
          return true;
        } on Object catch (error) {
          dvJsRefused('clipboard.copy', error);
        }
      });
    }

    if (clipboard != null && dvJsMethod(clipboard, 'readText') != null) {
      register('clipboard.paste', (Object? _) async {
        // Reading needs a secure context and, in most browsers, a user
        // gesture. The rejection reaches the caller as a refusal: an empty
        // string here would be reported as a clipboard bug.
        try {
          final text = await web.window.navigator.clipboard.readText().toDart;
          return text.toDart;
        } on Object catch (error) {
          dvJsRefused('clipboard.paste', error);
        }
      });
    }

    register('screen.geometry', (Object? _) {
      final screen = web.window.screen;
      return <String, Object?>{
        'width': screen.width,
        'height': screen.height,
        'devicePixelRatio': web.window.devicePixelRatio,
      };
    });

    // A deep link on the web is the address bar. Null for a plain visit to
    // the root, because an application that navigates to whatever this
    // returns would otherwise repeat the route it is already on for every
    // ordinary load.
    register('deepLinks.initial', (Object? _) => initialLink);

    if (dvJsObject(globalContext, 'Notification') != null) {
      register('notifications.sendLocal', (Object? arguments) {
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        // Permission is the caller's to obtain. Requesting it here would pop
        // a browser prompt from whatever code path happened to send a
        // notification, which is exactly the pattern browsers added the
        // user-gesture requirement to discourage.
        if (web.Notification.permission != 'granted') {
          throw const DVWebPermissionDenied(
            'notifications.sendLocal',
            'notification permission has not been granted; ask for it with '
                'permissions.request from a user gesture first',
          );
        }
        web.Notification(
          '${map['title'] ?? ''}',
          web.NotificationOptions(body: '${map['body'] ?? ''}'),
        );
        return true;
      });
    }

    // Absent on desktop Firefox, so probed rather than assumed. Registering
    // it there gave a TypeError from inside the binding instead of the
    // "no share on this browser" an application could have acted on.
    final JSObject? navigator = dvNavigator;
    if (navigator != null && dvJsMethod(navigator, 'share') != null) {
      register('share.text', (Object? arguments) async {
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        try {
          await web.window.navigator
              .share(web.ShareData(
                title: '${map['title'] ?? ''}',
                text: '${map['text'] ?? ''}',
              ))
              .toDart;
          return true;
        } on Object catch (error) {
          dvJsRefused('share.text', error);
        }
      });
    }

    // navigator.vibrate is the only haptic primitive the web has, and Safari
    // has none at all. It takes a duration and knows nothing of impact
    // weight, so the three names differ only in how long they buzz rather
    // than pretending to a fidelity that is not there.
    if (navigator != null && dvJsMethod(navigator, 'vibrate') != null) {
      register('haptics.lightVibrate', (Object? _) => _vibrate(10));
      register('haptics.impact', (Object? arguments) {
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        final weight = '${map['style'] ?? 'medium'}';
        return _vibrate(switch (weight) {
          'light' => 10,
          'heavy' => 50,
          _ => 25,
        });
      });
      register('haptics.vibrate', (Object? arguments) {
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        final duration = map['duration'];
        return _vibrate(duration is int ? duration : 25);
      });
    }

    register('window.setTitle', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      web.document.title = '${map['title'] ?? ''}';
      return true;
    });

    // window.alert: not fashionable, and genuinely the browser's message
    // dialog. The kind -- info, warning, error -- has no equivalent and is
    // ignored rather than encoded into the text, which would put the word
    // "ERROR" in front of somebody's own sentence.
    register('dialogs.message', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String title = '${map['title'] ?? ''}';
      final String text = '${map['text'] ?? ''}';
      web.window.alert(title.isEmpty ? text : '$title\n\n$text');
      return true;
    });

    _registerFullscreen(register);

    // navigator.bluetooth.getAvailability(), where it exists. Answering
    // false is the honest result on a browser without Web Bluetooth; it is
    // not the same as the call being unimplemented, which is what the caller
    // used to get.
    register('bluetooth.isEnabled', (Object? _) async {
      final JSObject? bluetooth =
          navigator == null ? null : dvJsObject(navigator, 'bluetooth');
      if (bluetooth == null) return false;
      final JSFunction? available = dvJsMethod(bluetooth, 'getAvailability');
      if (available == null) return false;
      final JSAny? value = await dvJsAwait(available.callAsFunction(bluetooth));
      return value.dartify() == true;
    });

    // NDEFReader is Chrome on Android and nowhere else, so this is false on a
    // desktop browser -- which is the platform reporting itself rather than
    // Dartvel guessing.
    register('nfc.isAvailable', (Object? _) async => DVWebNfc.available);

    // PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().
    // A browser with no platform authenticator answers false; one without
    // WebAuthn at all answers false too, because both mean the same thing to
    // a caller deciding whether to offer the option.
    register(
      'biometrics.canAuthenticate',
      (Object? _) async => _platformAuthenticator(),
    );

    _registerWebAuthn(register, navigator);

    if (DVWebSensors.locationAvailable) {
      DVWebSensors.registerLocation(register);
    }
    DVWebSensors.registerMotion(register);

    if (DVWebPermissions.available) DVWebPermissions.register(register);
    if (DVWebFiles.available) DVWebFiles.register(register);
    if (DVWebMedia.cameraAvailable) DVWebMedia.registerCamera(register);
    if (DVWebContacts.available) DVWebContacts.register(register);
    if (DVWebNfc.available) DVWebNfc.register(register);
    DVWebMedia.registerPicker(register);
    DVWebBluetooth.register(register);
    DVWebDevice.register(register);
    DVWebKiosk.register(register);

    _registered = true;
    return true;
  }

  /// The URL this tab was opened at, or null for a plain visit to the root.
  static String? get initialLink {
    final String? href = _initialLink;
    if (href == null) return null;
    final Uri url = Uri.parse(href);
    final bool bare = (url.path.isEmpty || url.path == '/') &&
        url.query.isEmpty &&
        url.fragment.isEmpty;
    return bare ? null : href;
  }

  /// The Fullscreen API, which the kiosk path has always used and which
  /// nothing registered under its own names.
  ///
  /// `DV.Platform.display.enterFullscreen()` worked on web through a separate
  /// code path while `isRegistered('display.enterFullscreen')` said no, so
  /// anything asking before calling was told the browser could not do the one
  /// thing it certainly can.
  ///
  /// The options -- hideSystemUi, lockOrientation -- are ignored, as they are
  /// on Linux. A page has no system UI to hide beyond what fullscreen already
  /// covers, and the Screen Orientation lock is a different API with its own
  /// refusals; honouring half of it would claim more than was done.
  static void _registerFullscreen(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    final web.Element? root = web.document.documentElement;
    if (root == null) return;
    if (dvJsMethod(root as JSObject, 'requestFullscreen') == null) return;

    register('display.enterFullscreen', (Object? _) async {
      try {
        await root.requestFullscreen().toDart;
        return true;
      } on Object catch (error) {
        // Fullscreen needs a user gesture. That is a refusal by the browser
        // rather than a missing capability, and it is the single most common
        // reason this call does nothing.
        dvJsRefused('display.enterFullscreen', error);
      }
    });

    register('display.exitFullscreen', (Object? _) async {
      // Leaving a fullscreen nobody is in is success. Somebody pressing Esc
      // has already done what was asked.
      if (web.document.fullscreenElement == null) return true;
      await web.document.exitFullscreen().toDart;
      return true;
    });
  }

  /// WebAuthn with userVerification required: the browser's own platform
  /// biometric prompt.
  ///
  /// It resolves with an assertion or throws, and there is no third outcome
  /// -- no authenticator, or a person who declines, both reach the caller as
  /// a failure rather than as a quiet false.
  ///
  /// Like every platform's local biometric API this gates the interface and
  /// proves nothing to a server; a passkey sign-in verifies its assertion
  /// server-side and is a different flow.
  static void _registerWebAuthn(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
    JSObject? navigator,
  ) {
    final JSObject? credentials =
        navigator == null ? null : dvJsObject(navigator, 'credentials');
    if (credentials == null || dvJsMethod(credentials, 'get') == null) return;

    register('biometrics.authenticate', (Object? _) async {
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
      final JSObject? crypto = dvJsObject(globalContext, 'crypto');
      final JSFunction? fill =
          crypto == null ? null : dvJsMethod(crypto, 'getRandomValues');
      if (fill != null) {
        fill.callAsFunction(crypto, challenge.toJS);
      }

      final JSObject publicKey = JSObject()
        ..setProperty('challenge'.toJS, challenge.toJS)
        ..setProperty('userVerification'.toJS, 'required'.toJS)
        ..setProperty('timeout'.toJS, 60000.toJS);
      final JSObject options = JSObject()
        ..setProperty('publicKey'.toJS, publicKey);

      final JSAny? assertion;
      try {
        assertion = await dvJsCall(credentials, 'get', <JSAny?>[options]);
      } on Object catch (error) {
        dvJsRefused('biometrics.authenticate', error);
      }
      if (assertion == null) {
        throw StateError('No assertion was returned.');
      }
      return true;
    });
  }

  static JSObject? _clipboard() {
    final JSObject? navigator = dvNavigator;
    return navigator == null ? null : dvJsObject(navigator, 'clipboard');
  }

  static bool _vibrate(int milliseconds) =>
      web.window.navigator.vibrate(milliseconds.toJS);

  static void unregister() {
    unawaited(DVWebKiosk.release());
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _names.clear();
    _registered = false;
  }
}

/// Whether the browser has a user-verifying platform authenticator.
///
/// One definition for both `biometrics.canAuthenticate` and the gate in
/// `biometrics.authenticate`, so the answer a caller is given and the
/// behaviour it then gets cannot disagree.
Future<bool> _platformAuthenticator() async {
  final JSObject? credential = dvJsObject(globalContext, 'PublicKeyCredential');
  if (credential == null) return false;
  final JSFunction? probe =
      dvJsMethod(credential, 'isUserVerifyingPlatformAuthenticatorAvailable');
  if (probe == null) return false;
  final JSAny? value = await dvJsAwait(probe.callAsFunction(credential));
  return value.dartify() == true;
}
