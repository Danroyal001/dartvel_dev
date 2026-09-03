/// The federated module manifest, and the parent's decision to trust it.
///
/// A federated module is built and deployed by somebody else and mounted into
/// this application's route tree. The manifest is the only thing between "a
/// partner ships a section of our site" and "a partner ships whatever they
/// like into our site", so what matters here is not accepting a good manifest
/// -- it is refusing the ones that are wrong in ways that look right.
///
/// Every refusal below is a real way in, and every one of them is quiet: the
/// document parses, a signature checks out against something, and the parent
/// mounts it. A manifest edited after signing, a valid signature by somebody
/// the parent never trusted, yesterday's manifest replayed to bring back a
/// vulnerability that was fixed, a module that is genuinely signed and is not
/// the module being mounted.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../notifications/web_push.dart'
    show dvWebPushBase64Decode, dvWebPushBase64Encode;
import '../notifications/web_push_vapid.dart' show dvWebPushSignEs256;

/// What a federated module publishes about itself.
class DVModuleManifest {
  const DVModuleManifest({
    required this.id,
    required this.version,
    required this.routes,
    this.capabilities = const <String>{},
    this.assets = const <String, String>{},
    this.shell = 'inherit',
    this.auth = 'inherit',
    this.theme = 'inherit',
    this.data = 'shared',
    this.publicFunctions = const <String>[],
    this.publicSignals = const <String>[],
    this.requiresParent,
    this.location,
  });

  /// The module's identifier, which is also what the parent mounts it as.
  final String id;
  final String version;

  /// The module's own routes, relative to wherever it is mounted.
  final List<String> routes;

  /// What the module needs the target to be able to do.
  final Set<String> capabilities;

  /// Asset keys and the paths behind them.
  final Map<String, String> assets;

  final String shell;
  final String auth;
  final String theme;
  final String data;

  final List<String> publicFunctions;
  final List<String> publicSignals;

  /// A version constraint on the parent, such as `>=3.0.0`.
  final String? requiresParent;

  /// Where the built module is served from.
  final String? location;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'version': version,
        'routes': routes,
        'capabilities': capabilities.toList()..sort(),
        'assets': assets,
        'shell': shell,
        'auth': auth,
        'theme': theme,
        'data': data,
        'publicFunctions': publicFunctions,
        'publicSignals': publicSignals,
        'requiresParent': requiresParent,
        'location': location,
      };

  static DVModuleManifest fromJson(Map<Object?, Object?> map) {
    List<String> strings(Object? value) => <String>[
          for (final Object? v in value is List ? value : const <Object?>[]) '$v',
        ];
    return DVModuleManifest(
      id: '${map['id']}',
      version: '${map['version']}',
      routes: strings(map['routes']),
      capabilities: strings(map['capabilities']).toSet(),
      assets: <String, String>{
        if (map['assets'] is Map)
          for (final MapEntry<Object?, Object?> e
              in (map['assets']! as Map<Object?, Object?>).entries)
            '${e.key}': '${e.value}',
      },
      shell: '${map['shell'] ?? 'inherit'}',
      auth: '${map['auth'] ?? 'inherit'}',
      theme: '${map['theme'] ?? 'inherit'}',
      data: '${map['data'] ?? 'shared'}',
      publicFunctions: strings(map['publicFunctions']),
      publicSignals: strings(map['publicSignals']),
      requiresParent: map['requiresParent']?.toString(),
      location: map['location']?.toString(),
    );
  }

  /// The bytes that are signed.
  ///
  /// Canonical, with the keys in a fixed order, because the signature has to
  /// be over a form both sides can reproduce exactly. Signing the document as
  /// it happened to be serialised would make a re-indented manifest
  /// unverifiable, and verifying a re-serialisation of what was parsed would
  /// mean the signature covers what the parser understood rather than what
  /// the publisher wrote -- which is the gap every "extra field" attack goes
  /// through.
  String canonical() => jsonEncode(_sorted(toJson()));

  static Object? _sorted(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final String key in value.keys.map((Object? k) => '$k').toList()
          ..sort())
          key: _sorted(value[key]),
      };
    }
    if (value is List) return <Object?>[for (final Object? v in value) _sorted(v)];
    return value;
  }
}

