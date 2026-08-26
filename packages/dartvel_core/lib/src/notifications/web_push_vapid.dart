// VAPID, per RFC 8292: how an application server identifies itself to a push
// service.
//
// Encryption alone does not get a message delivered. A push service will not
// accept an anonymous POST to a subscription endpoint, because anyone who
// learned the endpoint could then send to it. VAPID is the signed statement
// of who is sending, so the subscription is bound to one application server.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'web_push.dart';

/// Builds the `Authorization` header a push service requires.
class DVWebPushVapid {
  const DVWebPushVapid._();

  /// The longest life a push service will accept for a token.
  static const Duration maximumExpiry = Duration(hours: 24);

  /// The default life. Well inside the maximum, so clock skew between this
  /// server and the push service cannot push a fresh token past it.
  static const Duration defaultExpiry = Duration(hours: 12);

  /// The `vapid t=..., k=...` header value for a message to [endpoint].
  ///
  /// [subject] is the contact the push service can reach the sender at — a
  /// `mailto:` or `https:` URI. [now] exists so a caller can reproduce a
  /// token; real calls leave it out.
  static String authorizationHeader({
    required String endpoint,
    required DVWebPushKeyPair keyPair,
    String? subject,
    Duration expiry = defaultExpiry,
    DateTime? now,
  }) {
    if (expiry > maximumExpiry) {
      throw ArgumentError.value(
        expiry,
        'expiry',
        'A VAPID token lives at most 24 hours; a push service rejects a '
            'longer one outright.',
      );
    }
    if (expiry <= Duration.zero) {
      throw ArgumentError.value(
        expiry,
        'expiry',
        'A VAPID token that has already expired cannot be accepted.',
      );
    }
    if (subject != null &&
        !subject.startsWith('mailto:') &&
        !subject.startsWith('https:')) {
      throw ArgumentError.value(
        subject,
        'subject',
        'A VAPID subject is a mailto: or https: contact URI.',
      );
    }

    final issuedAt = now ?? DateTime.now();
    final token = signedToken(
      audience: audienceFor(endpoint),
      expiresAt: issuedAt.add(expiry),
      subject: subject,
      keyPair: keyPair,
    );
    return 'vapid t=$token, k=${dvWebPushBase64Encode(keyPair.publicKey)}';
  }

  /// The origin of [endpoint], which is what `aud` names.
  ///
  /// The path identifies the subscription, and a token scoped to one
  /// subscription would have to be reissued per recipient.
  static String audienceFor(String endpoint) {
    final uri = Uri.parse(endpoint);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'A push endpoint is an absolute URL.',
      );
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null)
        .toString();
  }

  /// A signed ES256 JWT with the VAPID claims.
  static String signedToken({
    required String audience,
    required DateTime expiresAt,
    required DVWebPushKeyPair keyPair,
    String? subject,
  }) {
    final header = <String, Object?>{'typ': 'JWT', 'alg': 'ES256'};
    final claims = <String, Object?>{
      'aud': audience,
      'exp': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      if (subject != null) 'sub': subject,
    };
    final signingInput = '${_segment(header)}.${_segment(claims)}';
    final signature = _sign(utf8.encode(signingInput), keyPair.privateKey);
    return '$signingInput.${dvWebPushBase64Encode(signature)}';
  }

  /// Whether [token] was signed by [publicKey].
  ///
  /// Provided because a signature nobody can check is not evidence of
  /// anything: this is what lets a test hold the implementation against a
  /// token it did not produce.
  static bool verify(String token, Uint8List publicKey) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    final signature = dvWebPushBase64Decode(parts[2]);
    if (signature.length != 64) return false;

    final domain = ECDomainParameters('prime256v1');
    final verifier = ECDSASigner(SHA256Digest())
      ..init(
        false,
        PublicKeyParameter<ECPublicKey>(
          ECPublicKey(domain.curve.decodePoint(publicKey), domain),
        ),
      );
    return verifier.verifySignature(
      Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
      ECSignature(
        _toBigInt(signature.sublist(0, 32)),
        _toBigInt(signature.sublist(32)),
      ),
    );
  }

  /// The claims inside [token], without checking its signature.
  static Map<String, Object?> claimsOf(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw ArgumentError.value(token, 'token', 'A JWT has three segments.');
    }
    return (jsonDecode(utf8.decode(dvWebPushBase64Decode(parts[1])))
            as Map<Object?, Object?>)
        .cast<String, Object?>();
  }

  static String _segment(Map<String, Object?> value) =>
      dvWebPushBase64Encode(utf8.encode(jsonEncode(value)));

  /// ES256 over [message]: a raw r||s pair, not the DER encoding a general
  /// ECDSA signer emits — JWS specifies the fixed-width concatenation.
  static Uint8List _sign(List<int> message, Uint8List privateKey) =>
      dvWebPushSignEs256(message, privateKey);

  static BigInt _toBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}

/// ES256 over [message] with a P-256 [privateKey], as JWS wants it.
///
/// A raw, fixed-width `r||s` pair of 64 bytes — not the DER encoding a general
/// ECDSA signer emits. DER trims leading zero bytes and wraps the pair in a
/// sequence, so a DER signature is both a different length and a different
/// shape, and every push service answers one with a 401.
///
/// k is derived from the key and the message per RFC 6979 rather than drawn
/// from an entropy source. That is a security property first: a repeated or
/// predictable k leaks the private key, and ECDSA has lost keys that way. It
/// makes the output reproducible second, which is what lets the signature be
/// pinned to RFC 6979's published vectors instead of only round-tripped
/// through this library's own verifier.
///
/// Public because it is the security-critical primitive under VAPID and is
/// worth asserting on directly.
Uint8List dvWebPushSignEs256(List<int> message, Uint8List privateKey) {
  final domain = ECDomainParameters('prime256v1');
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(
        ECPrivateKey(_bigIntFromBytes(privateKey), domain),
      ),
    );
  final signature =
      signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
  return Uint8List.fromList(<int>[
    ..._fixedWidthBytes(signature.r, 32),
    ..._fixedWidthBytes(signature.s, 32),
  ]);
}

/// A big-endian encoding of [value] in exactly [length] bytes.
///
/// Left-padded with zeros where the value is short. That padding is the whole
/// point: RFC 6979's own "test" vector has an s beginning `01`, and an
/// implementation that emitted the minimal integer would produce 63 bytes.
Uint8List _fixedWidthBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var remaining = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}

BigInt _bigIntFromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
