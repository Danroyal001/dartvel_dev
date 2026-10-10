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
/// Dartvel's own endpoints are under `<prefix>/_dartvel/`: release, publish,
/// rollout and rollback, which `dartvel updates release|patch|rollout|rollback
/// --patch-source <url>` call. They answer only a source given a
/// [DVShorebirdPatchSource.publishToken], and only a request bearing it: a
/// patch is code that every device on the release runs.
///
/// Hosting patches for other people adds three things, all here so the
/// web-server binary and Dartvel Cloud serve the same source:
///
///  * **staged rollout** -- a patch reaches [DVShorebirdPatch.rolloutPercent]
///    of the devices on its release, chosen from the updater's `client_id`
///    by [DVUpdateRollout], so a device answers the same at every check and
///    a rollout that grows keeps every device it had;
///  * **signed releases** -- a release registered with the public key it was
///    built with takes only patches whose `hash_signature` verifies against
///    it, the same check its devices make ([DVPatchSigning]);
///  * **install counting** -- the updater's `__patch_install__` events,
///    counted once per device per patch into the calendar month (UTC) the
///    server received them, with [DVShorebirdPatchSource.onInstall] called
///    for each counted install: the hook metering and billing hang off.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../http/wintercg.dart';
import 'patch_signing.dart';
import 'rollout.dart';

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
    this.rolloutPercent = 100,
  });

  final int number;

  /// Hex SHA-256 of the patched file the diff produces, which the updater
  /// checks before it will boot it.
  final String hash;
  final String channel;
  final bool rolledBack;
  final String? hashSignature;

  /// The share of the release's devices this patch is offered to, 0 to 100.
  final int rolloutPercent;

  DVShorebirdPatch copyWith({
    bool? rolledBack,
    int? rolloutPercent,
    String? channel,
  }) => DVShorebirdPatch(
    number: number,
    hash: hash,
    channel: channel ?? this.channel,
    rolledBack: rolledBack ?? this.rolledBack,
    hashSignature: hashSignature,
    rolloutPercent: rolloutPercent ?? this.rolloutPercent,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'number': number,
    'hash': hash,
    'channel': channel,
    'rolled_back': rolledBack,
    'hash_signature': ?hashSignature,
    'rollout_percent': rolloutPercent,
  };

  factory DVShorebirdPatch.fromJson(Map<String, Object?> json) =>
      DVShorebirdPatch(
        number: json['number']! as int,
        hash: json['hash']! as String,
        channel: json['channel']! as String,
        rolledBack: json['rolled_back'] == true,
        hashSignature: json['hash_signature'] as String?,
        // A patch published before rollouts existed reached everyone.
        rolloutPercent: json['rollout_percent'] is int
            ? json['rollout_percent']! as int
            : 100,
      );
}

/// A release a patch source knows about: the key its devices verify
/// patches with, when it was built with one.
class DVShorebirdRelease {
  const DVShorebirdRelease({
    required this.appId,
    required this.releaseVersion,
    required this.platform,
    this.patchPublicKey,
  });

  final String appId;
  final String releaseVersion;
  final String platform;

  /// Base64 DER PKCS#1, as the release's shorebird.yaml carries it. Null for
  /// a release built without signing, whose devices take unsigned patches.
  final String? patchPublicKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'app_id': appId,
    'release_version': releaseVersion,
    'platform': platform,
    'patch_public_key': ?patchPublicKey,
  };

  factory DVShorebirdRelease.fromJson(Map<String, Object?> json) =>
      DVShorebirdRelease(
        appId: json['app_id']! as String,
        releaseVersion: json['release_version']! as String,
        platform: json['platform']! as String,
        patchPublicKey: json['patch_public_key'] as String?,
      );
}

/// One counted install: a device that booted a patch and said so.
class DVShorebirdPatchInstall {
  const DVShorebirdPatchInstall({
    required this.appId,
    required this.releaseVersion,
    required this.platform,
    required this.arch,
    required this.patchNumber,
    required this.clientId,
    required this.at,
  });

  final String appId;
  final String releaseVersion;
  final String platform;
  final String arch;
  final int patchNumber;

  /// The updater's random per-install id, not a device identifier.
  final String clientId;

  /// When the server received it, which decides its month.
  final DateTime at;

  /// The calendar month (UTC) it is counted in, `YYYY-MM`.
  String get month => dvPatchInstallMonth(at);

  /// What makes two reports the same install.
  String get _key => '$releaseVersion/$platform/$patchNumber/$clientId';

