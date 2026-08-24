/// Stand-in for builds without `dart:js_interop` — every native target.
library dartvel_flutter.platform.web.unsupported;

import 'web_capabilities.dart';

/// The browser bindings, unavailable here.
///
/// [register] reports false rather than pretending, so every `DV.Platform`
/// binding stays unregistered and throws its own message when called.
class DVWebBindings {
  const DVWebBindings._();

  static bool get isRegistered => false;

  /// What the browser covers, which is a fact about the platform rather than
  /// about where this code is running.
  ///
  /// Unlike the Linux stub, this is the full set on both branches. The Linux
  /// one reports an empty set off-Linux because "which X11 bindings exist" is
  /// only answerable where X11 is; "which web APIs exist" is answerable
  /// anywhere, and keeping it constant is what lets the capability list be
  /// asserted from an ordinary VM test.
  static const Set<String> implemented = dvWebImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}
