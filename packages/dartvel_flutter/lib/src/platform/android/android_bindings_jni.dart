/// Android implementations of the `DV.Platform` bindings.
///
/// JNI through `package:jni` and jnigen-generated bindings, per the native
/// integration rule — never a platform channel.
///
/// The piece everything rests on is the application `Context`: everything
/// worth binding is reached through `Context.getSystemService`, and Dart has
/// no Activity to ask.
///
/// This file used to say that `package:jni` exports `GetApplicationContext()`
/// from its C header, "which is a deliberate C API and reachable with plain
/// dart:ffi". The declaration is in `dartjni.h`; there is no definition
/// behind it in `dartjni.c`. Every Android binding was therefore dead in
/// every real application — clipboard, haptics, sharing, the kiosk — while
/// the capability list claimed them, and it took running the application on
/// an emulator to find out: "undefined symbol: GetApplicationContext".
///
/// The route now is a ContentProvider that `dartvel build android` writes
/// into the application. Android creates every declared provider before
/// `Application.onCreate` returns and hands it a Context, which is earlier
/// than any Activity and earlier than the Flutter engine. It is what
/// androidx.startup is built on.
///
/// The other route, `ActivityThread.currentApplication()`, is the trick
/// libraries normally use and is not available here: the class is hidden and
/// absent from the public `android.jar`, so jnigen reported it "Not found"
/// while finding every other class.
library dartvel_flutter.platform.android.jni;

import 'dart:io' show Platform;

import 'package:jni/jni.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'android_capabilities.dart';
import 'android_kiosk_jni.dart';
import 'generated/android/app/Activity.dart';
import 'generated/android/app/Application.dart';
import 'generated/android/content/ClipData.dart';
import 'generated/android/content/ClipboardManager.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/Intent.dart';
import 'generated/android/os/VibrationEffect.dart';
import 'generated/android/os/Vibrator.dart';
import 'generated/java/lang/CharSequence.dart';

/// The class that holds the application Context, written by
/// `dartvel build android`.
///
/// JNI's slash-separated form, and the same string the CLI writes -- a
/// constant in both places rather than one, because the Flutter package
/// cannot depend on the CLI. A test in the CLI asserts they agree.
const String _contextHolder = 'dev/dartvel/jni/DartvelContext';

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

    // The Activity, which is what lock task mode belongs to and what the
    // application Context cannot reach. Android reports it and never answers
    // the question afterwards, so the watching starts here, before anything
    // asks.
    // The application Context *is* the Application on Android; the cast is
    // what tells Dart so. `as` checks it, so a Context that somehow is not
    // one throws here rather than at the first callback.
    DVAndroidActivities.watch(context.as(Application.type));
    DVAndroidKiosk.register(DVNativeBridge.register);

    // What the application was opened with. The launch Intent belongs to the
    // Activity, so this was unanswerable until the Activity was -- and a
    // home widget's tap is a deep link, so without it a widget opened the
    // application's home route: a shortcut, not a widget.
    DVNativeBridge.register('deepLinks.initial', (Object? _) {
      final Activity? activity = DVAndroidActivities.current;
      if (activity == null) return null;
      final Intent? intent = activity.intent;
      if (intent == null) return null;
      final JString? data = intent.dataString;
      return dvAndroidLaunchRoute(data?.toDartString(releaseOriginal: true));
    });

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

    DVNativeBridge.register('share.text', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final text = '${map['text'] ?? ''}';
      if (text.isEmpty) return false;
      return _shareText(text, '${map['title'] ?? 'Share'}');
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
  /// Why [register] last returned false, or null when it has not.
  ///
  /// Registration failing was one line in the log saying it had, which is not
  /// debugging. The ways it can fail need different fixes, so they say
  /// different things.
  static String? lastFailure;

  static Context? _applicationContext() {
    // Through the provider `dartvel build android` writes, not through
    // package:jni's GetApplicationContext. That symbol is declared in
    // dartjni.h and never defined -- an emulator run said so in the end,
    // "undefined symbol: GetApplicationContext" -- so every Android binding
    // was dead in every real application while the capability list claimed
    // them. Reading a header without checking there was a body behind it is
    // the whole mistake.
    //
    // Android creates every declared ContentProvider before
    // Application.onCreate returns and hands it a Context, which is earlier
    // than any Activity and earlier than the engine. No hidden API and no
    // ActivityThread, which is absent from the public android.jar and is why
    // jnigen could not bind it in the first place.
    final JClass holder;
    try {
      holder = JClass.forName(_contextHolder);
    } on Object catch (error) {
      lastFailure = 'the class $_contextHolder is not in this application '
          '($error). It is written by `dartvel build android`; an APK built '
          'with plain `flutter build` does not have it, and the platform '
          'bindings have no Context without it.';
      return null;
    }

    try {
      final JStaticMethodId method =
          holder.staticMethodId('context', '()Landroid/content/Context;');
      // callNullable, because the honest answer before Android has created
      // the provider is null, and treating that as a failure to link would
      // send whoever reads the log looking in the wrong place.
      final Context? held =
          method.callNullable(holder, Context.type, const <dynamic>[]);
      if (held == null) {
        lastFailure = 'the Context provider has not been created yet. '
            'Registration ran before Android brought the application up.';
        return null;
      }
      lastFailure = null;
      return held;
    } on Object catch (error) {
      lastFailure = '$_contextHolder is present but did not answer with a '
          'Context ($error).';
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

  /// Hand text to whatever the user picks to receive it.
  ///
  /// Three details decide whether this works, and each of them fails only on
  /// a device:
  ///
  ///   * The flags. Starting an activity from the application `Context`
  ///     rather than from an `Activity` throws without
  ///     `FLAG_ACTIVITY_NEW_TASK`.
  ///   * The chooser. A bare `ACTION_SEND` goes to whatever the user last
  ///     picked, or nowhere at all when no default is set. `createChooser`
  ///     always resolves, and the flags go on the chooser rather than on the
  ///     inner intent — it is the one being started.
  ///   * The type. Intent resolution matches on the action and the MIME type
  ///     together, so an untyped intent is delivered to nothing.
  static bool _shareText(String text, String title) {
    final context = _context;
    if (context == null) return false;

    final send = Intent.new$2(Intent.ACTION_SEND);
    send.setType(dvAndroidShareMimeType.toJString());
    // putExtra is overloaded five ways over primitives before it reaches
    // (String, String); the suffix counts positions in the Java class, not
    // anything about the types.
    send.putExtra$8(Intent.EXTRA_TEXT, text.toJString());

    // createChooser takes a CharSequence, and the cast has to name that type
    // rather than JObject or the generic does not line up.
    final chooser = Intent.createChooser(
      send,
      title.toJString().as(CharSequence.type),
    );
    if (chooser == null) return false;
    chooser.addFlags(dvAndroidShareIntentFlags);

    context.startActivity(chooser);
    return true;
  }
}
