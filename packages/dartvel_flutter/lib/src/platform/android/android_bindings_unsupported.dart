/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.android.unsupported;

import 'android_capabilities.dart';

/// The Android bindings, unavailable here.
class DVAndroidBindings {
  const DVAndroidBindings._();

  static bool get isRegistered => false;

  /// What Android covers — a fact about the platform rather than about where
  /// this code runs, so the list can be asserted anywhere.
  static const Set<String> implemented = dvAndroidImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}