/// The parent's verdict on a manifest.
class DVModuleTrust {
  const DVModuleTrust._(this.accepted, this.reason, this.manifest);

  const DVModuleTrust.refused(String reason) : this._(false, reason, null);

  final bool accepted;

  /// Why, in terms an operator can act on. A refusal that says only "invalid"
  /// sends somebody to read logs on the wrong machine.
  final String reason;

  /// The manifest, once it has been trusted. Null on a refusal, so a caller
  /// cannot mount what was refused by reading past the verdict.
  final DVModuleManifest? manifest;
}

/// The public key matching [privateKey], as the parent stores it.
String dvModuleSigningPublicKey(Uint8List privateKey) {
  final ECDomainParameters domain = ECDomainParameters('prime256v1');
  final BigInt d = _bigIntOf(privateKey);
  final ECPoint q = (domain.G * d)!;
  return dvWebPushBase64Encode(q.getEncoded(false));
}

/// A signed manifest document, as the module publishes it.
///
/// The signature is over [DVModuleManifest.canonical], and the document
/// carries the manifest alongside it so a parent can read what it is being
/// asked to trust before deciding whether to trust it.
String dvSignModuleManifest(
  DVModuleManifest manifest, {
  required Uint8List privateKey,
  required String keyId,
}) {
  final Uint8List signature =
      dvWebPushSignEs256(utf8.encode(manifest.canonical()), privateKey);
  return jsonEncode(<String, Object?>{
    'manifest': manifest.toJson(),
    'keyId': keyId,
    'signature': dvWebPushBase64Encode(signature),
  });
}

/// Whether the parent should mount the module [document] describes.
///
/// [trustedKeys] maps a key id to the public key the parent has for it. An
/// empty map refuses everything: a parent with no configured keys has not
/// been configured, and the safe reading of "no keys are trusted" is that
/// none are.
///
/// [lastAcceptedVersion] is the newest version this parent has already
/// mounted. An older one is refused even though it is validly signed: a
/// manifest does not expire, so replaying an old one is how a vulnerability
/// that was fixed comes back.
DVModuleTrust dvVerifyModuleManifest(
  String document, {
  required Map<String, String> trustedKeys,
  required String expectedId,
  String? lastAcceptedVersion,
  String? parentVersion,
  String? mountPath,
  Set<String> parentRoutes = const <String>{},
  Set<String>? targetCapabilities,
}) {
  Object? parsed;
  try {
    parsed = jsonDecode(document);
  } on Object {
    return const DVModuleTrust.refused(
      'The module manifest is not JSON, so nothing in it can be trusted.',
    );
  }
  if (parsed is! Map) {
    return const DVModuleTrust.refused(
      'The module manifest is not an object.',
    );
  }
  final Object? body = parsed['manifest'];
  final Object? keyId = parsed['keyId'];
  final Object? signature = parsed['signature'];
  if (body is! Map || keyId is! String || signature is! String) {
    return const DVModuleTrust.refused(
      'A signed module manifest carries a manifest, a keyId and a signature; '
      'this one does not.',
    );
  }

  final DVModuleManifest manifest = DVModuleManifest.fromJson(body);

  final String? publicKey = trustedKeys[keyId];
  if (publicKey == null) {
    return DVModuleTrust.refused(
      'The manifest names key "$keyId", which this application does not '
      'trust. Its signature was not checked.',
    );
  }
  if (!_verifies(manifest.canonical(), signature, publicKey)) {
    // Deliberately one message for "edited after signing" and "signed by
    // somebody else": from here they are the same fact -- these bytes were
    // not signed by that key -- and guessing which would be a guess.
    return DVModuleTrust.refused(
      'The manifest\'s signature does not match key "$keyId", so it was '
      'either signed by somebody else or edited after it was signed.',
    );
  }

  if (manifest.id != expectedId) {
    return DVModuleTrust.refused(
      'The manifest is for module "${manifest.id}", and this application is '
      'mounting "$expectedId".',
    );
  }

  if (lastAcceptedVersion != null &&
      _compareVersions(manifest.version, lastAcceptedVersion) < 0) {
    return DVModuleTrust.refused(
      'The manifest is version ${manifest.version} and this application has '
      'already accepted $lastAcceptedVersion. An older manifest is signed '
      'just as validly as a newer one, so it is refused rather than rolled '
      'back to.',
    );
  }

  final String? requires = manifest.requiresParent;
  if (requires != null && requires.isNotEmpty && parentVersion != null) {
    if (!_satisfies(parentVersion, requires)) {
      return DVModuleTrust.refused(
        'The module needs a parent $requires and this one is $parentVersion.',
      );
    }
  }

  if (targetCapabilities != null) {
    final List<String> missing = manifest.capabilities
        .where((String c) => !targetCapabilities.contains(c))
        .toList()
      ..sort();
    if (missing.isNotEmpty) {
      return DVModuleTrust.refused(
        'The module needs ${missing.join(', ')}, which this target does not '
        'provide.',
      );
    }
  }

  if (parentRoutes.isNotEmpty) {
    final String base = (mountPath ?? '').replaceAll(RegExp(r'/+$'), '');
    final List<String> collisions = <String>[
      for (final String route in manifest.routes)
        if (parentRoutes.contains('$base$route')) '$base$route',
    ];
    if (collisions.isNotEmpty) {
      return DVModuleTrust.refused(
        'Mounted at "$base" the module would answer for '
        '${collisions.join(', ')}, which this application already serves.',
      );
    }
  }

  return DVModuleTrust._(true, 'accepted', manifest);
}

