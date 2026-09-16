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
///
/// Two more endpoints are Dartvel's own, under `<prefix>/_dartvel/`: publish
/// and rollback, which `dartvel updates patch --patch-source <url>` and
/// `dartvel updates rollback --patch-source <url>` call. They answer only a
/// source given a [DVShorebirdPatchSource.publishToken], and only a request
/// bearing it: a patch is code that every device on the release runs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../http/wintercg.dart';

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
  DVShorebirdPatchSource(this.root, {this.publishToken});

  /// The directory patches are kept in.
  final String root;

  /// What a publish or rollback request must bear as `Authorization: Bearer`.
  /// Null or empty is a source that serves and never publishes.
  final String? publishToken;

  static final RegExp _segment = RegExp(r'^[A-Za-z0-9._+-]{1,128}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

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
      final File meta = File(
        '${entry.path}${Platform.pathSeparator}patch.json',
      );
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

  /// The architectures [appId] [releaseVersion] has patches for on
  /// [platform], sorted.
  List<String> architectures({
    required String appId,
    required String releaseVersion,
    required String platform,
  }) {
    final Directory dir = Directory(
      _dir(<String>[appId, releaseVersion, platform]),
    );
    if (!dir.existsSync()) return const <String>[];
    return <String>[
      for (final FileSystemEntity entry in dir.listSync())
        if (entry is Directory)
          entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ]..sort();
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
    if (!_sha256.hasMatch(patchedHash)) {
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
    File(
      '${dir.path}${Platform.pathSeparator}patch.bin',
    ).writeAsBytesSync(diff);
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

  /// Rolls back patch [number] on every architecture of the release that has
  /// it, and returns those architectures. Throws [StateError] when none does.
  List<String> rollBackRelease({
    required String appId,
    required String releaseVersion,
    required String platform,
    required int number,
  }) {
    final List<String> rolled = <String>[];
    for (final String arch in architectures(
      appId: appId,
      releaseVersion: releaseVersion,
      platform: platform,
    )) {
      final DVShorebirdPatchTarget target = DVShorebirdPatchTarget(
        appId: appId,
        releaseVersion: releaseVersion,
        platform: platform,
        arch: arch,
      );
      if (patches(target).any((DVShorebirdPatch p) => p.number == number)) {
        rollBack(target, number);
        rolled.add(arch);
      }
    }
    if (rolled.isEmpty) {
      throw StateError(
        'There is no patch $number for $appId $releaseVersion on $platform.',
      );
    }
    return rolled;
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

  /// Serves the check, downloads, events, publishing and rollback under
  /// [prefix], in the Request and Response shape a Dartvel server answers
  /// in. Null, having read nothing, for a request that is none of them, so
  /// the application answers it.
  Future<Response?> respond(Request request, {String prefix = ''}) async {
    final String path = request.url.path;
    if (!path.startsWith('$prefix/')) return null;
    final String rest = path.substring(prefix.length);

    if (request.method == 'POST' && rest == '/api/v1/patches/check') {
      try {
        final Object? decoded = jsonDecode(
          utf8.decode(await request.body.bytes()),
        );
        if (decoded is! Map) throw const FormatException('not an object');
        return Response.json(
          check(
            decoded.cast<String, Object?>(),
            downloadBase: _base(request, prefix),
          ),
        );
      } on FormatException catch (error) {
        return Response.text(error.message, status: HttpStatus.badRequest);
      }
    }

    if (request.method == 'POST' && rest == '/api/v1/patches/events') {
      await request.body.bytes();
      return Response(HttpStatus.noContent);
    }

    if (request.method == 'GET' && rest.startsWith('/patches/')) {
      return _download(request, rest.substring('/patches/'.length));
    }

    if (request.method == 'POST' && rest == '/_dartvel/publish') {
      return _authorized(request) ?? await _publish(request);
    }

    if (request.method == 'POST' && rest == '/_dartvel/rollback') {
      return _authorized(request) ?? await _rollback(request);
    }
    return null;
  }

  /// Where the device reached this server: the Host it sent and the scheme a
  /// proxy in front reports, since a server behind TLS termination is
  /// reached over https and answers over http.
  Uri _base(Request request, String prefix) {
    final String? forwarded = request.headers
        .get('x-forwarded-proto')
        ?.split(',')
        .first
        .trim()
        .toLowerCase();
    final String scheme = forwarded == 'https' || forwarded == 'http'
        ? forwarded!
        : request.url.scheme;
    final String? host = request.headers.get('host');
    final Uri origin = host == null || host.isEmpty
        ? request.url
        : Uri.parse('$scheme://$host');
    return Uri(
      scheme: scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: prefix,
    );
  }

  Future<Response?> _download(Request request, String tail) async {
    final List<String> parts = tail.split('/');
    if (parts.length != 5) return null;
    final File file;
    try {
      file = File('${_dir(parts)}${Platform.pathSeparator}patch.bin');
    } on FormatException {
      return Response(HttpStatus.badRequest);
    }
    if (!file.existsSync()) return null;
    final int length = file.lengthSync();
    final Match? range = RegExp(
      r'^bytes=(\d+)-$',
    ).firstMatch(request.headers.get('range') ?? '');
    final int start = range == null ? 0 : int.parse(range.group(1)!);
    final Headers headers = Headers()
      ..set('content-type', 'application/octet-stream');
    int status = HttpStatus.ok;
    if (start > 0 && start < length) {
      status = HttpStatus.partialContent;
      headers.set('content-range', 'bytes $start-${length - 1}/$length');
    }
    final int from = start < length ? start : 0;
    headers.set('content-length', '${length - from}');
    return Response(status, headers: headers, body: file.openRead(from));
  }

  /// Null when [request] bears the publish token; the refusal otherwise.
  Response? _authorized(Request request) {
    final String? token = publishToken;
    if (token == null || token.isEmpty) {
      return Response.text(
        'This patch source publishes nothing: it was started without '
        'DARTVEL_UPDATES_TOKEN.',
        status: HttpStatus.forbidden,
      );
    }
    final String presented = request.headers.get('authorization') ?? '';
    if (!_constantTimeEquals(presented, 'Bearer $token')) {
      return Response.text(
        'Publishing needs the token this patch source was started with.',
        status: HttpStatus.unauthorized,
      );
    }
    return null;
  }

  Future<Response> _publish(Request request) async {
    final Map<String, String> q = request.url.queryParameters;
    final Uint8List diff = await request.body.bytesU8();
    try {
      if (diff.isEmpty) throw const FormatException('The patch is empty.');
      String field(String name) {
        final String? value = q[name];
        if (value == null || value.isEmpty) {
          throw FormatException('The publish names no $name.');
        }
        return value;
      }

      final DVShorebirdPatch patch = publish(
        DVShorebirdPatchTarget(
          appId: field('app_id'),
          releaseVersion: field('release_version'),
          platform: field('platform'),
          arch: field('arch'),
        ),
        diff: diff,
        patchedHash: field('hash'),
        channel: q['channel'] == null || q['channel']!.isEmpty
            ? 'stable'
            : q['channel']!,
        hashSignature: q['hash_signature'],
      );
      return Response.json(patch.toJson(), status: HttpStatus.created);
    } on FormatException catch (error) {
      return Response.text(error.message, status: HttpStatus.badRequest);
    }
  }

  Future<Response> _rollback(Request request) async {
    try {
      final Object? decoded = jsonDecode(
        utf8.decode(await request.body.bytes()),
      );
      if (decoded is! Map) throw const FormatException('not an object');
      final Object? number = decoded['number'];
      final Object? app = decoded['app_id'];
      final Object? release = decoded['release_version'];
      final Object? platform = decoded['platform'];
      if (number is! int ||
          app is! String ||
          release is! String ||
          platform is! String) {
        throw const FormatException(
          'A rollback names app_id, release_version, platform and number.',
        );
      }
      final List<String> rolled = rollBackRelease(
        appId: app,
        releaseVersion: release,
        platform: platform,
        number: number,
      );
      return Response.json(<String, Object?>{
        'number': number,
        'architectures': rolled,
      });
    } on FormatException catch (error) {
      return Response.text(error.message, status: HttpStatus.badRequest);
    } on StateError catch (error) {
      return Response.text(error.message, status: HttpStatus.notFound);
    }
  }

  /// Serves the patch source to a dart:io [request] under [prefix]. Returns
  /// false, having written nothing, for a request that is not one of its own.
  Future<bool> handle(HttpRequest request, {String prefix = ''}) async {
    if (!request.uri.path.startsWith('$prefix/')) return false;
    final Headers headers = Headers();
    request.headers.forEach((String name, List<String> values) {
      headers.set(name, values.join(', '));
    });
    final String host = request.headers.host ?? 'localhost';
    final int port = request.headers.port ?? request.connectionInfo!.localPort;
    final Response? answer = await respond(
      Request(
        method: request.method,
        url: Uri(
          scheme: 'http',
          host: host,
          port: port,
          path: request.uri.path,
          query: request.uri.hasQuery ? request.uri.query : null,
        ),
        headers: headers,
        bodyStream: request,
      ),
      prefix: prefix,
    );
    if (answer == null) return false;
    final HttpResponse response = request.response;
    response.statusCode = answer.status;
    answer.headers.singleValueMap.forEach((String name, String value) {
      if (name == 'content-length') {
        response.contentLength = int.parse(value);
      } else {
        response.headers.set(name, value);
      }
    });
    final Body? body = answer.body;
    if (body != null) await response.addStream(body.stream);
    await response.close();
    return true;
  }
}

bool _constantTimeEquals(String a, String b) {
  final List<int> x = utf8.encode(a);
  final List<int> y = utf8.encode(b);
  int difference = x.length ^ y.length;
  for (int i = 0; i < y.length; i++) {
    difference |= (i < x.length ? x[i] : 0) ^ y[i];
  }
  return difference == 0;
}
