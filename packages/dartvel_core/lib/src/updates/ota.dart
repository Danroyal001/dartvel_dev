// OTA Updates - Shorebird/EAS inspired
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Update check result
class UpdateCheckResult {
  final bool updateAvailable;
  final String? version;
  final String? downloadUrl;
  final Map<String, dynamic>? metadata;

  const UpdateCheckResult({
    required this.updateAvailable,
    this.version,
    this.downloadUrl,
    this.metadata,
  });

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) {
    return UpdateCheckResult(
      updateAvailable: json['updateAvailable'] as bool,
      version: json['version'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Update download progress
class UpdateProgress {
  final int bytesDownloaded;
  final int totalBytes;

  const UpdateProgress(this.bytesDownloaded, this.totalBytes);

  double get percentage => totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;
}

/// OTA Update manager
class OtaUpdater {
  static final _instance = OtaUpdater._();
  OtaUpdater._();

  static OtaUpdater get instance => _instance;

  String? _updateServerUrl;
  String? _currentVersion;
  String? _platform;

  void configure({
    required String updateServerUrl,
    required String currentVersion,
    String? platform,
  }) {
    _updateServerUrl = updateServerUrl;
    _currentVersion = currentVersion;
    _platform = platform ?? _detectPlatform();
  }

  String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    if (_updateServerUrl == null || _currentVersion == null) {
      throw StateError('OtaUpdater not configured');
    }

    try {
      final client = HttpClient();
      final uri = Uri.parse('$_updateServerUrl/check');
      final request = await client.getUrl(uri);

      request.headers.set('x-current-version', _currentVersion!);
      request.headers.set('x-platform', _platform!);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      client.close();

      return UpdateCheckResult.fromJson(json);
    } catch (e) {
      print('Error checking for updates: $e');
      return const UpdateCheckResult(updateAvailable: false);
    }
  }

  Stream<UpdateProgress> downloadUpdate(String url) async* {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    final totalBytes = response.contentLength;
    var bytesDownloaded = 0;

    await for (final chunk in response) {
      bytesDownloaded += chunk.length;
      yield UpdateProgress(bytesDownloaded, totalBytes);
      // TODO: Write to temporary file
    }

    client.close();
  }

  Future<void> installUpdate(String updatePath) async {
    // TODO: Platform-specific installation
    // For now, just a placeholder
    print('Installing update from: $updatePath');
  }

  Future<void> checkAndUpdate({
    bool silent = false,
    void Function(UpdateCheckResult)? onUpdateAvailable,
    void Function(UpdateProgress)? onProgress,
  }) async {
    final result = await checkForUpdate();

    if (result.updateAvailable) {
      onUpdateAvailable?.call(result);

      if (result.downloadUrl != null) {
        await for (final progress in downloadUpdate(result.downloadUrl!)) {
          onProgress?.call(progress);
        }

        // Auto-install if silent
        if (silent) {
          // await installUpdate(downloadPath);
        }
      }
    }
  }
}

/// Shorebird integration
class ShorebirdUpdater {
  static bool get isSupported {
    // Shorebird supports mobile platforms
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<void> checkForUpdate() async {
    if (!isSupported) return;

    // TODO: Integrate with shorebird_code_push package
    // This is a placeholder for now
    print('Checking for Shorebird updates...');
  }

  static Future<void> downloadUpdate() async {
    if (!isSupported) return;
    print('Downloading Shorebird update...');
  }
}
