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
    if (!Platform.isAndroid) return false;
    final type = Platform.environment['DARTVEL_DEVICE_TYPE']?.toLowerCase();
    final features = Platform.environment['DARTVEL_ANDROID_FEATURES'] ?? '';
    return type == 'tv' ||
        features.contains('android.software.leanback') ||
        features.contains('android.hardware.type.television');
  }

  static bool get isAppleTV {
    final type = Platform.environment['DARTVEL_DEVICE_TYPE']?.toLowerCase();
    final platform = Platform.environment['DARTVEL_PLATFORM']?.toLowerCase();
    return type == 'tv' && (platform == 'tvos' || platform == 'appletv');
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

/// Embedded Linux GPIO access through Linux sysfs GPIO.
class GpioController {
  final int pin;
  final Directory gpioRoot;

  GpioController(this.pin, {Directory? gpioRoot})
      : gpioRoot = gpioRoot ?? Directory('/sys/class/gpio');

  Directory get _pinDir => Directory('${gpioRoot.path}/gpio$pin');
  File get _export => File('${gpioRoot.path}/export');
  File get _direction => File('${_pinDir.path}/direction');
  File get _value => File('${_pinDir.path}/value');

  Future<void> setOutput() async {
    await _ensureExported();
    await _direction.writeAsString('out');
  }

  Future<void> setInput() async {
    await _ensureExported();
    await _direction.writeAsString('in');
  }

  Future<void> write(bool value) async {
    await _ensureExported();
    if (!_direction.existsSync() ||
        !_direction.readAsStringSync().trim().startsWith('out')) {
      await setOutput();
    }
    await _value.writeAsString(value ? '1' : '0');
  }

  Future<bool> read() async {
    await _ensureExported();
    return (await _value.readAsString()).trim() == '1';
  }

  Future<void> _ensureExported() async {
    if (!Platform.isLinux) {
      throw StateError('GPIO sysfs access is only available on Linux.');
    }
    if (_pinDir.existsSync()) return;
    if (!_export.existsSync()) {
      throw FileSystemException('GPIO export path not available', _export.path);
    }
    await _export.writeAsString('$pin');
    for (var i = 0; i < 20; i++) {
      if (_pinDir.existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw FileSystemException('GPIO pin was not exported', _pinDir.path);
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
