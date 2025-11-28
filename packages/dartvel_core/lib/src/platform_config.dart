import 'dart:io' as io;

/// Supported platforms for Dartvel framework
enum Platform {
  android,
  ios,
  windows,
  macos,
  linux,
  androidTV,
  appleTV,
  tizenOS,
  webOS,
  embeddedLinux,
  web;

  /// Check if the platform supports native code
  bool get supportsNativeCode {
    return this != Platform.web;
  }

  /// Get the platform display name
  String get displayName {
    switch (this) {
      case Platform.android:
        return 'Android';
      case Platform.ios:
        return 'iOS';
      case Platform.windows:
        return 'Windows';
      case Platform.macos:
        return 'macOS';
      case Platform.linux:
        return 'Linux';
      case Platform.androidTV:
        return 'Android TV';
      case Platform.appleTV:
        return 'Apple TV (tvOS)';
      case Platform.tizenOS:
        return 'Tizen OS (Samsung)';
      case Platform.webOS:
        return 'webOS (LG)';
      case Platform.embeddedLinux:
        return 'Embedded Linux';
      case Platform.web:
        return 'Web';
    }
  }

  /// Get the platform build command
  String get buildCommand {
    switch (this) {
      case Platform.android:
        return 'flutter build apk';
      case Platform.ios:
        return 'flutter build ios';
      case Platform.windows:
        return 'flutter build windows';
      case Platform.macos:
        return 'flutter build macos';
      case Platform.linux:
        return 'flutter build linux';
      case Platform.androidTV:
        return 'flutter build apk --target-platform android-arm64';
      case Platform.appleTV:
        return 'flutter build ios --config-only';
      case Platform.tizenOS:
        return 'flutter-tizen build tpk';
      case Platform.webOS:
        return 'flutter build linux'; // webOS typically uses custom tooling
      case Platform.embeddedLinux:
        return 'flutter build linux --target-platform linux-arm64';
      case Platform.web:
        return 'flutter build web';
    }
  }
}

/// Platform configuration for Dartvel
class PlatformConfig {
  final Set<Platform> enabledPlatforms;
  final Map<Platform, Map<String, dynamic>> platformSettings;

  const PlatformConfig({
    this.enabledPlatforms = const {
      Platform.android,
      Platform.ios,
      Platform.web,
      Platform.windows,
      Platform.macos,
      Platform.linux,
    },
    this.platformSettings = const {},
  });

  /// Check if a platform is enabled
  bool isPlatformEnabled(Platform platform) {
    return enabledPlatforms.contains(platform);
  }

  /// Get settings for a platform
  Map<String, dynamic>? getSettingsFor(Platform platform) {
    return platformSettings[platform];
  }

  /// Detect the current running platform
  static Platform detectCurrent() {
    if (io.Platform.isAndroid) return Platform.android;
    if (io.Platform.isIOS) return Platform.ios;
    if (io.Platform.isWindows) return Platform.windows;
    if (io.Platform.isMacOS) return Platform.macos;
    if (io.Platform.isLinux) return Platform.linux;
    // Web detection would work differently in actual web context
    return Platform.linux; // fallback
  }

  /// Get all supported platforms with their status
  Map<Platform, bool> get platformStatus {
    return Map.fromEntries(
      Platform.values.map((p) => MapEntry(p, enabledPlatforms.contains(p))),
    );
  }
}

/// Platform-specific build configuration
class BuildConfig {
  final Platform platform;
  final String outputPath;
  final bool release;
  final Map<String, String> buildArgs;

  const BuildConfig({
    required this.platform,
    required this.outputPath,
    this.release = false,
    this.buildArgs = const {},
  });

  /// Generate the full build command
  String generateBuildCommand() {
    final baseCommand = platform.buildCommand;
    final mode = release ? '--release' : '--debug';
    final args =
        buildArgs.entries.map((e) => '--${e.key}=${e.value}').join(' ');
    return '$baseCommand $mode $args';
  }
}
