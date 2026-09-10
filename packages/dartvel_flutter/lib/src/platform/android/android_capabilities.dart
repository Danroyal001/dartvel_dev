/// The names the Android bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.android.capabilities;

/// What Android is bound for, and nothing more.
///
/// Reached through JNI and jnigen-generated bindings, per the native
/// integration rule — never a platform channel. Everything here goes through
/// `Context.getSystemService`, and the Context comes from the ContentProvider
/// `dartvel build android` writes; the C export this file used to name is
/// declared in `dartjni.h` with nothing behind it.
///
/// Absent, with reasons rather than "not yet":
///
///   * **`biometrics.authenticate`** is blocked on something specific rather
///     than on an Activity. `BiometricPrompt.authenticate` takes an
///     `AuthenticationCallback`, and that is an abstract *class*. jnigen
///     implements interfaces and cannot subclass, so the result of the prompt
///     has nowhere to arrive. The fix is a small Java shim beside the Context
///     provider, written by the build the same way, and it is not written yet.
///     `biometrics.canAuthenticate` needs no callback and is bound.
///   * **NFC** dispatch is delivered to an `Activity`.
///   * **Window controls** do not apply — an Android app owns no resizable
///     window.
///   * **`screen.geometry`** would come from `WindowManager`, whose modern API
///     returns metrics through classes that vary by API level. Flutter already
///     reports the same numbers, so a binding would add a second answer that
///     can disagree with the first.
///
/// Notifications were on that list, and the reason given was wrong: a channel
/// is created through `NotificationManager`, which is a system service on the
/// application Context like every other. The API 33 permission is real, and
/// the binding answers false when notifications are switched off rather than
/// posting into a system that drops it — see [dvAndroidNotificationNeedsChannel].
const Set<String> dvAndroidImplementedBindings = <String>{
  // ClipboardManager through Context.getSystemService.
  'clipboard.copy',
  'clipboard.paste',

  // Vibrator, or VibratorManager from API 31.
  'haptics.vibrate',
  'haptics.lightVibrate',
  'haptics.impact',

  // Intent.ACTION_SEND through a chooser.
  'share.text',

  // Lock task mode, held on the running Activity. Reached through
  // Application.registerActivityLifecycleCallbacks, because the application
  // Context that package:jni hands back is not an Activity and lock task is
  // an Activity's.
  'kiosk.enforce',
  'kiosk.release',

  // The launch Intent's URI, which is the Activity's and so arrived with it.
  'deepLinks.initial',

  // What a home-screen widget shows. The AppWidgetProvider is a receiver in
  // this application's own process -- only the RemoteViews it returns are
  // handed to the launcher -- so both ends reach the same SharedPreferences,
  // and the write goes through the class `dartvel build android` writes
  // beside the Context holder.
  'homeWidgets.publish',

  // One sample from SensorManager, taken by registering a listener and
  // letting it go again as soon as the first event lands. The binding name
  // is singular and so is the reading: see [dvAndroidSensorSample].
  'sensors.accelerometer',
  'sensors.gyroscope',

  // BiometricManager.canAuthenticate, which is a plain system service and
  // needs no prompt. The prompt itself is the part that is still absent.
  'biometrics.canAuthenticate',

  // NotificationManager, with the channel API 26 and later require.
  'notifications.sendLocal',

  // The device runtime, which is procfs and one Android class for the disk.
  // Six names rather than two: the watchdog, provisioning and the
  // diagnostics bundle are the same plain Dart on every platform, and
  // registering four of the six would leave DV.Platform.device half working
  // in a way nothing reports.
  'device.capabilityManifest',
  'device.health',
  'device.watchdog.arm',
  'device.watchdog.heartbeat',
  'device.fleet.provision',
  'device.diagnostics.collect',

  // Files, confined to the private directory the application owns. Shared
  // Dart, not JNI -- Android has a filesystem like any other target -- but
  // nothing had ever registered it, on any platform.
  'files.readBytes',
  'files.writeBytes',
  'files.delete',
};

