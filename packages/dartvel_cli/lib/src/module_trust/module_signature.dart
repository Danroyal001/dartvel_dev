/// A module package signed by its publisher.
///
/// Dartvel runs no key server and issues no certificates. The publisher signs
/// a statement -- package, version, content digest, capabilities -- and the
/// parent pins the key on first use and compares every resolution after that
/// against the pin.
///
/// The signature is over the exact payload bytes the document carries, and
/// those same bytes are what is parsed. Signing one serialisation and reading
/// another is how a signature ends up covering something other than what the
/// reader acts on, so the payload is also required to be canonical: a
/// document with a duplicate key parses to one statement under one parser and
/// another under the next, and is refused.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        dvModuleSigningPublicKey,
        dvWebPushBase64Decode,
        dvWebPushBase64Encode,
        dvWebPushSignEs256;
import 'package:pointycastle/export.dart';

import 'capabilities.dart';
import 'package_digest.dart';

/// The format both the envelope and the signed statement name.
const String dvModuleSignatureFormat = 'dartvel-module-signature-v1';

/// Why a signature was not accepted.
class DVModuleSignatureException implements Exception {
  const DVModuleSignatureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a publisher signs about one release of a module.
class DVModuleSignedStatement {
  const DVModuleSignedStatement({
    required this.package,
    required this.version,
    required this.sha256,
    required this.capabilities,
    this.publisher,
    this.dartvel,
  });

  final String package;
  final String version;

  /// [dvModulePackageDigest] of the release.
  final String sha256;

  /// The complete list of capabilities the module uses.
  final DVModuleCapabilities capabilities;

  /// Who the publisher says it is. A claim, written by the publisher: nothing
  /// is ever trusted because of it.
  final String? publisher;

  /// The Dartvel range the module supports.
  final String? dartvel;

  Map<String, Object?> toJson() => <String, Object?>{
    'capabilities': capabilities.toJson(),
    'dartvel': dartvel,
    'format': dvModuleSignatureFormat,
    'package': package,
    'publisher': publisher,
    'sha256': sha256,
    'version': version,
  };

  /// The bytes that are signed: [toJson] with every key sorted and no
  /// whitespace.
  List<int> canonicalBytes() => utf8.encode(jsonEncode(_sorted(toJson())));

  /// Reads a signed payload, refusing anything that is not exactly the
  /// canonical form of the statement it parses to.
  static DVModuleSignedStatement fromCanonicalBytes(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const DVModuleSignatureException(
        'The signed statement is not JSON, so nothing in it can be trusted.',
      );
    }
    if (json is! Map) {
      throw const DVModuleSignatureException(
        'The signed statement is not an object.',
      );
    }
    const Set<String> keys = <String>{
      'capabilities',
      'dartvel',
      'format',
      'package',
      'publisher',
      'sha256',
      'version',
    };
    if (json.length != keys.length || !json.keys.every(keys.contains)) {
      throw const DVModuleSignatureException(
        'The signed statement carries fields other than the ones a statement '
        'has.',
      );
    }
    final Object? format = json['format'];
    final Object? package = json['package'];
    final Object? version = json['version'];
    final Object? sha256 = json['sha256'];
    final Object? publisher = json['publisher'];
    final Object? dartvel = json['dartvel'];
    if (format != dvModuleSignatureFormat ||
        package is! String ||
        package.isEmpty ||
        version is! String ||
        version.isEmpty ||
        sha256 is! String ||
        !dvIsModuleDigest(sha256) ||
        (publisher != null && publisher is! String) ||
        (dartvel != null && dartvel is! String)) {
      throw const DVModuleSignatureException(
        'The signed statement does not name a package, a version and a '
        'sha256 digest in the form a statement writes them.',
      );
    }
    final DVModuleCapabilities capabilities;
    try {
      capabilities = DVModuleCapabilities.fromJson(json['capabilities']);
    } on FormatException catch (e) {
      throw DVModuleSignatureException(
        'The signed statement\'s capabilities cannot be read: ${e.message}.',
      );
    }
    final DVModuleSignedStatement statement = DVModuleSignedStatement(
      package: package,
      version: version,
      sha256: sha256,
      capabilities: capabilities,
      publisher: publisher as String?,
      dartvel: dartvel as String?,
    );
    if (!_sameBytes(statement.canonicalBytes(), bytes)) {
      throw const DVModuleSignatureException(
        'The signed statement is not in canonical form. What was signed and '
        'what would be read from it could differ, so it is refused.',
      );
    }
    return statement;
  }
}

/// A verified signature.
class DVModuleSignature {
  const DVModuleSignature({
    required this.keyId,
    required this.publicKey,
    required this.statement,
  });

