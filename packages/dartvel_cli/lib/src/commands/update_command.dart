import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../update/self_update.dart';
import '../utils/logger.dart';
import 'version_command.dart';

/// `dartvel update` — fetch the latest published CLI and replace this one.
///
/// A no-op when the running binary is already the newest, so it is safe to run
/// at any time. It refuses rather than guesses: an asset that does not match
/// the host, a manifest without a checksum, or a download whose hash does not
/// match all stop before anything touches the executable.
class UpdateCommand extends Command<void> {
  UpdateCommand() {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help: 'Report whether an update exists without installing it.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Reinstall even when the running version is already the latest.',
      );
  }

  @override
  final String name = 'update';

  @override
  final String description =
      'Update the Dartvel CLI to the latest published release.';

  @override
  Future<void> run() async {
    final bool checkOnly = argResults!['check'] as bool;
    final bool force = argResults!['force'] as bool;

    final changed = await dvUpgradeExecutable(
      current: File(Platform.resolvedExecutable),
      runningVersion: dartvelCliVersion,
      os: Platform.operatingSystem,
      arch: _architecture(),
      currentPath: Platform.environment['PATH'] ?? '',
      home:
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.',
      shell: Platform.environment['SHELL'],
      fetchManifest: _fetchManifest,
      download: _download,
      force: force,
      checkOnly: checkOnly,
    );
    Logger.log(
      changed
          ? (checkOnly
                ? 'A newer CLI release is available.'
                : 'CLI upgraded. Open a new terminal to refresh PATH.')
          : 'The CLI is already the latest release.',
    );
  }

  /// Dart reports the architecture only through the VM's version string, which
  /// is the one place it is available without a platform channel.
  static String _architecture() {
    final String version = Platform.version;
    if (version.contains('arm64') || version.contains('aarch64')) {
      return 'arm64';
    }
    return 'x64';
  }

  Future<Map<String, Object?>> _fetchManifest() async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse(dvLatestManifestUrl),
      );
      request.followRedirects = true;
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw StateError(
          'Could not read the release manifest: HTTP ${response.statusCode}.',
        );
      }
      final String body = await response.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw StateError('The release manifest was not a JSON object.');
      }
      return decoded;
    } finally {
      client.close();
    }
  }

  Future<List<int>> _download(String url) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Download failed: HTTP ${response.statusCode}.');
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close();
    }
  }
}