  Map<String, Object?> toJson() => <String, Object?>{
    'release_version': releaseVersion,
    'platform': platform,
    'arch': arch,
    'patch_number': patchNumber,
    'client_id': clientId,
    'at': at.toUtc().toIso8601String(),
  };
}

/// The month an install made at [at] is counted in, `YYYY-MM` in UTC.
String dvPatchInstallMonth(DateTime at) {
  final DateTime utc = at.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}';
}

/// Installs of one app in one month.
class DVPatchInstallUsage {
  const DVPatchInstallUsage({
    required this.appId,
    required this.month,
    required this.byPatch,
  });

  final String appId;

  /// `YYYY-MM`, UTC.
  final String month;

  /// Installs by `release/platform/patch`.
  final Map<String, int> byPatch;

  int get total => byPatch.values.fold(0, (int a, int b) => a + b);
}

/// Called once for each install counted. Metering records it from here.
typedef DVPatchInstallHook = void Function(DVShorebirdPatchInstall install);

/// Whether patches for [target] may be offered right now: false stops new
/// patches reaching devices (a hosted plan out of included installs, say)
/// while rollbacks still reach them.
typedef DVPatchOfferGate = bool Function(DVShorebirdPatchTarget target);

class DVShorebirdPatchSource {
  DVShorebirdPatchSource(
    this.root, {
    this.publishToken,
    this.onInstall,
    this.mayOffer,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The directory patches are kept in.
  final String root;

  /// What a publish or rollback request must bear as `Authorization: Bearer`.
  /// Null or empty is a source that serves and never publishes.
  final String? publishToken;

  /// Called for every install counted.
  final DVPatchInstallHook? onInstall;

  /// Asked before a patch is offered; null offers always.
  final DVPatchOfferGate? mayOffer;

  final DateTime Function() _clock;

  /// The name under [root] the install ledger is kept in, which is therefore
  /// not an app id.
  static const String ledgerName = '_dartvel';

  static final RegExp _segment = RegExp(r'^[A-Za-z0-9._+-]{1,128}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  String _dir(List<String> segments) {
    for (final String s in segments) {
      if (!_segment.hasMatch(s) || s == '.' || s == '..') {
        throw FormatException('"$s" is not a valid patch path component.');
      }
    }
    if (segments.isNotEmpty && segments.first == ledgerName) {
      throw const FormatException(
        '"$ledgerName" is where installs are counted, not an app id.',
      );
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

  File _releaseFile(String appId, String releaseVersion, String platform) =>
      File(
        '${_dir(<String>[appId, releaseVersion, platform])}'
        '${Platform.pathSeparator}release.json',
      );

  /// Records a release, and the key its devices verify patches with. From
  /// then on [publish] takes for it only patches signed by that key.
  ///
  /// A release registered with a key cannot be registered again without one:
  /// its devices would still refuse every unsigned patch.
  DVShorebirdRelease registerRelease({
    required String appId,
    required String releaseVersion,
    required String platform,
    String? patchPublicKey,
  }) {
    final String? key = patchPublicKey == null || patchPublicKey.trim().isEmpty
        ? null
        : patchPublicKey.trim();
    if (key != null) {
      try {
        // A key the updater could not read either is refused now, not when
        // the first patch is.
        DVPatchSigning.verifyHash('0' * 64, '', key);
      } on DVPatchSigningException catch (error) {
        throw FormatException('The release key is unusable: ${error.message}');
      }
    }
    final DVShorebirdRelease? existing = releaseRecord(
      appId: appId,
      releaseVersion: releaseVersion,
      platform: platform,
    );
    if (existing?.patchPublicKey != null && existing!.patchPublicKey != key) {
      throw const FormatException(
        'This release was registered with a signing key, and its devices '
        'verify every patch against that key. Make a new release to change '
        'or drop it.',
      );
    }
    final DVShorebirdRelease release = DVShorebirdRelease(
      appId: appId,
      releaseVersion: releaseVersion,
      platform: platform,
      patchPublicKey: key,
    );
    final File file = _releaseFile(appId, releaseVersion, platform);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(release.toJson()));
    return release;
  }

  /// The release registered for [appId] [releaseVersion] on [platform], or
  /// null when none was.
  DVShorebirdRelease? releaseRecord({
    required String appId,
    required String releaseVersion,
    required String platform,
  }) {
    final File file = _releaseFile(appId, releaseVersion, platform);
    if (!file.existsSync()) return null;
    return DVShorebirdRelease.fromJson(
      (jsonDecode(file.readAsStringSync()) as Map<Object?, Object?>)
          .cast<String, Object?>(),
    );
  }

  /// Stores [diff] as the next patch for [target].
  ///
  /// [patchedHash] is the hex SHA-256 of the file the diff turns the release
  /// into -- not of the diff -- because that is what the updater verifies.
  /// For a release registered with a key, [hashSignature] must be that key's
  /// signature of [patchedHash]; anything else is refused with a
  /// [FormatException], since every device would refuse it too.
  DVShorebirdPatch publish(
    DVShorebirdPatchTarget target, {
    required List<int> diff,
    required String patchedHash,
    String channel = 'stable',
    String? hashSignature,
    int rolloutPercent = 100,
  }) {
    if (!_sha256.hasMatch(patchedHash)) {
      throw const FormatException('The hash is a hex SHA-256.');
    }
    _dir(<String>[channel]);
    _dir(target._segments);
    if (rolloutPercent < 0 || rolloutPercent > 100) {
      throw const FormatException('A rollout is 0 to 100 per cent.');
    }
    final String? key = releaseRecord(
      appId: target.appId,
      releaseVersion: target.releaseVersion,
      platform: target.platform,
    )?.patchPublicKey;
    if (key != null) {
      if (hashSignature == null || hashSignature.isEmpty) {
        throw const FormatException(
          'This release was built with a signing key, so its devices refuse '
          'unsigned patches. Sign the patch with the release\'s private key.',
        );
      }
      if (!DVPatchSigning.verifyHash(patchedHash, hashSignature, key)) {
        throw const FormatException(
          'The patch\'s signature does not verify against the key this '
          'release was built with, so every device would refuse it.',
        );
      }
    }
    final List<DVShorebirdPatch> existing = patches(target);
    final DVShorebirdPatch patch = DVShorebirdPatch(
      number: existing.isEmpty ? 1 : existing.last.number + 1,
      hash: patchedHash,
      channel: channel,
      rolledBack: false,
      hashSignature: hashSignature,
      rolloutPercent: rolloutPercent,
    );
    final Directory dir = Directory(
      _dir(<String>[...target._segments, '${patch.number}']),
    )..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}patch.bin')
        .writeAsBytesSync(diff);
    File('${dir.path}${Platform.pathSeparator}patch.json')
        .writeAsStringSync(jsonEncode(patch.toJson()));
    return patch;
  }

  DVShorebirdPatch _update(
    DVShorebirdPatchTarget target,
    int number,
    DVShorebirdPatch Function(DVShorebirdPatch patch) change,
  ) {
    final File meta = File(
      '${_dir(<String>[...target._segments, '$number'])}'
      '${Platform.pathSeparator}patch.json',
    );
    if (!meta.existsSync()) {
      throw StateError('There is no patch $number for this release.');
    }
    final DVShorebirdPatch patch = change(
      DVShorebirdPatch.fromJson(
        (jsonDecode(meta.readAsStringSync()) as Map<Object?, Object?>)
            .cast<String, Object?>(),
      ),
    );
    meta.writeAsStringSync(jsonEncode(patch.toJson()));
    return patch;
  }

  /// Marks patch [number] of [target] rolled back. Devices running it drop it
  /// at their next check.
  void rollBack(DVShorebirdPatchTarget target, int number) {
    _update(
      target,
      number,
      (DVShorebirdPatch p) => p.copyWith(rolledBack: true),
    );
  }

  /// Sets the share of devices patch [number] of [target] is offered to.
  void setRollout(DVShorebirdPatchTarget target, int number, int percent) {
    if (percent < 0 || percent > 100) {
      throw const FormatException('A rollout is 0 to 100 per cent.');
    }
    _update(
      target,
      number,
      (DVShorebirdPatch p) => p.copyWith(rolloutPercent: percent),
    );
  }

  /// Applies [change] to patch [number] on every architecture of the release
  /// that has it, and returns those architectures. Throws [StateError] when
  /// none does.
  List<String> _acrossRelease(
    String appId,
    String releaseVersion,
    String platform,
    int number,
    void Function(DVShorebirdPatchTarget target) change,
  ) {
    final List<String> changed = <String>[];
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
        change(target);
        changed.add(arch);
      }
    }
    if (changed.isEmpty) {
      throw StateError(
        'There is no patch $number for $appId $releaseVersion on $platform.',
      );
    }
    return changed;
  }

