/// Android implementations of the `DV.Platform` bindings.
///
/// JNI through `package:jni` and jnigen-generated bindings, per the native
/// integration rule — never a platform channel.
///
/// The piece that made this possible is the application `Context`. Everything
/// worth binding is reached through `Context.getSystemService`, and Dart has no
/// Activity to ask. `package:jni` exports `GetApplicationContext()` from its C
/// header — "Returns application context on Android" — which is a deliberate C
/// API and reachable with plain `dart:ffi`.
///
/// It is worth recording what that replaced. The intended route was
/// `ActivityThread.currentApplication()`, the trick libraries normally use.
/// Generation proved it impossible: the class is hidden and absent from the
/// public `android.jar`, so jnigen reported it "Not found" while finding every
/// other class. The C export is not a workaround for that — it is a better
/// answer, being neither a hidden Android API nor a Dart internal.
library dartvel_flutter.platform.android.jni;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:jni/jni.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'android_capabilities.dart';
import 'generated/android/content/ClipData.dart';
import 'generated/android/content/ClipboardManager.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/os/VibrationEffect.dart';
import 'generated/android/os/Vibrator.dart';
import 'generated/java/lang/CharSequence.dart';

/// `GetApplicationContext` as declared in package:jni's `dartjni.h`.
typedef _GetApplicationContextNative = Pointer<Void> Function();
typedef _GetApplicationContextDart = Pointer<Void> Function();

/// Registers the Android bindings that are genuinely implemented.
class DVAndroidBindings {
  const DVAndroidBindings._();

  static bool _registered = false;
  static Context? _context;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvAndroidImplementedBindings;

  static bool register() {
    if (_registered) return true;
    if (!Platform.isAndroid) return false;

    final context = _applicationContext();
    if (context == null) return false;
    _context = context;

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());

    DVNativeBridge.register('haptics.lightVibrate', (Object? _) => _vibrate(10));
    DVNativeBridge.register('haptics.impact', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _vibrate(switch ('${map['style'] ?? 'medium'}') {
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

    _registered = true;
    return true;
  }

  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _context = null;
    _registered = false;
  }

  /// The application `Context`, or null when it cannot be obtained.
  ///
  /// Null rather than throwing: [register] is called unconditionally at
  /// startup, and an application that cannot reach a Context should keep
  /// running with the bindings unregistered rather than fail to start.
  static Context? _applicationContext() {
    try {
      final lookup = DynamicLibrary.process().lookupFunction<
          _GetApplicationContextNative, _GetApplicationContextDart>(
        'GetApplicationContext',
      );
      final pointer = lookup();
      if (pointer == nullptr) return null;
      return JObject.fromReference(JGlobalReference(pointer)).as(Context.type);
    } on ArgumentError {
      // The symbol is absent, which means package:jni's native library is not
      // linked into this build.
      return null;
    }
  }

  /// A system service, or null when the platform does not offer it.
  static JObject? _service(String name) {
    final context = _context;
    if (context == null) return null;
    final service = context.getSystemService(name.toJString());
    return service;
  }

  static bool _copy(String text) {
    final service = _service('clipboard');
    if (service == null) return false;
    final manager = service.as(ClipboardManager.type);

    // The label is what Android shows in the clipboard UI on newer versions.
    // newPlainText takes CharSequence, and JString is one — but the cast has
    // to name that type, not JObject, or the generic does not line up.
    final clip = ClipData.newPlainText(
      'dartvel'.toJString().as(CharSequence.type),
      text.toJString().as(CharSequence.type),
    );
    if (clip == null) return false;
    manager.primaryClip = clip;
    return true;
  }

  static String? _paste() {
    final service = _service('clipboard');
    if (service == null) return null;
    final manager = service.as(ClipboardManager.type);

    final clip = manager.primaryClip;
    // Nothing on the clipboard. Null rather than an empty string, so a caller
    // can tell "nothing there" from "an empty string".
    if (clip == null) return null;
    if (clip.itemCount == 0) return null;

    final item = clip.getItemAt(0);
    if (item == null) return null;
    final text = item.coerceToText(_context);
    return text?.toString();
  }

  /// Vibrates for [milliseconds].
  ///
  /// `vibrator_manager` is the API 31 way in and `vibrator` remains for older
  /// releases. Both are tried rather than branching on the SDK level, because
  /// reading the level is another JNI call and the fallback answers the same
  /// question.
  static bool _vibrate(int milliseconds) {
    final service = _service('vibrator_manager') ?? _service('vibrator');
    if (service == null) return false;

    final effect = VibrationEffect.createOneShot(
      milliseconds,
      VibrationEffect.DEFAULT_AMPLITUDE,
    );
    if (effect == null) return false;

    // vibrate$4 is the VibrationEffect overload. The generated names are
    // positional across Java's five vibrate() signatures, so the number
    // matters and is not guessable.
    service.as(Vibrator.type).vibrate$4(effect);
    return true;
  }
}
