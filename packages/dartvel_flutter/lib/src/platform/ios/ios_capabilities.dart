/// The names the iOS bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.ios.capabilities;

/// What iOS is bound for, and nothing more.
///
/// Only the clipboard. The reasons for each omission are specific rather than
/// "not done yet":
///
///   * **`screen.geometry`** would come from `UIScreen.nativeBounds`, which
///     returns a `CGRect`. A struct return through `objc_msgSend` needs
///     `objc_msgSend_stret` on some ABIs and corrupts the stack when the wrong
///     entry point is used. macOS avoids this with CoreGraphics, which has no
///     iOS equivalent, so there is no safe C path here.
///   * **Notifications** need `UNUserNotificationCenter`, authorisation
///     granted by the user, and a configured app delegate.
///   * **Haptics** need `UIImpactFeedbackGenerator`, which must be created and
///     called on the main thread.
///   * **Window controls** do not exist: an iOS app does not own a resizable
///     window.
const Set<String> dvIosImplementedBindings = <String>{
  // UIPasteboard through the Objective-C runtime.
  'clipboard.copy',
  'clipboard.paste',
};
