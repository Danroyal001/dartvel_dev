/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.android.unsupported;

import 'android_capabilities.dart';
import 'android_capture.dart';

/// The Android bindings, unavailable here.
class DVAndroidBindings {
  const DVAndroidBindings._();

  static bool get isRegistered => false;

  /// What Android covers — a fact about the platform rather than about where
  /// this code runs, so the list can be asserted anywhere.
  static const Set<String> implemented = dvAndroidImplementedBindings;

  static bool register() => false;

  /// Never set: this build has no JNI at all, which is why register() is a
  /// constant false rather than something that can fail for a reason.
  static String? get lastFailure => null;

  static void unregister() {}
}

/// The capture bridge, unavailable here, and present so the name resolves.
///
/// Its twin lives in `android_capture_jni.dart` and is exported from the JNI
/// branch. Without this the two branches of the conditional import declare
/// different names, and the analyser -- which resolves the default branch, not
/// the one an Android build would take -- reports `DVAndroidCapture` undefined
/// in any code that names it. That is what an integration test asserting the
/// capture bindings hit: the test was right, the branches were uneven.
class DVAndroidCapture {
  const DVAndroidCapture._();

  /// The names the capture group covers. A fact about Android rather than
  /// about where this code runs, so it reads the same list either way.
  static const Set<String> implemented = dvAndroidCaptureBindings;

  static bool get isRegistered => false;

  /// Never set, for the same reason DVAndroidBindings.lastFailure is not:
  /// there is no JNI here to fail, so registration does not get far enough to
  /// have a reason.
  static String? get lastFailure => null;

  static void reset() {}
}
