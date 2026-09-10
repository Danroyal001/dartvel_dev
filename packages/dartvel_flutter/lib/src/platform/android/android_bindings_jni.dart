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

import 'package:dartvel_core/dartvel.dart' show dvHomeWidgetAndroidClass;
import 'package:jni/jni.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import '../device_runtime.dart';
import '../file_bindings.dart';
import 'android_capabilities.dart';
import 'android_device.dart';
import 'android_kiosk_jni.dart';
import 'android_system_jni.dart';
import 'generated/android/app/Activity.dart';
import 'generated/android/app/Application.dart';
import 'generated/android/content/ClipData.dart';
import 'generated/android/content/ClipboardManager.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/Intent.dart';
import 'generated/android/hardware/Sensor.dart';
import 'generated/android/os/VibrationEffect.dart';
import 'generated/android/os/Vibrator.dart';
// For getFilesDir()'s absolutePath. jnigen puts an extension type's methods
// in a plain `extension ... on File`, and a Dart extension is only in scope
// where its library is imported -- so without this line the getter is
// "not defined for the type File" even though the type is right there.
import 'generated/java/io/File.dart';
import 'generated/java/lang/CharSequence.dart';

/// The class that holds the application Context, written by
/// `dartvel build android`.
///
/// JNI's slash-separated form, and the same string the CLI writes -- a
/// constant in both places rather than one, because the Flutter package
/// cannot depend on the CLI. A test in the CLI asserts they agree.
const String _contextHolder = 'dev/dartvel/jni/DartvelContext';

/// The class a home widget's data is published through, in the same form and
/// for the same reason.
///
/// From core, because the CLI writes the class and this calls it and they
/// are in packages that cannot import each other. Two spellings would be a
/// publish that answers false on a device with a perfectly good widget on
/// its home screen.
const String _widgetPublisher = dvHomeWidgetAndroidClass;

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

    // What a home-screen widget shows. Nothing about the Flutter tree
    // crosses -- the launcher composes the widget in its own process, which
    // cannot host an engine -- so this is the value the generated provider
    // reads back out of the shared store before it draws.
    DVNativeBridge.register('homeWidgets.publish', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final key = '${map['key'] ?? ''}';
      if (key.isEmpty) return false;
      return _publishWidget(key, '${map['text'] ?? ''}');
    });

    DVNativeBridge.register('share.text', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final text = '${map['text'] ?? ''}';
      if (text.isEmpty) return false;
      return _shareText(text, '${map['title'] ?? 'Share'}');
    });

    // One sample each, not a subscription. SensorManager has no call that
    // answers what the accelerometer reads right now; a reading arrives by
    // registering a listener and waiting, and these register one, take the
    // first event and let go again. See android_system_jni.dart for why the
    // singular binding name and DVSensors's Stream do not line up.
    DVNativeBridge.register(
      'sensors.accelerometer',
      (Object? _) => DVAndroidSensors.sample(
        context,
        Sensor.TYPE_ACCELEROMETER,
        'accelerometer',
      ),
    );
    DVNativeBridge.register(
      'sensors.gyroscope',
      (Object? _) => DVAndroidSensors.sample(
        context,
        Sensor.TYPE_GYROSCOPE,
        'gyroscope',
      ),
    );

    // BiometricManager is a system service like the clipboard, which is what
    // this file was previously recorded as unable to reach. The prompt is
    // the part that is genuinely blocked: its result arrives at an abstract
    // callback class, and jnigen implements interfaces.
    DVNativeBridge.register(
      'biometrics.canAuthenticate',
      (Object? _) => DVAndroidBiometrics.canAuthenticate(context),
    );

    DVNativeBridge.register('notifications.sendLocal', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      return DVAndroidNotifications.send(
        context,
        '${map['title'] ?? ''}',
        '${map['body'] ?? ''}',
      );
    });

    _registerDeviceAndFiles(context);

    _registered = true;
    return true;
  }

  /// The device runtime and the file bindings, both rooted in the one
  /// directory an Android application owns.
  ///
  /// Neither is JNI beyond asking for that directory. What makes them
  /// Android-specific is where they are allowed to write: the shared device
  /// runtime falls back to `$HOME` and then to `Directory.systemTemp`, and
  /// Android sets no HOME and gives no application /tmp. Left alone it would
  /// try to create `/tmp/.dartvel/device` and `device.health` would throw on
  /// its first call — on the phone, never in a test.
  ///
  /// Failing to find the directory leaves both unregistered rather than
  /// registered against a guess. `DV.Platform` then reports them unavailable,
  /// which is true, instead of writing somewhere nobody can read back.
  static void _registerDeviceAndFiles(Context context) {
    final String? files = context.filesDir?.absolutePath
        ?.toDartString(releaseOriginal: true);
    final String? state = dvAndroidStateDirectory(files);
    final String? root = dvAndroidFilesRoot(files);
    if (state == null || root == null) {
      lastFailure = 'the application has no files directory, so the device '
          'runtime and the file bindings have nowhere they are allowed to '
          'write and were left unregistered.';
      return;
    }

    DVDeviceRuntime.probes = DVAndroidDeviceProbes(context);
    DVDeviceRuntime.stateDirectory = state;
    DVDeviceRuntime.register(DVNativeBridge.register);

    // Confined to a directory of its own inside the private one, not to the
    // filesystem root and not to the private directory either. An Android
    // application can reach a good deal of shared storage, and a binding
    // that writes wherever it is told is a file-write primitive handed to
    // whatever can call it -- while the private directory as a whole would
    // put the device id and the provisioning record inside the confinement.
    DVFileBindings.register(root, DVNativeBridge.register);
  }

  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    // The two that hold state of their own. Dropping the handler without
    // these would leave a watchdog timer running against a process that has
    // let go of its bindings, and a file root that the next register() would
    // decline to replace.
    DVDeviceRuntime.unregister();
    DVFileBindings.reset();
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

  /// Leaves [text] under [key] where the generated widget provider reads it,
  /// and asks the launcher to redraw what is already on a home screen.
  ///
  /// Through the class `dartvel build android` writes, rather than through
  /// SharedPreferences from here: the jnigen bindings have `SharedPreferences`
  /// as a stub, and the redraw needs the provider class names, which Java
  /// knows at build time and Dart cannot know at all -- the application's
  /// package is an applicationId this package is compiled without.
  ///
  /// The class is written only for a project that declares a home widget, so
  /// the lookup failing is the honest answer "this application has none".
  /// Every failure here is silent on the device -- an APK built with plain
  /// `flutter build` has none of the generated classes -- which is why each
  /// one answers false rather than being allowed to look like a write.
  static bool _publishWidget(String key, String text) {
    final JClass holder;
    try {
      holder = JClass.forName(_widgetPublisher);
    } on Object {
      return false;
    }

    try {
      final JStaticMethodId method = holder.staticMethodId(
        'publish',
        '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
      );
      // A String rather than a boolean, so the answer carries which key was
      // written: a publish that stored something under a key nobody reads
      // and a publish that stored nothing look the same from a bool.
      final JString? written = method.callNullable(
        holder,
        JString.type,
        <dynamic>[key.toJString(), text.toJString()],
      );
      if (written == null) return false;
      return written.toDartString(releaseOriginal: true) == key;
    } on Object {
      return false;
    }
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
