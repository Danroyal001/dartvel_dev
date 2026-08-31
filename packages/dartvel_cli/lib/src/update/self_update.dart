/// `dartvel update` — replacing the running binary with the published one.
///
/// The download is the easy part. What has to be right is picking the asset
/// that matches the host, verifying it before it goes anywhere near the
/// executable, and replacing that executable in a way that cannot leave the
/// user with no working CLI and no way to install one.
library dartvel_cli.update.self_update;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where the published manifest lives.
///
/// `releases/latest/download/...` always resolves to the newest release, so
/// the CLI does not have to know a version to find one.
const String dvLatestManifestUrl =
    'https://github.com/Danroyal001/dartvel_dev/releases/latest/download/latest.json';

/// One row of the manifest: the binary for this host and its checksum.
class DVUpdateTarget {
  const DVUpdateTarget({
    required this.version,
    required this.url,
    required this.sha256,
  });

  final String version;
  final String url;
  final String sha256;
}

/// The release asset name for [os]/[arch].
///
/// The three vocabularies involved do not agree: `uname` says `aarch64`, Dart
/// says `arm64`, the release says `arm64`; Dart says `macos`, the release says
/// `darwin`. Mapping them wrong downloads a binary that installs cleanly and
/// then cannot exec, which reads as a corrupt download rather than a wrong one.
String dvAssetName({required String os, required String arch}) {
  final String platform = switch (os.toLowerCase()) {
    'linux' => 'linux',
    'macos' || 'darwin' => 'darwin',
    'windows' => 'windows',
    _ => throw ArgumentError.value(os, 'os', 'no published binary for this OS'),
  };

  final String cpu = switch (arch.toLowerCase()) {
    'x64' || 'x86_64' || 'amd64' => 'amd64',
    'arm64' || 'aarch64' => 'arm64',
    _ => throw ArgumentError.value(
        arch,
        'arch',
        'no published binary for this architecture',
      ),
  };

  // Windows keeps its extension: without it the file is not executable there,
  // and the failure surfaces later as "not recognized as a command".
  final String suffix = platform == 'windows' ? '.exe' : '';
  return 'dartvel-$platform-$cpu$suffix';
}

/// Reads the entry for [assetName] out of a decoded manifest.
DVUpdateTarget dvUpdateTargetFrom(
  Map<String, Object?> manifest, {
  required String assetName,
}) {
  final Object? version = manifest['version'];
  final Object? assets = manifest['assets'];
  if (version is! String || assets is! Map) {
    throw StateError('The release manifest is not in the expected shape.');
  }

  final Object? entry = assets[assetName];
  if (entry is! Map) {
    throw StateError(
      'Release $version publishes no "$assetName". Available: '
      '${assets.keys.join(', ')}.',
    );
  }

  final Object? url = entry['url'];
  final Object? sum = entry['sha256'];
  if (url is! String || url.isEmpty) {
    throw StateError('"$assetName" has no download URL in the manifest.');
  }
  // Refused rather than downloaded unverified. Installing whatever answered
  // the request, over the binary the user runs, is the one thing this must
  // never do.
  if (sum is! String || sum.isEmpty) {
    throw StateError(
      '"$assetName" has no sha256 in the manifest, so the download cannot be '
      'verified and will not be installed.',
    );
  }

  return DVUpdateTarget(version: version, url: url, sha256: sum);
}

/// Whether [published] is a later release than [running].
///
/// Compared numerically per component. As strings '0.10.0' sorts below
/// '0.9.0', which would strand everyone on 0.9 exactly when the tenth release
/// shipped. An unreadable version is not an update: replacing a working binary
/// on the strength of a string nobody can parse is worse than staying put.
bool dvIsNewer({required String published, required String running}) {
  final List<int>? left = _parseVersion(published);
  final List<int>? right = _parseVersion(running);
  if (left == null || right == null) return false;

  for (int i = 0; i < 3; i += 1) {
    if (left[i] != right[i]) return left[i] > right[i];
  }
  // Equal cores. A prerelease of the same version is not newer than the
  // release, so 0.4.0-beta.1 never replaces 0.4.0.
  final bool leftPre = published.contains('-');
  final bool rightPre = running.contains('-');
  if (leftPre && !rightPre) return false;
  if (!leftPre && rightPre) return true;
  return false;
}

List<int>? _parseVersion(String value) {
  final RegExpMatch? match =
      RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(value.trim());
  if (match == null) return null;
  return <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

/// The SHA-256 of [bytes], lower-case hex.
String dvSha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Whether [bytes] matches [expected].
///
/// An empty download never passes, whatever it hashes to: a truncated or
/// refused request that still wrote a file is not a release.
bool dvVerifyDownload(List<int> bytes, String expected) {
  if (bytes.isEmpty) return false;
  return dvSha256Hex(bytes).toLowerCase() == expected.trim().toLowerCase();
}

/// Puts [bytes] in place of [current], keeping the old binary alongside.
///
/// The old file is moved aside before the new one is written. Writing straight
/// over the running executable can leave nothing at all if the write fails
/// halfway, and the user then has no CLI to install a CLI with.
Future<void> dvReplaceExecutable({
  required File current,
  required List<int> bytes,
}) async {
  final File backup = File('${current.path}.old');
  if (backup.existsSync()) backup.deleteSync();
  if (current.existsSync()) {
    // Renamed rather than copied: on every platform this is atomic within a
    // directory, and it releases the name without a window where neither file
    // exists.
    current.renameSync(backup.path);
  }

  try {
    await current.writeAsBytes(bytes, flush: true);
  } on Object {
    // Put the working binary back rather than leaving the user with nothing.
    if (backup.existsSync() && !current.existsSync()) {
      backup.renameSync(current.path);
    }
    rethrow;
  }

  if (!Platform.isWindows) {
    final ProcessResult result =
        await Process.run('chmod', <String>['+x', current.path]);
    if (result.exitCode != 0) {
      throw StateError(
        'Downloaded ${current.path} but could not make it executable: '
        '${result.stderr}',
      );
    }
  }
}
