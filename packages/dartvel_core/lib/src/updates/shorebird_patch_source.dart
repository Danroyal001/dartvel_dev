/// A patch source for the Shorebird updater, served by Dartvel.
///
/// Shorebird's updater is compiled into its Flutter engine and asks
/// `<base_url>/api/v1/patches/check` whether a release has a patch;
/// `base_url` comes from the application's `shorebird.yaml` and defaults to
/// Shorebird's hosted service. Pointed here, the whole exchange is this file:
/// the check, the patch download, and the events endpoint the updater reports
/// installs to. The shapes are the updater's own, from `library/src/network.rs`
/// in shorebirdtech/updater.
///
/// Shorebird does not offer self-hosting and does not document this protocol
/// as stable; it is the open-source updater's wire format, and a change to it
/// would arrive with a new engine version that a release is pinned to anyway.
///
/// Patches live in a directory:
/// `<root>/<app>/<release>/<platform>/<arch>/<number>/{patch.bin,patch.json}`.
library;

import 'dart:convert';
import 'dart:io';

/// The release a patch applies to.
class DVShorebirdPatchTarget {
  const DVShorebirdPatchTarget({
    required this.appId,
    required this.releaseVersion,
    required this.platform,
    required this.arch,
  });

  final String appId;

  /// `versionName+versionCode`, as the updater reads it from the app.
  final String releaseVersion;

  /// `android`, `ios`, ...
  final String platform;

  /// The updater's spelling: `aarch64`, `arm`, `x86_64`.
  final String arch;

  List<String> get _segments => <String>[appId, releaseVersion, platform, arch];
}

/// A published patch.
class DVShorebirdPatch {
  const DVShorebirdPatch({
    required this.number,
    required this.hash,
    required this.channel,
    required this.rolledBack,
    this.hashSignature,
  });

  final int number;

  /// Hex SHA-256 of the patched file the diff produces, which the updater
  /// checks before it will boot it.
  final String hash;
  final String channel;
  final bool rolledBack;
  final String? hashSignature;

  Map<String, Object?> toJson() => <String, Object?>{
    'number': number,
    'hash': hash,
    'channel': channel,
    'rolled_back': rolledBack,
    'hash_signature': ?hashSignature,
  };

  factory DVShorebirdPatch.fromJson(Map<String, Object?> json) =>
      DVShorebirdPatch(
        number: json['number']! as int,
        hash: json['hash']! as String,
        channel: json['channel']! as String,
        rolledBack: json['rolled_back'] == true,
        hashSignature: json['hash_signature'] as String?,
      );
}

class DVShorebirdPatchSource {
  DVShorebirdPatchSource(this.root);

  /// The directory patches are kept in.
  final String root;

  static final RegExp _segment = RegExp(r'^[A-Za-z0-9._+-]{1,128}$');

  String _dir(List<String> segments) {
    for (final String s in segments) {
      if (!_segment.hasMatch(s) || s == '.' || s == '..') {
        throw FormatException('"$s" is not a valid patch path component.');
      }
    }
    return <String>[root, ...segments].join(Platform.pathSeparator);
  }

  /// Every patch published for [target], oldest first.
  List<DVShorebirdPatch> patches(DVShorebirdPatchTarget target) {
    final Directory dir = Directory(_dir(target._segments));
    if (!dir.existsSync()) return const <DVShorebirdPatch>[];
    final List<DVShorebirdPatch> found = <DVShorebirdPatch>[];
    for (final FileSystemEntity entry in dir.listSync()) {
      final File meta = File('${entry.path}${Platform.pathSeparator}patch.json');
      if (entry is! Directory || !meta.existsSync()) continue;
      found.add(
        DVShorebirdPatch.fromJson(
          (jsonDecode(meta.readAsStringSync()) as Map<Object?, Object?>)
              .cast<String, Object?>(),
        ),
      );
    }
    return found..sort((a, b) => a.number.compareTo(b.number));
  }

