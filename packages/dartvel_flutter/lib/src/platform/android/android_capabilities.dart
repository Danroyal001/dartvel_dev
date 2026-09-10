/// The names the Android bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.android.capabilities;

/// What Android is bound for, and nothing more.
///
/// Reached through JNI and jnigen-generated bindings, per the native
/// integration rule — never a platform channel. Most of it goes through
/// `Context.getSystemService`, and the Context comes from the ContentProvider
/// `dartvel build android` writes — not from `GetApplicationContext()`, which
/// package:jni declares in a header and never defines, and which left every
/// binding here dead in every real application until an emulator run said
/// "undefined symbol". The header of `android_bindings_jni.dart` carries the
/// full account; this sentence used to send the next person to that symbol.
///
/// The rest needs an `Activity`, which a Context is not. `requestPermissions`
/// is an Activity method and both `onRequestPermissionsResult` and
/// `onActivityResult` are delivered only to an Activity, so the build writes
/// a transparent one of Dartvel's own for the results to arrive at. That is
/// what the camera, the picker, contacts, location and the permission dialog
/// are reached through.
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
///   * **Reading and writing an NFC tag** need the tag object, and a tag
///     reaches an application only through foreground dispatch or reader
///     mode. Both are Activity callbacks that fire whenever somebody taps,
///     and a one-shot binding has nowhere to wait: it would answer null for
///     ever, or hand back whatever was tapped last, which is worse.
///   * **Connecting to a Bluetooth device** is per-profile and asynchronous
///     on Android — `connectGatt` with a callback, or a socket for the
///     classic profiles. There is no `BluetoothDevice.connect()` to bind.
///     `removeBond()`, which `bluetooth.forget` would need, is hidden and
///     blocked for ordinary applications.
///   * **`display.enterFullscreen` and `display.exitFullscreen`** have to run
///     on Android's main thread; see [dvAndroidFullscreenBlocker].
///   * **`display.enableKiosk` and `display.disableKiosk`** are answered by
///     `kiosk.enforce` and `kiosk.release`, which `DVDisplayControls` falls
///     back to and which Android binds. A second registration would be two
///     answers to one question.
///   * **Window controls** do not apply — an Android app owns no resizable
///     window.
///
/// Two entries left this list rather than being built around. Notifications
/// were here because a channel and, since API 33, a permission "belong to the
/// application, not to a binding" — but a channel is created through
/// `NotificationManager`, a system service on the application Context like
/// the clipboard, and the binding answers false when notifications are
/// switched off rather than posting into a system that drops it. See
/// [dvAndroidNotificationNeedsChannel]. `screen.geometry` was here because
/// `WindowManager`'s modern API varies by API level and Flutter reports the
/// same numbers; it comes from `Resources.getDisplayMetrics()` instead, which
/// has not changed since API 1, and it answers for the default display where
/// Flutter answers for the window — different numbers in split screen, and
/// the name says screen.
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

  // The permission dialog, and what it guards. Every one of these needs an
  // Activity rather than a Context -- requestPermissions is an Activity
  // method and both of its results are delivered to one -- so they are
  // reached through the transparent Activity `dartvel build android` writes
  // beside the Context holder.
  'permissions.isGranted',
  'permissions.request',
  // ACTION_IMAGE_CAPTURE, written into the application's own cache through a
  // provider. The photograph comes back as bytes.
  'camera.takePhoto',
  // ACTION_OPEN_DOCUMENT, which is the system picker and needs no permission
  // at all: what it returns is a grant on the one file that was chosen.
  'media.pick',
  // ContactsContract, behind READ_CONTACTS.
  'contacts.getContacts',
  // LocationManager: the last fix when it is recent, and a single update
  // when it is not.
  'location.current',

  // The default display, from the Context's own DisplayMetrics. Not the
  // window Flutter reports: on a device in split screen the two differ, and
  // the name says screen. This list said for a long time that the binding was
  // deliberately absent; see dvAndroidGeometry for why that reasoning does
  // not hold against the route taken.
  'screen.geometry',

  // Whether there is a reader and it is switched on. Reading and writing a
  // tag are not here, and the header says why.
  'nfc.isAvailable',

  // What Bluetooth this device has and knows about. Reading, not connecting:
  // Android's connect is per-profile and asynchronous, so the four
  // action names Linux binds cannot be honoured in this shape.
  'bluetooth.isEnabled',
  'bluetooth.adapters',
  'bluetooth.devices',
  'bluetooth.scanDevices',
  'bluetooth.pair',

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
String? dvAndroidStateDirectory(String? filesDir) =>
    _dvAndroidUnder(filesDir, 'dartvel-device');

/// The one directory `files.readBytes`, `files.writeBytes` and `files.delete`
/// may touch, given the application's own files directory. Null when there is
/// none.
///
/// A subdirectory rather than the files directory itself, and that is the
/// whole point of the function. Confining the file bindings to the files
/// directory would put the device id and the provisioning record inside their
/// root, so `files.delete('dartvel-device/provisioning.json')` from
/// application code tidying up after itself would unprovision the device —
/// and nothing would report it, because the next `device.health` simply
/// carries a new id.
String? dvAndroidFilesRoot(String? filesDir) =>
    _dvAndroidUnder(filesDir, 'dartvel-files');