  /// Rolls back patch [number] on every architecture of the release that has
  /// it, and returns those architectures. Throws [StateError] when none does.
  List<String> rollBackRelease({
    required String appId,
    required String releaseVersion,
    required String platform,
    required int number,
  }) => _acrossRelease(
    appId,
    releaseVersion,
    platform,
    number,
    (DVShorebirdPatchTarget t) => rollBack(t, number),
  );

  /// Sets patch [number]'s rollout to [percent] on every architecture of the
  /// release that has it, and returns those architectures.
  List<String> rolloutRelease({
    required String appId,
    required String releaseVersion,
    required String platform,
    required int number,
    required int percent,
  }) {
    if (percent < 0 || percent > 100) {
      throw const FormatException('A rollout is 0 to 100 per cent.');
    }
    return _acrossRelease(
      appId,
      releaseVersion,
      platform,
      number,
      (DVShorebirdPatchTarget t) => setRollout(t, number, percent),
    );
  }

  /// Whether the device [clientId] is inside [patch]'s rollout.
  ///
  /// The patch is part of what is hashed, so the devices that find the first
  /// patch of a release are not also the first to find every later one.
  static bool reaches(
    DVShorebirdPatch patch, {
    required String releaseVersion,
    required String clientId,
  }) => DVUpdateRollout.includes(
    deviceId: clientId,
    version: '$releaseVersion#${patch.number}',
    percent: patch.rolloutPercent,
  );

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
    final String clientId = request['client_id'] is String
        ? request['client_id']! as String
        : '';

