/// Starting the application when the user logs in.
///
/// A menu-bar or tray application is one a user expects to be there after a
/// restart without opening it. Each desktop keeps that list somewhere of
/// its own -- an XDG autostart entry on Linux, the per-user Run key on
/// Windows, SMAppService's login items on macOS -- and each is per-user, so
/// nothing here needs administrator rights.
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';

/// `DV.Platform.launchAtLogin`.
class DVLaunchAtLogin {
  const DVLaunchAtLogin();

  /// Whether this platform has a binding. For deciding whether to offer the
  /// setting; [setEnabled] still throws where there is none.
  bool get isSupported => DVNativeBridge.isRegistered('launchAtLogin.isEnabled');

  /// Whether the application starts at login now. Reads the desktop's own
  /// list, so a user who turned it off in the system settings is answered
  /// truthfully rather than with what this application last wrote.
  Future<bool> isEnabled() => DVNativeBridge.require<bool>('launchAtLogin.isEnabled');

  /// Turns starting at login on or off for the user running the
  /// application. A binding that could not is an error rather than a
  /// setting that silently did not stick.
  Future<void> setEnabled(bool enabled) async {
    final bool done = await DVNativeBridge.require<bool>(
      'launchAtLogin.setEnabled',
      <String, Object?>{'enabled': enabled},
    );
    if (!done) {
      throw StateError('The desktop refused to ${enabled ? 'add' : 'remove'} the login item.');
    }
  }
}