  /// Stores [diff] as the next patch for [target].
  ///
  /// [patchedHash] is the hex SHA-256 of the file the diff turns the release
  /// into -- not of the diff -- because that is what the updater verifies.
  DVShorebirdPatch publish(
    DVShorebirdPatchTarget target, {
    required List<int> diff,
    required String patchedHash,
    String channel = 'stable',
    String? hashSignature,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(patchedHash)) {
      throw const FormatException('The hash is a hex SHA-256.');
    }
    _dir(<String>[channel]);
    final List<DVShorebirdPatch> existing = patches(target);
    final DVShorebirdPatch patch = DVShorebirdPatch(
      number: existing.isEmpty ? 1 : existing.last.number + 1,
      hash: patchedHash,
      channel: channel,
      rolledBack: false,
      hashSignature: hashSignature,
    );
    final Directory dir = Directory(
      _dir(<String>[...target._segments, '${patch.number}']),
    )..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}patch.bin').writeAsBytesSync(diff);
    File(
      '${dir.path}${Platform.pathSeparator}patch.json',
    ).writeAsStringSync(jsonEncode(patch.toJson()));
    return patch;
  }

  /// Marks patch [number] of [target] rolled back. Devices running it drop it
  /// at their next check.
  void rollBack(DVShorebirdPatchTarget target, int number) {
    final File meta = File(
      '${_dir(<String>[...target._segments, '$number'])}'
      '${Platform.pathSeparator}patch.json',
    );
    if (!meta.existsSync()) {
      throw StateError('There is no patch $number for this release.');
    }
    final DVShorebirdPatch patch = DVShorebirdPatch.fromJson(
      (jsonDecode(meta.readAsStringSync()) as Map<Object?, Object?>)
          .cast<String, Object?>(),
    );
    meta.writeAsStringSync(
      jsonEncode(
        DVShorebirdPatch(
          number: patch.number,
          hash: patch.hash,
          channel: patch.channel,
          rolledBack: true,
          hashSignature: patch.hashSignature,
        ).toJson(),
      ),
    );
  }

  /// The updater's patch check, answered.
  ///
  /// Throws [FormatException] for a request that does not name a release in
  /// the updater's shape.
  Map<String, Object?> check(
    Map<String, Object?> request, {
    required Uri downloadBase,
  }) {
    String field(String name) {
      final Object? value = request[name];
      if (value is! String || value.isEmpty) {
        throw FormatException('The patch check names no $name.');
      }
      return value;
    }

    final DVShorebirdPatchTarget target = DVShorebirdPatchTarget(
      appId: field('app_id'),
      releaseVersion: field('release_version'),
      platform: field('platform'),
      arch: field('arch'),
    );
    _dir(target._segments);
    final String channel = request['channel'] is String
        ? request['channel']! as String
        : 'stable';
    final Object? running =
        request['current_patch_number'] ?? request['patch_number'];
    final int current = running is int ? running : 0;

    final List<DVShorebirdPatch> all = patches(target);
    final List<DVShorebirdPatch> live = <DVShorebirdPatch>[
      for (final DVShorebirdPatch p in all)
        if (!p.rolledBack && p.channel == channel) p,
    ];
    final DVShorebirdPatch? newest = live.isEmpty ? null : live.last;
    final bool available = newest != null && newest.number > current;
    final String base = downloadBase.toString().replaceAll(RegExp(r'/+$'), '');
    return <String, Object?>{
      'patch_available': available,
      'patch': available
          ? <String, Object?>{
              'number': newest.number,
              'hash': newest.hash,
              'download_url':
                  '$base/patches/${target._segments.join('/')}/${newest.number}',
              'hash_signature': ?newest.hashSignature,
            }
          : null,
      'rolled_back_patch_numbers': <int>[
        for (final DVShorebirdPatch p in all)
          if (p.rolledBack) p.number,
      ],
    };
  }

  /// Serves the check, downloads and events under [prefix]. Returns false,
  /// having written nothing, for a request that is not one of them.
  Future<bool> handle(HttpRequest request, {String prefix = ''}) async {
    final String path = request.uri.path;
    if (!path.startsWith('$prefix/')) return false;
    final String rest = path.substring(prefix.length);
    final HttpResponse response = request.response;

    if (request.method == 'POST' && rest == '/api/v1/patches/check') {
      final Map<String, Object?> body;
      try {
        final Object? decoded = jsonDecode(await utf8.decodeStream(request));
        if (decoded is! Map) throw const FormatException('not an object');
        body = decoded.cast<String, Object?>();
        final String host = request.headers.host ?? 'localhost';
        final int port = request.headers.port ?? request.connectionInfo!.localPort;
        final Map<String, Object?> answer = check(
          body,
          downloadBase: Uri(
            scheme: 'http',
            host: host,
            port: port,
            path: prefix,
          ),
        );
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(answer));
      } on FormatException catch (error) {
        response.statusCode = HttpStatus.badRequest;
        response.write(error.message);
      }
      await response.close();
      return true;
    }

    if (request.method == 'POST' && rest == '/api/v1/patches/events') {
      await request.drain<void>();
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return true;
    }

    if (request.method == 'GET' && rest.startsWith('/patches/')) {
      final List<String> parts = rest.substring('/patches/'.length).split('/');
      if (parts.length != 5) return false;
      final File file;
      try {
        file = File('${_dir(parts)}${Platform.pathSeparator}patch.bin');
      } on FormatException {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return true;
      }
      if (!file.existsSync()) return false;
      final int length = file.lengthSync();
      final Match? range = RegExp(
        r'^bytes=(\d+)-$',
      ).firstMatch(request.headers.value('range') ?? '');
      final int start = range == null ? 0 : int.parse(range.group(1)!);
      if (start > 0 && start < length) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('content-range', 'bytes $start-${length - 1}/$length');
      }
      final int from = start < length ? start : 0;
      response.headers.contentType = ContentType.binary;
      response.contentLength = length - from;
      await response.addStream(file.openRead(from));
      await response.close();
      return true;
    }
    return false;
  }
}