    final List<DVShorebirdPatch> all = patches(target);
    final bool offering = mayOffer?.call(target) ?? true;
    // Patches are each a diff from the release, so the newest patch a device
    // is inside the rollout of is the one it should run, even when a newer
    // one is still on its way to other devices.
    final List<DVShorebirdPatch> live = <DVShorebirdPatch>[
      if (offering)
        for (final DVShorebirdPatch p in all)
          if (!p.rolledBack &&
              p.channel == channel &&
              reaches(
                p,
                releaseVersion: target.releaseVersion,
                clientId: clientId,
              ))
            p,
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
      try {
        final Object? decoded = jsonDecode(
          utf8.decode(await request.body.bytes()),
        );
        if (decoded is! Map) throw const FormatException('not an object');
        try {
          recordEvent(decoded.cast<String, Object?>());
        } on FormatException {
          // Answered as received and not counted: the updater does not act
          // on the answer, and an event that names no release is no install.
        }
        return Response(HttpStatus.noContent);
      } on FormatException catch (error) {
        return Response.text(error.message, status: HttpStatus.badRequest);
      }
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

    if (request.method == 'POST' && rest == '/_dartvel/rollout') {
      return _authorized(request) ?? await _rollout(request);
    }

    if (request.method == 'POST' && rest == '/_dartvel/release') {
      return _authorized(request) ?? await _registerRelease(request);
    }
    return null;
  }

  // ---- Installs ------------------------------------------------------------

  /// The event type the updater reports a booted patch with
  /// (`library/src/events.rs` in shorebirdtech/updater). Failures, downloads
  /// and update failures are reported under other types and are not
  /// installs.
  static const String installEventType = '__patch_install__';

  File _ledger(String appId, String month) => File(
    <String>[
      root,
      ledgerName,
      'installs',
      appId,
      '$month.jsonl',
    ].join(Platform.pathSeparator),
  );

