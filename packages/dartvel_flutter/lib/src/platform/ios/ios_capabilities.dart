/// The names the iOS bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.ios.capabilities;

/// What iOS is bound for, and nothing more.
///
/// The clipboard and haptics. The reasons for each omission are specific
/// rather than "not done yet":
///
///   * **`screen.geometry`** would come from `UIScreen.nativeBounds`, which
///     returns a `CGRect`. A struct return through `objc_msgSend` needs
///     `objc_msgSend_stret` on some ABIs and corrupts the stack when the wrong
///     entry point is used. macOS avoids this with CoreGraphics, which has no
///     iOS equivalent, so there is no safe C path here.
///   * **Notifications** need `UNUserNotificationCenter`, authorisation
///     granted by the user, and a configured app delegate.
///   * **Window controls** do not exist: an iOS app does not own a resizable
///     window.
const Set<String> dvIosImplementedBindings = <String>{
  // UIPasteboard through the Objective-C runtime.
  'clipboard.copy',
  'clipboard.paste',
  // AudioToolbox, not UIKit. See dvIosHapticSoundId.
  'haptics.impact',
  'haptics.lightVibrate',
  'haptics.vibrate',
};

/// The system sound identifier that produces a given haptic.
///
/// `UIImpactFeedbackGenerator` is the documented API and is unusable here: it
/// must be constructed and called on the main thread, and Flutter's root
/// isolate runs on the UI thread. `AudioServicesPlaySystemSound` is a plain C
/// function in AudioToolbox, safe to call from any thread, and the identifiers
/// in the 1519-1521 range are the Taptic Engine taps rather than sounds.
///
/// Throws for a name this does not cover. A fallback would be worse than an
/// error: identifiers below 1000 are alert sounds, so a mistyped name would
/// play a noise out loud on a device meant to tap silently.
int dvIosHapticSoundId(String name) => switch (name) {
      // Peek: the lightest tap the Taptic Engine produces.
      'haptics.lightVibrate' => 1519,
      // Pop: firmer, the one that reads as an impact.
      'haptics.impact' => 1520,
      // kSystemSoundID_Vibrate. The taps above are silent on a device with a
      // Taptic Engine and do nothing at all on one without, so a full vibrate
      // has to be the real motor.
      'haptics.vibrate' => 4095,
      _ => throw ArgumentError.value(
          name, 'name', 'Not an iOS haptic binding'),
    };
