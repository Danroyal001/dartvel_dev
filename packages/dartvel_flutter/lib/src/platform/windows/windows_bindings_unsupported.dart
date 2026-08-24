/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.windows.unsupported;

import 'windows_capabilities.dart';

/// The Windows bindings, unavailable here.
class DVWindowsBindings {
  const DVWindowsBindings._();

  static bool get isRegistered => false;

  /// What Win32 covers, which is a fact about the platform rather than about
  /// where this code is running — so the list can be asserted anywhere.
  static const Set<String> implemented = dvWindowsImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}
