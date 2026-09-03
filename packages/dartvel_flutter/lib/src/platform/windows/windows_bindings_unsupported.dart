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

/// The Windows kiosk enforcement, unavailable here.
class DVWindowsKiosk {
  const DVWindowsKiosk._();

  static String? lastConfineError;
  static bool confined = false;
  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};
  static List<String> get held => const <String>[];
  static void release() {}
}

/// The Windows global shortcuts, unavailable here.
class DVWindowsShortcuts {
  const DVWindowsShortcuts._();

  static const Set<String> implemented = <String>{'shortcuts.register', 'shortcuts.unregister'};
  static Future<void> unregister() async {}
}
