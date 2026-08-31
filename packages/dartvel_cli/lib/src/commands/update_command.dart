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

    final String assetName = dvAssetName(
      os: Platform.operatingSystem,
      arch: _architecture(),
    );

    Logger.log('Checking for a newer release...');
    final Map<String, Object?> manifest = await _fetchManifest();
    final DVUpdateTarget target =
        dvUpdateTargetFrom(manifest, assetName: assetName);

    if (!force && !dvIsNewer(published: target.version, running: dartvelCliVersion)) {
      Logger.log(
        'dartvel $dartvelCliVersion is already the latest '
        '(published: ${target.version}).',
      );
      return;
    }

    Logger.log('A newer release is available: ${target.version} '
        '(running $dartvelCliVersion).');
    if (checkOnly) return;

    // The running executable, not whatever is first on PATH: updating a
    // different copy than the one being run is the confusing failure here.
    final File current = File(Platform.resolvedExecutable);
    if (!current.existsSync()) {
      throw StateError(
        'Could not find the running executable at ${current.path}.',
      );
    }
    // A `dart run` of the CLI resolves to the Dart VM, and replacing that
    // would be catastrophic. Refuse rather than overwrite it.
    final String basename = current.uri.pathSegments.last;
    if (basename == 'dart' || basename == 'dart.exe') {
      Logger.error(
        'This is running through the Dart VM rather than as the packaged '
        'binary, so there is no dartvel executable to replace. Install the '
        'binary with Homebrew or npm, or run `dart pub global activate '
        'dartvel_cli` to update the pub copy.',
      );
      return;
    }

    Logger.log('Downloading ${target.url}...');
    final List<int> bytes = await _download(target.url);

    if (!dvVerifyDownload(bytes, target.sha256)) {
      throw StateError(
        'The download did not match its published checksum and has not been '
        'installed. Expected ${target.sha256}, got ${dvSha256Hex(bytes)}.',
      );
    }
    Logger.log('Checksum verified.');

    await dvReplaceExecutable(current: current, bytes: bytes);
    Logger.log(
      'Updated to ${target.version}. The previous binary is at '
      '${current.path}.old.',
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
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(dvLatestManifestUrl));
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
