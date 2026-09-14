/// The dev client's trust and compatibility rules.
///
/// A dev client is a shell -- an application with the engine and the native
/// bindings a project declares, and no application code -- that loads bundles
/// from a `dartvel dev` server it was paired with. Three things decide whether
/// a bundle it receives may run, and each guards a failure that is silent when
/// it goes wrong:
///
/// - **Who sealed it.** A pairing link carries the server's public key, and a
///   bundle is opened only with that key. Another machine on the same network
///   can serve something that renders perfectly well; it cannot sign it.
/// - **What it needs.** A shell records the binding manifest it was built
///   from. A bundle states the manifest of the project it came from, and one
///   that needs a binding the shell lacks is refused with `DV-DEVCLIENT-002`
///   naming every missing entry -- not loaded to fail at the call site.
/// - **Which build it is.** A dev bundle's version is its content digest. The
///   apply underneath is idempotent by version, so a fixed version would have
///   every edit after the first taken for the bundle already applied.
///
/// The envelope is not dev-client specific: OTA page bundles open with the
/// same function when a signing key is configured, because a second delivery
/// mechanism for the same bytes is a second thing to keep correct.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../notifications/web_push.dart'
    show DVWebPushKeyPair, dvWebPushBase64Decode, dvWebPushBase64Encode;
import '../notifications/web_push_vapid.dart' show dvWebPushSignEs256;

/// The format both the envelope and the statement inside it name.
const String dvSignedBundleFormat = 'dartvel-bundle-v1';

/// The dev client could not reach, or was not let in by, its server.
const String dvDevClientUnreachable = 'DV-DEVCLIENT-001';

/// A bundle needs a native binding the shell was not built with.
const String dvDevClientMissingBinding = 'DV-DEVCLIENT-002';

/// A dev-client artifact was submitted to a public track.
const String dvDevClientPublicTrack = 'DV-DEVCLIENT-003';

/// The path a dev server serves the current bundle on.
const String dvDevClientBundlePath = '/_dartvel/dev-client/bundle';

/// The scheme of a pairing link.
const String dvDevClientLinkScheme = 'dartvel-dev';

/// Why a bundle was not opened.
class DVSignedBundleException implements Exception {
  const DVSignedBundleException(this.message);

  final String message;

  @override
  String toString() => 'DVSignedBundleException: $message';
}

/// What a shell was built with, or what a bundle's project needs.
///
/// [bindings] are opaque, comparable entries: `plugin:<name>` for each native
/// plugin compiled for [target], and `dartvel_flutter@<version>` for the
/// runtime, whose bindings and renderer are compiled into the shell too. A
/// bundle loads when every entry it names is one the shell has; a shell with
/// more is fine, since a binding removed from the project is merely unused.
class DVDevClientManifest {
  const DVDevClientManifest({required this.target, required this.bindings});

  /// The platform the manifest was resolved for: `android`, `ios`, ...
  final String target;

  final List<String> bindings;

  /// [bindings] sorted and without duplicates.
  List<String> get normalizedBindings => (bindings.toSet().toList()..sort());

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'bindings': normalizedBindings,
  };

  factory DVDevClientManifest.fromJson(Map<String, Object?> json) {
    final Object? target = json['target'];
    if (target is! String || target.trim().isEmpty) {
      throw const FormatException(
        'A dev-client manifest names the target it was resolved for.',
      );
    }
    final Object? bindings = json['bindings'];
    if (bindings is! List || bindings.any((Object? b) => b is! String)) {
      throw const FormatException(
        'A dev-client manifest lists its bindings as strings.',
      );
    }
    return DVDevClientManifest(
      target: target,
      bindings: (bindings.cast<String>().toSet().toList()..sort()),
    );
  }
}

/// Why a shell will not load a bundle.
class DVDevClientRefusal {
  const DVDevClientRefusal({
    required this.code,
    required this.message,
    this.missing = const <String>[],
  });

  /// A code from the diagnostics registry.
  final String code;

  final String message;

  /// Every manifest entry the bundle needs and the shell lacks, sorted.
  final List<String> missing;

  @override
  String toString() => '$code: $message';
}

