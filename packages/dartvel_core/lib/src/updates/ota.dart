// OTA Updates - Shorebird/EAS inspired
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// Update check result
class UpdateCheckResult {
  final bool updateAvailable;
  final String? version;
  final String? downloadUrl;
  final Map<String, Object?>? metadata;

  const UpdateCheckResult({
    required this.updateAvailable,
    this.version,
    this.downloadUrl,
    this.metadata,
  });

  factory UpdateCheckResult.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return UpdateCheckResult(
      updateAvailable: json['updateAvailable'] as bool,
      version: json['version'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      metadata: metadata is Map<Object?, Object?>
          ? Map<String, Object?>.from(metadata)
          : null,
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
  File? _lastDownloadedUpdate;

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
      final decoded = jsonDecode(body);
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException('Update response must be a JSON object.');
      }
      final json = Map<String, Object?>.from(decoded);

      client.close();

      return UpdateCheckResult.fromJson(json);
    } catch (e) {
      developer.log('Error checking for updates: $e', name: 'dartvel');
      return const UpdateCheckResult(updateAvailable: false);
    }
  }

  Stream<UpdateProgress> downloadUpdate(String url) async* {
    final client = HttpClient();
    final file = await _createDownloadFile(url);
    final sink = file.openWrite();

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final totalBytes = response.contentLength;
      var bytesDownloaded = 0;

      await for (final chunk in response) {
        bytesDownloaded += chunk.length;
        sink.add(chunk);
        yield UpdateProgress(bytesDownloaded, totalBytes);
      }
      await sink.flush();
      _lastDownloadedUpdate = file;
    } finally {
      await sink.close();
      client.close(force: true);
    }
  }

  Future<void> installUpdate(String updatePath) async {
    final update = File(updatePath);
    if (!update.existsSync()) {
      throw FileSystemException('Update artifact does not exist', updatePath);
    }
    final manifest = File('$updatePath.install.json');
    await manifest.writeAsString(jsonEncode({
      'updatePath': update.absolute.path,
      'version': _currentVersion,
      'platform': _platform,
      'installedAt': DateTime.now().toIso8601String(),
      'size': await update.length(),
    }));
    developer.log('Staged OTA update manifest: ${manifest.path}',
        name: 'dartvel');
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
          final update = _lastDownloadedUpdate;
          if (update != null) await installUpdate(update.path);
        }
      }
    }
  }

  Future<File> _createDownloadFile(String url) async {
    final dir = await Directory.systemTemp.createTemp('dartvel_ota_');
    final uri = Uri.parse(url);
    final name = uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
        ? 'update.bin'
        : uri.pathSegments.last;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }
}

/// Shorebird integration
class ShorebirdUpdater {
  static bool get isSupported {
    // Shorebird supports mobile platforms
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<void> checkForUpdate() async {
    if (!isSupported) {
      throw StateError('Shorebird updates require Android or iOS.');
    }
    await _runShorebird(['patch', 'list']);
  }

  static Future<void> downloadUpdate() async {
    if (!isSupported) {
      throw StateError('Shorebird updates require Android or iOS.');
    }
    await _runShorebird(['patch', 'download']);
  }

  static Future<void> _runShorebird(List<String> args) async {
    final result = await Process.run('shorebird', args, runInShell: true);
    if (result.exitCode != 0) {
      throw ProcessException(
        'shorebird',
        args,
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}
