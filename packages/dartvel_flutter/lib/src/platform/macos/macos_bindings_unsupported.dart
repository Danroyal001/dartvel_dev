/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.macos.unsupported;

import 'macos_capabilities.dart';

/// The macOS bindings, unavailable here.
class DVMacosBindings {
  const DVMacosBindings._();

  static bool get isRegistered => false;

  /// What macOS covers — a fact about the platform rather than about where
  /// this code runs, so the list can be asserted anywhere.
  static const Set<String> implemented = dvMacosImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}