  /// Reads the updater's `{"event": {...}}` and counts it when it is an
  /// install not counted before. Returns the install counted, or null for
  /// another event type or a repeat.
  ///
  /// Throws [FormatException] for an event that is not in the updater's
  /// shape, or that names a release no patch path could.
  DVShorebirdPatchInstall? recordEvent(Map<String, Object?> body) {
    final Object? event = body['event'];
    if (event is! Map) throw const FormatException('The body has no event.');
    String field(String name) {
      final Object? value = event[name];
      if (value is! String || value.isEmpty) {
        throw FormatException('The event names no $name.');
      }
      return value;
    }

    final String type = field('type');
    final DVShorebirdPatchTarget target = DVShorebirdPatchTarget(
      appId: field('app_id'),
      releaseVersion: field('release_version'),
      platform: field('platform'),
      arch: field('arch'),
    );
    _dir(target._segments);
    final Object? number = event['patch_number'];
    if (number is! int || number < 1) {
      throw const FormatException('The event names no patch_number.');
    }
    final String clientId = field('client_id');
    if (type != installEventType) return null;

    final DVShorebirdPatchInstall install = DVShorebirdPatchInstall(
      appId: target.appId,
      releaseVersion: target.releaseVersion,
      platform: target.platform,
      arch: target.arch,
      patchNumber: number,
      clientId: clientId,
      at: _clock().toUtc(),
    );
    final File ledger = _ledger(target.appId, install.month);
    if (ledger.existsSync()) {
      for (final String line in ledger.readAsLinesSync()) {
        if (line.isEmpty) continue;
        final Map<Object?, Object?> seen = jsonDecode(line) as Map;
        if ('${seen['release_version']}/${seen['platform']}/'
                '${seen['patch_number']}/${seen['client_id']}' ==
            install._key) {
          return null;
        }
      }
    } else {
      ledger.parent.createSync(recursive: true);
    }
    ledger.writeAsStringSync(
      '${jsonEncode(install.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    onInstall?.call(install);
    return install;
  }

  /// [appId]'s counted installs in [month] (`YYYY-MM`, UTC), the current
  /// month when null.
  DVPatchInstallUsage installUsage(String appId, {String? month}) {
    _dir(<String>[appId]);
    final String period = month ?? dvPatchInstallMonth(_clock());
    final Map<String, int> byPatch = <String, int>{};
    final File ledger = _ledger(appId, period);
    if (ledger.existsSync()) {
      for (final String line in ledger.readAsLinesSync()) {
        if (line.isEmpty) continue;
        final Map<Object?, Object?> seen = jsonDecode(line) as Map;
        final String key =
            '${seen['release_version']}/${seen['platform']}/'
            '${seen['patch_number']}';
        byPatch[key] = (byPatch[key] ?? 0) + 1;
      }
    }
    return DVPatchInstallUsage(appId: appId, month: period, byPatch: byPatch);
  }

  /// Installs counted in [month] (the current one when null) across every
  /// app this source serves: what a hosted project is billed on.
  int installTotal({String? month}) {
    final Directory installs = Directory(
      <String>[root, ledgerName, 'installs'].join(Platform.pathSeparator),
    );
    if (!installs.existsSync()) return 0;
    int total = 0;
    for (final Directory app in installs.listSync().whereType<Directory>()) {
      total += installUsage(
        app.uri.pathSegments.lastWhere((String s) => s.isNotEmpty),
        month: month,
      ).total;
    }
    return total;
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
    final Match? range = RegExp(r'^bytes=(\d+)-$')
        .firstMatch(request.headers.get('range') ?? '');
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
        rolloutPercent: q['rollout'] == null || q['rollout']!.isEmpty
            ? 100
            : int.tryParse(q['rollout']!) ?? -1,
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

  Future<Map<Object?, Object?>> _jsonBody(Request request) async {
    final Object? decoded = jsonDecode(utf8.decode(await request.body.bytes()));
    if (decoded is! Map) throw const FormatException('not an object');
    return decoded;
  }

  Future<Response> _rollout(Request request) async {
    try {
      final Map<Object?, Object?> decoded = await _jsonBody(request);
      final Object? number = decoded['number'];
      final Object? percent = decoded['percent'];
      final Object? app = decoded['app_id'];
      final Object? release = decoded['release_version'];
      final Object? platform = decoded['platform'];
      if (number is! int ||
          percent is! int ||
          app is! String ||
          release is! String ||
          platform is! String) {
        throw const FormatException(
          'A rollout names app_id, release_version, platform, number and '
          'percent.',
        );
      }
      final List<String> changed = rolloutRelease(
        appId: app,
        releaseVersion: release,
        platform: platform,
        number: number,
        percent: percent,
      );
      return Response.json(<String, Object?>{
        'number': number,
        'percent': percent,
        'architectures': changed,
      });
    } on FormatException catch (error) {
      return Response.text(error.message, status: HttpStatus.badRequest);
    } on StateError catch (error) {
      return Response.text(error.message, status: HttpStatus.notFound);
    }
  }

  Future<Response> _registerRelease(Request request) async {
    try {
      final Map<Object?, Object?> decoded = await _jsonBody(request);
      final Object? app = decoded['app_id'];
      final Object? release = decoded['release_version'];
      final Object? platform = decoded['platform'];
      final Object? key = decoded['patch_public_key'];
      if (app is! String ||
          release is! String ||
          platform is! String ||
          (key != null && key is! String)) {
        throw const FormatException(
          'A release names app_id, release_version and platform, and '
          'optionally patch_public_key.',
        );
      }
      final DVShorebirdRelease registered = registerRelease(
        appId: app,
        releaseVersion: release,
        platform: platform,
        patchPublicKey: key as String?,
      );
      return Response.json(registered.toJson(), status: HttpStatus.created);
    } on FormatException catch (error) {
      return Response.text(error.message, status: HttpStatus.badRequest);
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
