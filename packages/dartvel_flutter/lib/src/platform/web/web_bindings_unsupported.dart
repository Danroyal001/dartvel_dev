/// Stand-in for builds without `dart:js_interop` — every native target.
library dartvel_flutter.platform.web.unsupported;

import 'web_capabilities.dart';

// Re-exported so the capability lists and DVWebPermissionDenied reach an
// application through the package barrel. Without this an application could
// catch nothing more specific than Exception for a refusal, which is the
// distinction these files exist to make.
export 'web_capabilities.dart';

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

  /// What this build actually bound, which off the web is nothing.
  ///
  /// Separate from [implemented] because the two answer different questions
  /// and only one of them is constant. A browser without Web NFC registers
  /// no `nfc.readTag` even though the web platform has one, and a caller
  /// deciding whether to offer the feature has to read this rather than the
  /// capability list.
  static Set<String> get registeredNames => const <String>{};

  static bool register() => false;

  static void unregister() {}
}
