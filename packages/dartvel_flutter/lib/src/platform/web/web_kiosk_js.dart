/// Kiosk enforcement in a browser: Fullscreen, Keyboard Lock and Pointer Lock.
///
/// Each needs a user gesture, and Keyboard Lock holds keys only while the
/// page is fullscreen. The browser reserves Esc and cannot be prevented from
/// leaving fullscreen, so `fullscreenOnly` is the honest label; a dedicated
/// kiosk mode -- a launch flag, a ChromeOS kiosk app -- shows as the
/// fullscreen display mode and is reported so the enforcement can be raised.
/// Every refusal comes back with the browser's reason rather than as a claim.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../accelerator.dart';

class DVWebKiosk {
  const DVWebKiosk._();

  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};

  static bool _held = false;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('kiosk.enforce', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      _held = true;

      String? fullscreenError;
      var fullscreen = false;
      if (map['fullscreen'] == true) {
        fullscreenError = await _requestFullscreen();
        fullscreen = fullscreenError == null && web.document.fullscreenElement != null;
      }

      final List<String> blocked = <String>[];
      final Map<String, String> unenforced = <String, String>{};
      final List<String> codes = <String>[];
      final Map<String, List<String>> codesOf = <String, List<String>>{};
      for (final Object? raw in (map['combos'] as List?) ?? const <Object?>[]) {
        final String text = '$raw';
        try {
          final DVAccelerator combo = DVAccelerator.parse(text);
          final List<String> own = keyCodesFor(combo);
          codesOf[text] = own;
          codes.addAll(own);
        } on FormatException catch (e) {
          unenforced[text] = e.message;
        }
      }
      final String? lockError = codes.isEmpty ? null : await _lockKeys(codes.toSet().toList());
      final bool inFullscreen = web.document.fullscreenElement != null;
      for (final MapEntry<String, List<String>> e in codesOf.entries) {
        if (lockError != null) {
          unenforced[e.key] = lockError;
        } else if (!inFullscreen) {
          unenforced[e.key] = 'Keyboard Lock holds keys only in fullscreen, which needs a user gesture';
        } else {
          blocked.add(e.key);
        }
      }

      String? pointerError;
      var confined = false;
      if (map['confinePointer'] == true) {
        pointerError = await _requestPointerLock();
        confined = pointerError == null;
      }

      return <String, Object?>{
        'blocked': blocked,
        'unenforced': unenforced,
        'fullscreen': fullscreen,
        if (fullscreenError != null) 'fullscreenError': fullscreenError,
        'confined': confined,
        if (pointerError != null) 'pointerError': pointerError,
        // The Notification API is the page's own; the system's are not the
        // page's to hold.
        'notificationsSuppressed': false,
        'browserKiosk': browserKioskDetected,
      };
    });
    bind('kiosk.release', (Object? _) async {
      await release();
      return true;
    });
  }

  /// A dedicated kiosk mode presents the page in the fullscreen display mode.
  static bool get browserKioskDetected =>
      web.window.matchMedia('(display-mode: fullscreen)').matches;

  /// `KeyboardEvent.code` values Keyboard Lock takes for [combo]: the key
  /// and the modifiers that make it a system shortcut.
  static List<String> keyCodesFor(DVAccelerator combo) {
    final List<String> out = <String>[];
    for (final DVModifierKey m in combo.modifiers) {
      out.addAll(switch (m) {
        DVModifierKey.control => const <String>['ControlLeft', 'ControlRight'],
        DVModifierKey.alt => const <String>['AltLeft', 'AltRight'],
        DVModifierKey.shift => const <String>['ShiftLeft', 'ShiftRight'],
        DVModifierKey.meta => const <String>['MetaLeft', 'MetaRight'],
      });
    }
    final String k = combo.key.toLowerCase();
    const Map<String, String> named = <String, String>{
      'tab': 'Tab',
      'escape': 'Escape',
      'esc': 'Escape',
      'space': 'Space',
      'enter': 'Enter',
      'return': 'Enter',
      'delete': 'Delete',
      'del': 'Delete',
      'up': 'ArrowUp',
      'down': 'ArrowDown',
      'left': 'ArrowLeft',
      'right': 'ArrowRight',
      'home': 'Home',
      'end': 'End',
      'pageup': 'PageUp',
      'pagedown': 'PageDown',
    };
    if (named.containsKey(k)) {
      out.add(named[k]!);
    } else if (k.length == 1 && RegExp('[a-z]').hasMatch(k)) {
      out.add('Key${k.toUpperCase()}');
    } else if (k.length == 1 && RegExp('[0-9]').hasMatch(k)) {
      out.add('Digit$k');
    } else if (RegExp(r'^f\d{1,2}$').hasMatch(k)) {
      out.add(k.toUpperCase());
    } else {
      out.add(k);
    }
    return out;
  }

  static Future<String?> _requestFullscreen() async {
    final web.Element? root = web.document.documentElement;
    if (root == null) return 'no document element';
    try {
      await root.requestFullscreen().toDart;
      return null;
    } catch (error) {
      return 'requestFullscreen refused: $error';
    }
  }

  static JSObject? get _keyboard {
    final JSObject navigator = web.window.navigator as JSObject;
    if (!navigator.has('keyboard')) return null;
    return navigator.getProperty<JSObject?>('keyboard'.toJS);
  }

  static Future<String?> _lockKeys(List<String> codes) async {
    final JSObject? keyboard = _keyboard;
    if (keyboard == null || !keyboard.has('lock')) {
      return 'Keyboard Lock API absent in this browser';
    }
    try {
      final JSAny? result = keyboard.callMethod<JSAny?>(
          'lock'.toJS, <JSString>[for (final String c in codes) c.toJS].toJS);
      if (result != null && result.isA<JSPromise>()) {
        await (result as JSPromise<JSAny?>).toDart;
      }
      return null;
    } catch (error) {
      return 'Keyboard Lock refused: $error';
    }
  }

  static Future<String?> _requestPointerLock() async {
    final web.Element? root = web.document.documentElement;
    if (root == null) return 'no document element';
    final Completer<String?> done = Completer<String?>();
    void onChange(web.Event _) {
      if (!done.isCompleted) done.complete(web.document.pointerLockElement == null ? 'pointer lock ended' : null);
    }
    void onError(web.Event _) {
      if (!done.isCompleted) done.complete('requestPointerLock refused: needs a user gesture');
    }
    final JSFunction change = onChange.toJS;
    final JSFunction error = onError.toJS;
    web.document.addEventListener('pointerlockchange', change);
    web.document.addEventListener('pointerlockerror', error);
    try {
      final JSAny? result = (root as JSObject).callMethod<JSAny?>('requestPointerLock'.toJS);
      if (result != null && result.isA<JSPromise>()) {
        await (result as JSPromise<JSAny?>).toDart;
        if (!done.isCompleted) done.complete(web.document.pointerLockElement == null ? 'pointer lock not granted' : null);
      }
      return await done.future.timeout(const Duration(milliseconds: 500),
          onTimeout: () => web.document.pointerLockElement == null ? 'pointer lock not granted' : null);
    } catch (e) {
      return 'requestPointerLock refused: $e';
    } finally {
      web.document.removeEventListener('pointerlockchange', change);
      web.document.removeEventListener('pointerlockerror', error);
    }
  }

  /// Unlocks the keyboard, releases the pointer and leaves fullscreen.
  static Future<void> release() async {
    if (!_held) return;
    _held = false;
    final JSObject? keyboard = _keyboard;
    if (keyboard != null && keyboard.has('unlock')) {
      keyboard.callMethod<JSAny?>('unlock'.toJS);
    }
    if (web.document.pointerLockElement != null) web.document.exitPointerLock();
    if (web.document.fullscreenElement != null) {
      try {
        await web.document.exitFullscreen().toDart;
      } catch (_) {
        // Leaving fullscreen the user already left is not a failure.
      }
    }
  }
}