/// Null when a shell built from [shell] can run a bundle needing [bundle].
DVDevClientRefusal? dvDevClientCompatibility({
  required DVDevClientManifest shell,
  required DVDevClientManifest bundle,
}) {
  if (shell.target != bundle.target) {
    // Plugin lists are per platform, so two manifests for different targets
    // can agree by accident and still leave a native call unbound.
    return DVDevClientRefusal(
      code: dvDevClientMissingBinding,
      message:
          'This bundle was resolved for ${bundle.target} and this shell '
          'was built for ${shell.target}; its bindings were never compared '
          'against what this shell has.',
    );
  }
  final Set<String> has = shell.bindings.toSet();
  final List<String> missing = <String>[
    for (final String binding in bundle.normalizedBindings)
      if (!has.contains(binding)) binding,
  ];
  if (missing.isEmpty) return null;
  return DVDevClientRefusal(
    code: dvDevClientMissingBinding,
    missing: missing,
    message:
        'This bundle needs ${missing.join(', ')}, which this shell was '
        'not built with. A native change needs a rebuilt shell: run '
        '`dartvel build dev-client --target ${shell.target}` and install it.',
  );
}

/// The content version of a dev bundle: a digest of everything but its
/// `version` field, independent of key order.
String dvDevClientBundleVersion(Map<String, Object?> bundle) {
  final Map<String, Object?> content = Map<String, Object?>.of(bundle)
    ..remove('version');
  return 'sha256-${sha256.convert(utf8.encode(_canonical(content)))}';
}

