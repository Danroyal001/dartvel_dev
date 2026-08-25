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
};
