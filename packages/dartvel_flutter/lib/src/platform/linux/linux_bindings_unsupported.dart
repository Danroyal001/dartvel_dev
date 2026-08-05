/// Stand-in for platforms without dart:ffi (the web) or without X11/GTK.
library dartvel_flutter.platform.linux.unsupported;

/// The Linux desktop bindings, unavailable here.
///
/// [register] reports false rather than pretending: every `DV.Platform`
/// binding stays unregistered and throws with its own message when called.
class DVLinuxBindings {
  const DVLinuxBindings._();

  static bool get isRegistered => false;

  static const Set<String> implemented = <String>{};

  static bool register() => false;

  static void unregister() {}
}
