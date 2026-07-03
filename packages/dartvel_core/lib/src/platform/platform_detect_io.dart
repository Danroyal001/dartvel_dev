import 'dart:io' as io;
import '../platform_config.dart';

/// Detects the current platform on native platforms using dart:io.
Platform detectCurrentPlatform() {
  if (io.Platform.isAndroid) return Platform.android;
  if (io.Platform.isIOS) return Platform.ios;
  if (io.Platform.isWindows) return Platform.windows;
  if (io.Platform.isMacOS) return Platform.macos;
  if (io.Platform.isLinux) return Platform.linux;
  return Platform.linux;
}
