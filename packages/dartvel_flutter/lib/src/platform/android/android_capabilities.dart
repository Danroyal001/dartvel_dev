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
/// `Context.getSystemService`, and the Context comes from
/// `GetApplicationContext()`, a C function package:jni exports for exactly
/// this purpose.
///
/// Absent, with reasons rather than "not yet":
///
///   * **Notifications** need a notification channel created at run time and,
///     since API 33, a permission the user grants. Both belong to the
///     application, not to a binding.
///   * **Biometrics and NFC** need an `Activity`, not a `Context`:
///     `BiometricPrompt` attaches to one and NFC dispatch is delivered to it.
///   * **Window controls** do not apply — an Android app owns no resizable
///     window.
///   * **`screen.geometry`** would come from `WindowManager`, whose modern API
///     returns metrics through classes that vary by API level. Flutter already
///     reports the same numbers, so a binding would add a second answer that
///     can disagree with the first.
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
};

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
