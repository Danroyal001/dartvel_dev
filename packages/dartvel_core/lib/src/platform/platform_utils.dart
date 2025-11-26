// Platform-specific utilities for embedded Linux and TV platforms
import 'dart:io';

/// Platform detector
class PlatformDetector {
  static bool get isEmbeddedLinux {
    if (!Platform.isLinux) return false;

    // Check for common embedded Linux indicators
    try {
      final osRelease = File('/etc/os-release');
      if (osRelease.existsSync()) {
        final content = osRelease.readAsStringSync();
        return content.contains('Raspberry') ||
            content.contains('embedded') ||
            content.contains('Yocto');
      }
    } catch (e) {
      // Ignore
    }

    return false;
  }

  static bool get isAndroidTV {
    // TODO: Proper detection
    return Platform.isAndroid; // Placeholder
  }

  static bool get isAppleTV {
    // TODO: Requires tvOS support
    return false;
  }

  static String get platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) {
      return isEmbeddedLinux ? 'Embedded Linux' : 'Linux';
    }
    return 'Unknown';
  }

  static bool get isTV => isAndroidTV || isAppleTV;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
}

/// TV-specific input handling
class TVInputHandler {
  static const Map<String, String> dPadKeys = {
    'ArrowUp': 'up',
    'ArrowDown': 'down',
    'ArrowLeft': 'left',
    'ArrowRight': 'right',
    'Enter': 'select',
    'Escape': 'back',
  };

  static String? mapTVKey(String key) {
    return dPadKeys[key];
  }

  static bool isTVKey(String key) {
    return dPadKeys.containsKey(key);
  }
}

/// Embedded Linux GPIO access (placeholder)
class GpioController {
  final int pin;

  GpioController(this.pin);

  Future<void> setOutput() async {
    // TODO: GPIO setup via sysfs or libgpiod
  }

  Future<void> setInput() async {
    // TODO: GPIO setup
  }

  Future<void> write(bool value) async {
    // TODO: Write to GPIO
  }

  Future<bool> read() async {
    // TODO: Read from GPIO
    return false;
  }
}

/// System info for embedded devices
class SystemInfo {
  static Future<String> getCpuArchitecture() async {
    try {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'unknown';
    }
  }

  static Future<String> getKernelVersion() async {
    try {
      final result = await Process.run('uname', ['-r']);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'unknown';
    }
  }

  static Future<Map<String, String>> getDeviceInfo() async {
    return {
      'platform': PlatformDetector.platformName,
      'architecture': await getCpuArchitecture(),
      'kernel': await getKernelVersion(),
      'isTV': PlatformDetector.isTV.toString(),
      'isEmbedded': PlatformDetector.isEmbeddedLinux.toString(),
    };
  }
}
