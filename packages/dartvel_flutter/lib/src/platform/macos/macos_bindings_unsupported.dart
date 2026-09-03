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

/// The macOS kiosk enforcement, unavailable here.
class DVMacosKiosk {
  const DVMacosKiosk._();

  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};
  static const int kioskOptions = 0;
  static int get presentationOptions => 0;
  static void release() {}
}

/// The macOS global shortcuts, unavailable here.
class DVMacosShortcuts {
  const DVMacosShortcuts._();

  static const Set<String> implemented = <String>{'shortcuts.register', 'shortcuts.unregister'};
  static void pump(Duration slice) {}
  static void unregister() {}
}