  /// The publisher's label for the key. Not an identity: two keys can share
  /// one, which is exactly what a takeover would do.
  final String keyId;
  final String publicKey;
  final DVModuleSignedStatement statement;
}

/// ES256 over [bytes], base64url.
String dvModuleSignBytes(List<int> bytes, Uint8List privateKey) =>
    dvWebPushBase64Encode(dvWebPushSignEs256(bytes, privateKey));

/// The signature document for [statement], as written to
/// [dvModuleSignatureFile].
String dvSignModulePackage(
  DVModuleSignedStatement statement, {
  required Uint8List privateKey,
  required String keyId,
}) {
  final List<int> bytes = statement.canonicalBytes();
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'format': dvModuleSignatureFormat,
    'keyId': keyId,
    'publicKey': dvModuleSigningPublicKey(privateKey),
    'payload': base64Url.encode(bytes),
    'signature': dvModuleSignBytes(bytes, privateKey),
  });
}

/// The sha256 of a public key's bytes, as lowercase hex: how a key is named to
/// people, and how a parent revokes one.
String dvModuleKeyFingerprint(String publicKey) {
  final Uint8List bytes;
  try {
    bytes = dvWebPushBase64Decode(publicKey);
  } on Object {
    throw const DVModuleSignatureException('The public key is not base64url.');
  }
  return sha256.convert(bytes).toString();
}

class _Envelope {
  const _Envelope(this.keyId, this.publicKey, this.payload, this.signature);

  final String keyId;
  final String publicKey;
  final List<int> payload;
  final String signature;
}

_Envelope _envelope(String document) {
  final Object? json;
  try {
    json = jsonDecode(document);
  } on FormatException {
    throw const DVModuleSignatureException('The signature file is not JSON.');
  }
  const Set<String> keys = <String>{
    'format',
    'keyId',
    'publicKey',
    'payload',
    'signature',
  };
  if (json is! Map ||
      json.length != keys.length ||
      !json.keys.every(keys.contains) ||
      json['format'] != dvModuleSignatureFormat ||
      json.values.any((Object? v) => v is! String)) {
    throw const DVModuleSignatureException(
      'The signature file is not a dartvel-module-signature-v1 document: a '
      'format, a keyId, a publicKey, a payload and a signature, and nothing '
      'else.',
    );
  }
  final List<int> payload;
  try {
    payload = base64Url.decode(base64Url.normalize(json['payload']! as String));
  } on FormatException {
    throw const DVModuleSignatureException(
      'The signature file\'s payload is not base64url.',
    );
  }
  return _Envelope(
    json['keyId']! as String,
    json['publicKey']! as String,
    payload,
    json['signature']! as String,
  );
}

/// The public key [document] says it was signed with, unverified; null when
/// the document cannot be read.
///
/// For comparing against a pin and for trust on first use. It is a field the
/// publisher writes, so it is never what a signature is verified against once
/// a key is pinned.
String? dvClaimedModuleSigningKey(String document) {
  try {
    return _envelope(document).publicKey;
  } on DVModuleSignatureException {
    return null;
  }
}

/// Verifies [document] against [publicKey] -- the pinned key, not the one the
/// document names -- and returns what it signs.
///
/// Throws [DVModuleSignatureException] for anything short of a canonical
/// statement signed by that key.
DVModuleSignature dvVerifyModuleSignature(
  String document, {
  required String publicKey,
}) {
  final _Envelope envelope = _envelope(document);
  if (!dvModuleVerifyBytes(envelope.payload, envelope.signature, publicKey)) {
    throw const DVModuleSignatureException(
      'The signature does not verify against the key, so the statement was '
      'either signed by somebody else or edited after it was signed.',
    );
  }
  return DVModuleSignature(
    keyId: envelope.keyId,
    publicKey: envelope.publicKey,
    statement: DVModuleSignedStatement.fromCanonicalBytes(envelope.payload),
  );
}

/// Whether [signature] is ES256 over exactly [bytes] by [publicKey].
bool dvModuleVerifyBytes(List<int> bytes, String signature, String publicKey) {
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
      Uint8List.fromList(bytes),
      ECSignature(_bigInt(raw.sublist(0, 32)), _bigInt(raw.sublist(32))),
    );
  } on Object {
    // A key that is not a point on the curve is not a key that signed this.
    return false;
  }
}

BigInt _bigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Object? _sorted(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final String key
          in value.keys.map((Object? k) => '$k').toList()..sort())
        key: _sorted(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final Object? v in value) _sorted(v)];
  }
  return value;
}
