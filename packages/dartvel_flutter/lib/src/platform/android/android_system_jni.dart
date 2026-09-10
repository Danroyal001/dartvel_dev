/// Sensors, biometric availability and local notifications on Android.
///
/// All three are `Context.getSystemService`, which is the shape the
/// application Context can reach — no Activity, no platform channel. They sit
/// in their own file rather than in `android_bindings_jni.dart` because that
/// file is where every Android binding is registered and three groups being
/// added to it at once is three sets of conflicts.
///
/// The sensor half is worth reading before it is used. `SensorManager` has no
/// call that answers "what is the accelerometer reading now" and never has:
/// a reading arrives by registering a listener and waiting for the hardware
/// to report. The declared binding name is singular, so what is bound here
/// takes one sample — register, wait for the first event, unregister — rather
/// than holding a subscription open. That is a real reading each time it is
/// called and not a cached one, which is the failure this shape most invites.
/// What it cannot be is a stream, and `DVSensors.accelerometer` types itself
/// as one while yielding exactly once; that mismatch is in the declared
/// surface, not in this file, and it is recorded rather than papered over.
library dartvel_flutter.platform.android.system;

import 'dart:async';

import 'package:jni/jni.dart';

import 'android_capabilities.dart';
import 'generated/android/app/Notification.dart';
import 'generated/android/app/NotificationChannel.dart';
import 'generated/android/app/NotificationManager.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/res/Resources.dart';
import 'generated/android/hardware/Sensor.dart';
import 'generated/android/hardware/SensorEvent.dart';
import 'generated/android/hardware/SensorEventListener.dart';
import 'generated/android/hardware/SensorManager.dart';
import 'generated/android/hardware/biometrics/BiometricManager.dart';
import 'generated/android/os/Build.dart';
import 'generated/java/lang/CharSequence.dart';

/// How long a sample waits for the hardware before giving up.
///
/// A sensor that is present but reports nothing would otherwise leave the
/// caller's future pending for the life of the process, which reads as an
/// application that has hung rather than as a sensor that is quiet.
const Duration dvAndroidSensorTimeout = Duration(seconds: 2);

/// One reading each from the accelerometer and the gyroscope.
class DVAndroidSensors {
  const DVAndroidSensors._();

  /// The next event from the sensor of [type], as `{x, y, z}`.
  ///
  /// Throws when the device has no such sensor, and when none arrives inside
  /// [dvAndroidSensorTimeout]. Both are thrown rather than returned as null
  /// because null from a binding is what an unregistered name returns, and a
  /// caller cannot tell "this phone has no gyroscope" from "nothing is bound
  /// here" once the two look the same.
  static Future<Map<String, double>> sample(
    Context context,
    int type,
    String name,
  ) async {
    final JObject? service = context.getSystemService('sensor'.toJString());
    if (service == null) {
      throw StateError('Android reported no SensorManager, so $name cannot '
          'be read on this device.');
    }
    final SensorManager manager = service.as(SensorManager.type);
    final Sensor? sensor = manager.getDefaultSensor(type);
    if (sensor == null) {
      throw StateError('This device has no $name.');
    }

    final Completer<Map<String, double>> completer =
        Completer<Map<String, double>>();

    // onSensorChanged$async, deliberately. Without it the Android thread
    // delivering the event blocks until the Dart callback returns, and the
    // thread delivering sensor events is the main thread -- so a busy isolate
    // would stall the interface of the application asking for a reading.
    final SensorEventListener listener = SensorEventListener.implement(
      $SensorEventListener(
        onSensorChanged: (SensorEvent? event) {
          if (completer.isCompleted) return;
          final JFloatArray? values = event?.values;
          if (values == null) return;
          final List<double> axes = <double>[
            for (int i = 0; i < values.length && i < 3; i++) values[i],
          ];
          final Map<String, double>? reading = dvAndroidSensorSample(axes);
          // A truncated event is skipped, not completed with. The next one
          // may well be whole, and the timeout is what ends the wait if not.
          if (reading != null) completer.complete(reading);
        },
        onSensorChanged$async: true,
        onAccuracyChanged: (Sensor? sensor, int accuracy) {},
        onAccuracyChanged$async: true,
      ),
    );

    // registerListener$2 is the (SensorEventListener, Sensor, int) overload.
    // The suffix counts positions across Java's six registerListener
    // signatures -- the first two take the deprecated SensorListener -- so
    // the number is not guessable and picking the wrong one binds a
    // listener that is never called.
    manager.registerListener$2(
      listener,
      sensor,
      SensorManager.SENSOR_DELAY_FASTEST,
    );
    try {
      return await completer.future.timeout(
        dvAndroidSensorTimeout,
        onTimeout: () => throw StateError(
          'The $name reported nothing within '
          '${dvAndroidSensorTimeout.inMilliseconds}ms.',
        ),
      );
    } finally {
      // Always. A listener left registered keeps the sensor powered, which
      // on a phone is a battery drain nobody can attribute to anything.
      manager.unregisterListener$3(listener);
      // And the proxy itself, which is a global JNI reference and an open
      // receive port on the Dart side. One sample leaks nothing anybody
      // notices; a page reading the accelerometer while it is open leaks one
      // of each per reading.
      listener.release();
    }
  }
}