/// One sample from a motion sensor, or null when the event does not carry
/// three axes.
///
/// Null rather than a padded map, because a padded map is the most plausible
/// wrong answer this binding can give: a phone lying still on a table reads
/// near zero on two axes, so `{x: 0, y: 0, z: 0}` from a truncated event is
/// indistinguishable from a real reading and nothing downstream can catch it.
///
/// Values past the third are dropped. An uncalibrated gyroscope reports six —
/// three rates, then three drift estimates — and drift is not an axis.
Map<String, double>? dvAndroidSensorSample(List<double> values) {
  if (values.length < 3) return null;
  return <String, double>{'x': values[0], 'y': values[1], 'z': values[2]};
}

/// `BiometricManager.BIOMETRIC_SUCCESS`.
const int dvAndroidBiometricSuccess = 0;

/// Whether [status] from `BiometricManager.canAuthenticate` means yes.
///
/// Only success does. The status that has to answer false and looks like it
/// should answer true is `BIOMETRIC_ERROR_NONE_ENROLLED` (11): the sensor is
/// there, so anything asking whether there is hardware says yes, and then
/// every prompt on that device fails because nobody has enrolled a finger.
bool dvAndroidBiometricAvailable(int status) =>
    status == dvAndroidBiometricSuccess;

/// The channel every Dartvel local notification is posted on.
const String dvAndroidNotificationChannelId = 'dartvel.local';

/// What the channel is called in the system settings, where the user sees it.
const String dvAndroidNotificationChannelName = 'Notifications';

/// Whether this API level needs a notification channel.
///
/// Oreo, API 26. A notification posted with no channel from 26 onwards is
/// dropped by the system with a log line and no exception, which is the
/// silent half of this; below 26 the method to create one is not there.
bool dvAndroidNotificationNeedsChannel(int sdkInt) => sdkInt >= 26;

/// A notification id from a running [counter].
///
/// `NotificationManager.notify` takes a Java int. A counter left to grow
/// arrives negative or does not arrive at all, and the only symptom is a
/// notification that never appears — so it is masked into the positive range
/// here rather than trusted to stay small.
int dvAndroidNotificationId(int counter) => counter & 0x7fffffff;

/// Where the device runtime keeps its id, provisioning record and restarts,
/// given the application's own files directory. Null when there is none.
///
/// The shared runtime falls back to `$HOME` and then to
/// `Directory.systemTemp`. Android has neither: HOME is unset and /tmp
/// belongs to no application, so `device.health` would throw on its first
/// call — on the phone, and nowhere it was tested. Null for an empty
/// directory rather than a path at the root of the device, which is a write
/// that fails from a line that reads like a join.
String? dvAndroidStateDirectory(String? filesDir) {
  if (filesDir == null || filesDir.isEmpty) return null;
  String base = filesDir;
  while (base.length > 1 && base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty || base == '/') return null;
  return '$base/dartvel-device';
}

/// `Intent.FLAG_ACTIVITY_NEW_TASK`.
///
/// Starting an activity from the application `Context` rather than from an
/// `Activity` requires it. Without it Android throws at run time, on the
/// device: "Calling startActivity() from outside of an Activity context
/// requires the FLAG_ACTIVITY_NEW_TASK flag".
const int dvAndroidShareIntentFlags = 0x10000000;

/// Whether the share goes through `Intent.createChooser`.
///
/// It does. A bare `ACTION_SEND` resolves to whatever the user last chose, or
/// to nothing when no default is set; the chooser always resolves.
const bool dvAndroidShareUsesChooser = true;

/// The MIME type the shared payload is declared as.
///
/// An intent with no type is delivered to nothing — resolution matches on the
/// action and the type together.
const String dvAndroidShareMimeType = 'text/plain';

/// The route an application was launched at, from the URI it was given.
///
/// A home widget's tap is a deep link to the route Dartvel generated for it,
/// which is the whole of "home widgets can launch and navigate to pages
/// within the app" on Android. App links arrive the same way, so this reads
/// the path out of whatever scheme it was given rather than only the widget
/// one.
///
/// Null for a launch with no link. Answering `/` would make every cold start
/// look like a deep link to the home page, and the caller has to be able to
/// tell those apart.
String? dvAndroidLaunchRoute(String? uri) {
  if (uri == null || uri.isEmpty) return null;
  final Uri? parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.path.isEmpty) return null;
  // A path that is not a path is not a route. `Uri.tryParse` accepts a good
  // deal that is not an address, and a route built out of it would be a
  // not-found page on launch.
  if (!parsed.path.startsWith('/')) return null;
  return parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path;
}