String _canonical(Object? value) {
  if (value is Map) {
    final List<String> keys = <String>[for (final Object? k in value.keys) '$k']
      ..sort();
    return '{${keys.map((String k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

/// The key a dev server or a preview seals bundles with.
///
/// ES256 over P-256, the primitive VAPID and module signatures already use.
/// A dev server generates a fresh one per run, so a pairing ends when the
/// server does.
class DVDevClientSigner {
  DVDevClientSigner._(this._pair);

  factory DVDevClientSigner.generate([Random? random]) =>
      DVDevClientSigner._(DVWebPushKeyPair.generate(random));

  factory DVDevClientSigner.fromPrivateKey(Uint8List privateKey) =>
      DVDevClientSigner._(DVWebPushKeyPair.fromPrivateKey(privateKey));

  final DVWebPushKeyPair _pair;

  /// The uncompressed P-256 point a pairing link carries.
  Uint8List get publicKey => Uint8List.fromList(_pair.publicKey);

  /// A raw `r||s` ES256 signature over [message].
  Uint8List sign(List<int> message) =>
      dvWebPushSignEs256(message, _pair.privateKey);

  /// [bundle] sealed into an envelope.
  ///
  /// A bundle with no `version` is given its content version. [channel] is
  /// the branch a dev server serves, or the OTA channel. [sequence] increases
  /// with every seal from the same key, so a device can refuse an older
  /// bundle replayed after a newer one.
  String seal({
    required Map<String, Object?> bundle,
    String? channel,
    DVDevClientManifest? requires,
    int? sequence,
  }) {
    final Map<String, Object?> sealed = <String, Object?>{
      'version': bundle['version'] ?? dvDevClientBundleVersion(bundle),
      for (final MapEntry<String, Object?> e in bundle.entries)
        if (e.key != 'version') e.key: e.value,
    };
    final String payload = jsonEncode(<String, Object?>{
      'format': dvSignedBundleFormat,
      if (channel != null) 'channel': channel,
      if (sequence != null) 'sequence': sequence,
      if (requires != null) 'requires': requires.toJson(),
      'bundle': sealed,
    });
    final List<int> bytes = utf8.encode(payload);
    return jsonEncode(<String, Object?>{
      'format': dvSignedBundleFormat,
      'payload': dvWebPushBase64Encode(bytes),
      'signature': dvWebPushBase64Encode(sign(bytes)),
    });
  }
}

/// A bundle whose signature has been verified.
class DVSignedBundle {
  const DVSignedBundle._({
    required this.bundle,
    this.channel,
    this.sequence,
    this.requires,
  });

  /// The page bundle, in the OTA wire format.
  final Map<String, Object?> bundle;

  final String? channel;
  final int? sequence;
  final DVDevClientManifest? requires;

  /// Verifies [envelope] against [publicKey] and returns what it states.
  ///
  /// The statement is parsed from the exact bytes the signature covers, and
  /// those bytes must be canonical: a payload with a duplicated key means one
  /// thing to one parser and another to the next. With
  /// [requireContentVersion] the bundle's version must be its content digest.
  ///
  /// Throws [DVSignedBundleException] for anything else, including a bundle
  /// that was never signed at all.
  static DVSignedBundle open(
    String envelope, {
    required List<int> publicKey,
    bool requireContentVersion = false,
  }) {
    final Object? outer;
    try {
      outer = jsonDecode(envelope);
    } on FormatException {
      throw const DVSignedBundleException('The body is not a bundle at all.');
    }
    if (outer is! Map ||
        outer['format'] != dvSignedBundleFormat ||
        outer['payload'] is! String ||
        outer['signature'] is! String) {
      throw const DVSignedBundleException(
        'This bundle is not signed, and only signed bundles are loaded.',
      );
    }

    final Uint8List payload;
    final Uint8List signature;
    try {
      payload = dvWebPushBase64Decode(outer['payload'] as String);
      signature = dvWebPushBase64Decode(outer['signature'] as String);
    } on FormatException {
      throw const DVSignedBundleException(
        'The envelope\'s payload or signature is not base64url.',
      );
    }
    if (!_verifyEs256(payload, signature, publicKey)) {
      throw const DVSignedBundleException(
        'The signature does not verify against the paired key. The bundle '
        'was sealed by another key or altered after sealing.',
      );
    }

    final String text;
    final Object? statement;
    try {
      text = utf8.decode(payload);
      statement = jsonDecode(text);
    } on FormatException {
      throw const DVSignedBundleException('The signed payload is not JSON.');
    }
    if (jsonEncode(statement) != text) {
      throw const DVSignedBundleException(
        'The signed payload is not canonical JSON (a key is duplicated or '
        'spaced differently), so it could be read two ways.',
      );
    }
    if (statement is! Map || statement['format'] != dvSignedBundleFormat) {
      throw const DVSignedBundleException(
        'The signed payload does not name the bundle format.',
      );
    }
    final Object? bundle = statement['bundle'];
    if (bundle is! Map ||
        bundle['version'] is! String ||
        (bundle['version'] as String).isEmpty) {
      throw const DVSignedBundleException(
        'The signed payload carries no versioned bundle.',
      );
    }
    final Map<String, Object?> typed = bundle.cast<String, Object?>();
    if (requireContentVersion &&
        typed['version'] != dvDevClientBundleVersion(typed)) {
      throw DVSignedBundleException(
        'The bundle\'s version "${typed['version']}" is not the digest of '
        'its content, so a changed bundle could be taken for one already '
        'applied.',
      );
    }

    final Object? channel = statement['channel'];
    final Object? sequence = statement['sequence'];
    final Object? requires = statement['requires'];
    try {
      return DVSignedBundle._(
        bundle: typed,
        channel: channel is String ? channel : null,
        sequence: sequence is int ? sequence : null,
        requires: requires is Map
            ? DVDevClientManifest.fromJson(requires.cast<String, Object?>())
            : null,
      );
    } on FormatException catch (error) {
      throw DVSignedBundleException(error.message);
    }
  }
}

/// What a pairing link carries: where the server is, which branch it serves,
/// the key its bundles are sealed with, and the token that lets this device
/// fetch them.
///
/// The key is what stops another machine pushing code; the token is what
/// stops another device reading it. Both travel out of band -- a QR code on
/// the developer's screen or a deep link sent to a colleague -- which is the
/// whole of the pairing: nothing on the network can substitute either.
class DVDevClientPairing {
  DVDevClientPairing({
    required this.server,
    required this.branch,
    required List<int> publicKey,
    required this.token,
  }) : publicKey = Uint8List.fromList(publicKey);

  final Uri server;
  final String branch;
  final Uint8List publicKey;
  final String token;

  /// `dartvel-dev://pair?server=...&branch=...&key=...&token=...`
  Uri get link => Uri(
    scheme: dvDevClientLinkScheme,
    host: 'pair',
    queryParameters: <String, String>{
      'server': server.toString(),
      'branch': branch,
      'key': dvWebPushBase64Encode(publicKey),
      'token': token,
    },
  );

  /// Where the current bundle for [target] is fetched.
  Uri bundleUri(String target) {
    final String base = server.path.replaceAll(RegExp(r'/+$'), '');
    return server.replace(
      path: '$base$dvDevClientBundlePath',
      queryParameters: <String, String>{'target': target},
    );
  }

  /// Parses a pairing link, refusing anything it could not trust.
  factory DVDevClientPairing.parse(Uri link) {
    if (link.scheme != dvDevClientLinkScheme || link.host != 'pair') {
      throw const FormatException(
        'Not a Dartvel pairing link: $dvDevClientLinkScheme://pair?... '
        'expected.',
      );
    }
    final Map<String, String> q = link.queryParameters;

    final Uri? server = Uri.tryParse(q['server'] ?? '');
    if (server == null ||
        !(server.scheme == 'http' || server.scheme == 'https') ||
        server.host.isEmpty) {
      throw const FormatException(
        'A pairing link names an http or https dev server.',
      );
    }
    final String branch = q['branch'] ?? '';
    if (branch.trim().isEmpty) {
      throw const FormatException('A pairing link names the branch it serves.');
    }

    final Uint8List key;
    try {
      key = dvWebPushBase64Decode(q['key'] ?? '');
    } on FormatException {
      throw const FormatException('The pairing key is not base64url.');
    }
    if (!_isP256Point(key)) {
      // Without a key there is nothing to verify a bundle against, and a
      // shell that loaded anyway would load from anybody.
      throw const FormatException(
        'A pairing link carries the server\'s P-256 public key.',
      );
    }

    final String token = q['token'] ?? '';
    Uint8List tokenBytes;
    try {
      tokenBytes = dvWebPushBase64Decode(token);
    } on FormatException {
      tokenBytes = Uint8List(0);
    }
    if (tokenBytes.length < 32) {
      throw const FormatException(
        'A pairing token is at least 32 random bytes; a shorter one can be '
        'guessed by anything on the network.',
      );
    }

    return DVDevClientPairing(
      server: server,
      branch: branch,
      publicKey: key,
      token: token,
    );
  }

  /// 32 bytes from a secure source, base64url.
  static String newToken([Random? random]) {
    final Random source = random ?? Random.secure();
    return dvWebPushBase64Encode(<int>[
      for (int i = 0; i < 32; i++) source.nextInt(256),
    ]);
  }

  /// Whether [presented] is [expected], compared in constant time.
  static bool tokenMatches(String? presented, String expected) {
    if (presented == null) return false;
    final List<int> a = utf8.encode(presented);
    final List<int> b = utf8.encode(expected);
    int difference = a.length ^ b.length;
    for (int i = 0; i < b.length; i++) {
      difference |= (i < a.length ? a[i] : 0) ^ b[i];
    }
    return difference == 0 && b.isNotEmpty;
  }
}

// P-256: y^2 = x^3 - 3x + b over p.
final BigInt _p = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final BigInt _b = BigInt.parse(
  '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  radix: 16,
);

bool _isP256Point(List<int> key) {
  if (key.length != 65 || key[0] != 4) return false;
  final BigInt x = _bigInt(key.sublist(1, 33));
  final BigInt y = _bigInt(key.sublist(33));
  if (x >= _p || y >= _p) return false;
  final BigInt left = (y * y) % _p;
  final BigInt right = (x * x * x - BigInt.from(3) * x + _b) % _p;
  return left == right;
}

bool _verifyEs256(List<int> message, List<int> signature, List<int> key) {
  if (signature.length != 64 || !_isP256Point(key)) return false;
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
      Uint8List.fromList(message),
      ECSignature(
        _bigInt(signature.sublist(0, 32)),
        _bigInt(signature.sublist(32)),
      ),
    );
  } on Object {
    // Nonsense that decodes: "unverified" is the honest answer to all of it.
    return false;
  }
}

BigInt _bigInt(List<int> bytes) {
  BigInt result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