bool _verifies(String canonical, String signature, String publicKey) {
  final Uint8List raw;
  final Uint8List key;
  try {
    raw = dvWebPushBase64Decode(signature);
    key = dvWebPushBase64Decode(publicKey);
  } on Object {
    return false;
  }
  if (raw.length != 64) return false;
  try {
    final ECDomainParameters domain = ECDomainParameters('prime256v1');
    final ECDSASigner verifier = ECDSASigner(SHA256Digest())
      ..init(
        false,
        PublicKeyParameter<ECPublicKey>(
          ECPublicKey(domain.curve.decodePoint(key), domain),
        ),
      );
    return verifier.verifySignature(
      Uint8List.fromList(utf8.encode(canonical)),
      ECSignature(_bigIntOf(raw.sublist(0, 32)), _bigIntOf(raw.sublist(32))),
    );
  } on Object {
    // A key that is not a point on the curve, a signature that decodes to
    // nonsense: not an exception the caller can do anything with, and
    // "unverified" is the honest answer to all of them.
    return false;
  }
}

BigInt _bigIntOf(List<int> bytes) {
  var result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// -1, 0 or 1 comparing two dotted versions, prerelease and build ignored.
int _compareVersions(String a, String b) {
  List<int> parts(String v) => <int>[
        for (final String p in v.split(RegExp('[-+]')).first.split('.'))
          int.tryParse(p) ?? 0,
      ];
  final List<int> left = parts(a);
  final List<int> right = parts(b);
  for (var i = 0; i < (left.length > right.length ? left.length : right.length); i++) {
    final int l = i < left.length ? left[i] : 0;
    final int r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

/// Whether [version] satisfies a constraint such as `>=3.0.0` or `^2.1.0`.
bool _satisfies(String version, String constraint) {
  for (final String part in constraint.split(RegExp(r'\s+'))) {
    if (part.isEmpty) continue;
    final RegExpMatch? m = RegExp(r'^(\^|>=|<=|>|<|=)?\s*(.+)$').firstMatch(part);
    if (m == null) continue;
    final String op = m.group(1) ?? '=';
    final String want = m.group(2)!;
    final int c = _compareVersions(version, want);
    final bool ok = switch (op) {
      '>=' => c >= 0,
      '<=' => c <= 0,
      '>' => c > 0,
      '<' => c < 0,
      // A caret allows anything up to the next major, which is the only
      // reading that does not let a module declare compatibility with a
      // parent that has since broken it.
      '^' => c >= 0 && _compareVersions(version, _nextMajor(want)) < 0,
      _ => c == 0,
    };
    if (!ok) return false;
  }
  return true;
}

String _nextMajor(String version) {
  final List<String> parts = version.split('.');
  final int major = int.tryParse(parts.first) ?? 0;
  return '${major + 1}.0.0';
}
