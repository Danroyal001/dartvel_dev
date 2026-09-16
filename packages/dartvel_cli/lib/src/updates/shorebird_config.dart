/// What a project's `shorebird.yaml` says about where its patches come from.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Shorebird's hosted service, which the updater uses when `base_url` is
/// absent.
const String dvShorebirdHostedApi = 'api.shorebird.dev';

/// The largest patch a self-hosted patch source accepts in one publish.
///
/// A patch is a compressed binary diff of the compiled Dart, a few megabytes
/// for most applications. The server's own body limit is one megabyte, so the
/// publish route declares this instead.
const int dvPatchPublishMaxBytes = 256 * 1024 * 1024;

/// A project's `shorebird.yaml`, as far as Dartvel reads it.
class DVShorebirdConfig {
  const DVShorebirdConfig({required this.appId, this.baseUrl});

  final String appId;

  /// Where the updater asks for patches; null is Shorebird's hosted service.
  final Uri? baseUrl;

  /// Whether the patches come from a patch source this project hosts.
  bool get selfHosted =>
      baseUrl != null && baseUrl!.host.toLowerCase() != dvShorebirdHostedApi;

  /// The path the patch source is served under on its server: `base_url`'s
  /// path without a trailing slash, so `https://example.com/updates` is
  /// `/updates` and `https://updates.example.com` is the empty string.
  String? get patchSourcePrefix =>
      selfHosted ? baseUrl!.path.replaceAll(RegExp(r'/+$'), '') : null;

  /// Reads `shorebird.yaml` in [root]. Null when there is none; throws
  /// [FormatException] for one that names no app_id or a base_url that is
  /// not an http(s) URL.
  static DVShorebirdConfig? read(String root) {
    final File file = File(p.join(root, 'shorebird.yaml'));
    if (!file.existsSync()) return null;
    final Object? doc = loadYaml(file.readAsStringSync());
    if (doc is! Map) {
      throw const FormatException('shorebird.yaml is not a mapping.');
    }
    final Object? appId = doc['app_id'];
    if (appId is! String || appId.trim().isEmpty) {
      throw const FormatException('shorebird.yaml names no app_id.');
    }
    final Object? base = doc['base_url'];
    Uri? baseUrl;
    if (base != null) {
      baseUrl = base is String ? Uri.tryParse(base.trim()) : null;
      if (baseUrl == null ||
          (baseUrl.scheme != 'http' && baseUrl.scheme != 'https') ||
          baseUrl.host.isEmpty) {
        throw FormatException(
          'shorebird.yaml base_url "$base" is not an http or https URL.',
        );
      }
    }
    return DVShorebirdConfig(appId: appId.trim(), baseUrl: baseUrl);
  }
}

/// The patch source prefix the backend generated for [root] serves, or null
/// when the project's patches do not come from its own server -- no
/// shorebird.yaml, one with no base_url, or one naming Shorebird's service.
/// A shorebird.yaml that cannot be read serves nothing rather than failing
/// the generation of a backend that may not ship a mobile app at all.
String? dvPatchSourcePrefix(String root) {
  try {
    return DVShorebirdConfig.read(root)?.patchSourcePrefix;
  } on FormatException {
    // YamlException included.
    return null;
  }
}
