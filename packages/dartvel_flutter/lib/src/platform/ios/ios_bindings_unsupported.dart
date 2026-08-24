/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.ios.unsupported;

import 'ios_capabilities.dart';

/// The iOS bindings, unavailable here.
class DVIosBindings {
  const DVIosBindings._();

  static bool get isRegistered => false;

  /// What iOS covers — a fact about the platform rather than about where this
  /// code runs, so the list can be asserted anywhere.
  static const Set<String> implemented = dvIosImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}