/// Whether this device can take a biometric answer at all.
class DVAndroidBiometrics {
  const DVAndroidBiometrics._();

  /// `BiometricManager.canAuthenticate()`, reduced to yes or no.
  ///
  /// False on API 28 and below, where the service does not exist. That is an
  /// understatement on a device with a fingerprint reader and the older
  /// `FingerprintManager` — but the prompt is not bound either, so saying yes
  /// would promise something no other binding here can deliver.
  static bool canAuthenticate(Context context) {
    final JObject? service = context.getSystemService('biometric'.toJString());
    if (service == null) return false;
    final int status = service.as(BiometricManager.type).canAuthenticate();
    return dvAndroidBiometricAvailable(status);
  }
}

/// Local notifications through `NotificationManager`.
class DVAndroidNotifications {
  const DVAndroidNotifications._();

  static int _counter = 0;

  /// For tests: forgets how many have been posted.
  static void resetForTest() => _counter = 0;

  /// Posts [title] and [body], answering whether it was actually posted.
  ///
  /// False, not an exception, for the two cases a device produces routinely:
  /// notifications switched off for the application, and no icon to draw.
  /// Both would otherwise be a call that returns successfully and shows
  /// nothing, which is the shape of failure this whole file exists to avoid.
  static bool send(Context context, String title, String body) {
    final JObject? service =
        context.getSystemService('notification'.toJString());
    if (service == null) return false;
    final NotificationManager manager = service.as(NotificationManager.type);

    // Since API 33 this is a permission the user grants, and a notification
    // posted without it is dropped by the system silently. Asking first turns
    // that into an answer the caller gets.
    if (!manager.areNotificationsEnabled()) return false;

    if (dvAndroidNotificationNeedsChannel(Build$VERSION.SDK_INT)) {
      // Creating a channel that exists is a no-op, so this runs on every
      // send rather than being tracked -- one boolean fewer to get wrong
      // across a process restart.
      manager.createNotificationChannel(
        NotificationChannel(
          dvAndroidNotificationChannelId.toJString(),
          dvAndroidNotificationChannelName.toJString().as(CharSequence.type),
          NotificationManager.IMPORTANCE_DEFAULT,
        ),
      );
    }

    final int icon = smallIcon(context);
    // A notification built with icon 0 throws from notify(), on the device,
    // out of a call whose arguments all looked fine.
    if (icon == 0) return false;

    final Notification$Builder builder = Notification$Builder(
      context,
      dvAndroidNotificationChannelId.toJString(),
    );
    builder.setContentTitle(title.toJString().as(CharSequence.type));
    builder.setContentText(body.toJString().as(CharSequence.type));
    builder.setSmallIcon(icon);
    builder.setAutoCancel(true);

    final Notification? notification = builder.build();
    if (notification == null) return false;

    manager.notify(dvAndroidNotificationId(_counter++), notification);
    return true;
  }

  /// The drawable a notification is drawn with, or 0 when there is none.
  ///
  /// The application's own launcher icon first, because that is what a person
  /// recognises in the shade; a platform drawable after it, because an
  /// application whose icon lives under a name this does not know would
  /// otherwise be unable to notify at all. Resolved by name through
  /// `Resources.getIdentifier` rather than by a constant: a resource id is
  /// assigned at build time and a number written here would point at
  /// something else, or nothing, in every application but the one it was read
  /// from.
  static int smallIcon(Context context) {
    final Resources? resources = context.resources;
    final JString? package = context.packageName;
    if (resources == null || package == null) return 0;
    for (final (String name, String kind, String from) in <(
      String,
      String,
      String
    )>[
      ('ic_launcher', 'mipmap', package.toDartString()),
      ('ic_launcher', 'drawable', package.toDartString()),
      ('ic_notification', 'drawable', package.toDartString()),
      ('ic_dialog_info', 'drawable', 'android'),
    ]) {
      final int id = resources.getIdentifier(
        name.toJString(),
        kind.toJString(),
        from.toJString(),
      );
      if (id != 0) return id;
    }
    return 0;
  }
}