/// [name] under [filesDir], or null when that directory is not usable.
///
/// Null rather than a path at the root of the device: `getFilesDir()`
/// answering null or empty means this is not the application's Context, and
/// building `/dartvel-device` out of it is a write that fails at run time
/// from a line that reads like an ordinary join.
String? _dvAndroidUnder(String? filesDir, String name) {
  if (filesDir == null || filesDir.isEmpty) return null;
  String base = filesDir;
  while (base.length > 1 && base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty || base == '/') return null;
  return '$base/$name';
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

/// Why `display.enterFullscreen` and `display.exitFullscreen` are unbound on
/// Android, in one place so it is not retold three different ways.
///
/// Every route into fullscreen ends at the view hierarchy —
/// `View.setSystemUiVisibility` on the decor view, or
/// `WindowInsetsController.hide` from API 30 — and each of those reaches
/// `ViewRootImpl`, which calls `checkThread()` and throws
/// `CalledFromWrongThreadException` off Android's main thread. Flutter runs
/// Dart on the UI task runner, which is a different thread, so a direct call
/// from here would throw on every device and never here.
///
/// The fix is `Activity.runOnUiThread(Runnable)`, and the missing piece is the
/// `Runnable`: implementing a Java interface from Dart needs jnigen's
/// generated `implement`, and `java.lang.Runnable` is a stub in the committed
/// bindings because nothing listed it. `JImplementer` is public but its `add`
/// is `@internal` and wants a native trampoline only generated code has, so
/// there is no hand-written way round it.
///
/// So this is a one-line generation change followed by a small Dart one: add
/// `java.lang.Runnable` to `tool/android_bindings.jnigen.yaml`, run the
/// **Android bindings** workflow, then post the window work through it. It is
/// not a platform limitation and it is not blocked on anybody — it is blocked
/// on a generation run, which needs an Android SDK that this workspace has
/// none of.
///
/// `kiosk.enforce` is unaffected and stays bound: `startLockTask()` is a
/// binder call to the activity task manager and touches no views.
const String dvAndroidFullscreenBlocker =
    'display.enterFullscreen and display.exitFullscreen need Android main '
    'thread access through Activity.runOnUiThread(Runnable), and '
    'java.lang.Runnable is a stub in the committed jnigen bindings.';

/// The default display, or null when Android has not said yet.
///
/// **This reverses a decision recorded here, so the reasoning is worth
/// keeping.** The position was that `screen.geometry` "would come from
/// `WindowManager`, whose modern API returns metrics through classes that
/// vary by API level", and that "Flutter already reports the same numbers, so
/// a binding would add a second answer that can disagree with the first".
/// Both halves were right about the route they assumed. Neither survives the
/// route actually taken:
///
///   * Nothing here touches `WindowManager`. The numbers come from
///     `Resources.getDisplayMetrics()` off the application Context, which has
///     carried the same three fields since API 1. There is no `WindowMetrics`
///     branch and nothing to vary.
///   * The two answers are not the same number and were never meant to be.
///     Flutter reports the **view** — the window this application draws
///     into, a fraction of the screen in split screen and a slice of it in a
///     freeform window. This reports the **default display**, which is
///     exactly what the same binding name reports on every other target:
///     `XDisplayWidth` of the default X screen on Linux, the main display on
///     macOS, `window.screen` on the web. Android answering the window
///     instead is what would make the name mean two things.
///
/// What is given up by using the application Context is multi-display
/// accuracy: its resources track the default display, so an application shown
/// on an external monitor or a foldable's other panel is described by the
/// panel it is not on. That is a real limit, it is the same limit Linux and
/// macOS have for the same reason, and the alternative — an Activity's
/// resources — reports window bounds from API 30 and display bounds before
/// it, which is the API-level variance the original objection was about.
///
/// The keys match the web binding's — `width`, `height`, `devicePixelRatio` —
/// because application code reading `screen.geometry` must not have to know
/// which platform answered. Linux adds an X screen number instead of a ratio;
/// Android has a density and no screen number.
///
/// Null rather than zeroes. `DisplayMetrics` read before the display is up
/// gives 0x0, and a caller handed `{width: 0, height: 0}` cannot tell that
/// from a screen — every layout computed from it is quietly wrong and nothing
/// upstream throws.
///
/// A density of zero drops the ratio and keeps the pixels: the pixels are
/// still true, and a zero ratio is a division waiting to happen a long way
/// from here.
Map<String, Object?>? dvAndroidGeometry({
  required int widthPixels,
  required int heightPixels,
  required double density,
}) {
  if (widthPixels <= 0 || heightPixels <= 0) return null;
  return <String, Object?>{
    'width': widthPixels,
    'height': heightPixels,
    if (density > 0) 'devicePixelRatio': density,
  };
}

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
