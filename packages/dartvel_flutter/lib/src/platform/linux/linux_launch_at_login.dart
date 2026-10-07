/// Launch at login on Linux: an XDG autostart entry.
///
/// The freedesktop Desktop Application Autostart specification: a desktop
/// entry in `$XDG_CONFIG_HOME/autostart` is started by the session at
/// login. Files, so it is the same on GNOME, KDE, XFCE and the rest, and
/// needs nothing running to write.
library;

import 'dart:async';
import 'dart:io';

class DVLinuxLaunchAtLogin {
  DVLinuxLaunchAtLogin({required this.configHome, required this.executable, required this.name});

  /// The entry for the running application, in the user's config home.
  factory DVLinuxLaunchAtLogin.current() {
    final String home = Platform.environment['HOME'] ?? '';
    final String configured = Platform.environment['XDG_CONFIG_HOME'] ?? '';
    final String executable = Platform.resolvedExecutable;
    return DVLinuxLaunchAtLogin(
      configHome: configured.isNotEmpty ? configured : '$home/.config',
      executable: executable,
      name: executable.split('/').last,
    );
  }

  final String configHome;
  final String executable;

  /// What a session's startup list shows.
  final String name;

  File get file => File('$configHome/autostart/${executable.split('/').last}.desktop');

  /// On when the entry is there and the user has not switched it off in
  /// their session's settings, which writes Hidden or the GNOME key rather
  /// than deleting the file.
  bool get isEnabled {
    if (!file.existsSync()) return false;
    final List<String> lines = file.readAsLinesSync();
    return !lines.contains('Hidden=true') && !lines.contains('X-GNOME-Autostart-enabled=false');
  }

  void setEnabled(bool enabled) {
    if (!enabled) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=$name\n'
      // Quoted, as the Desktop Entry spec quotes an argument with a space.
      'Exec="${executable.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"\n'
      'X-GNOME-Autostart-enabled=true\n',
    );
  }

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('launchAtLogin.isEnabled', (Object? _) => DVLinuxLaunchAtLogin.current().isEnabled);
    bind('launchAtLogin.setEnabled', (Object? arguments) {
      final bool enabled = arguments is Map && arguments['enabled'] == true;
      DVLinuxLaunchAtLogin.current().setEnabled(enabled);
      return true;
    });
  }
}
