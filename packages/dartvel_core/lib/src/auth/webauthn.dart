/// Passkey sign-in: verifying a WebAuthn assertion.
///
/// Every check below exists because skipping it produces a *successful* login.
/// A verifier that omits the challenge accepts a replayed assertion forever;
/// one that omits the origin accepts an assertion produced on any site the
/// user visits. Neither failure is visible from the outside: the user signs in
/// and nothing logs a complaint.
///
/// This is the relying party's half of `navigator.credentials.get()`. The
/// client sends back the authenticator data, the client data JSON, and a
/// signature over both; the server checks all three against what it expects
/// and against the public key it stored at registration.
library dartvel_core.auth.webauthn;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// The outcome of verifying an assertion.
///
/// Carries a reason rather than only a boolean, because "the login failed" is
/// not something an operator can act on and "the signature counter went
/// backwards" is.
class DVWebAuthnVerification {
  const DVWebAuthnVerification._(this.ok, this.reason, this.signCount);

  const DVWebAuthnVerification.failed(String reason)
      : this._(false, reason, 0);

  const DVWebAuthnVerification.passed(int signCount)
      : this._(true, null, signCount);

  /// Whether the assertion is genuine and current.
  final bool ok;

  /// Why it was refused. Null when [ok].
  final String? reason;

  /// The counter the authenticator reported. Store it: the next assertion is
  /// checked against it.
  final int signCount;
}

/// Verifies WebAuthn assertions.
class DVWebAuthn {
  const DVWebAuthn._();

  /// The fixed part of authenticator data: a 32-byte RP hash, one flags byte,
  /// and a four-byte counter.
  static const int _headerLength = 37;

  static const int _flagUserPresent = 0x01;
  static const int _flagUserVerified = 0x04;

  /// Checks an assertion from `navigator.credentials.get()`.
  ///
  /// [credentialPublicKey] is the uncompressed P-256 point stored at
  /// registration. [storedSignCount] is the counter from the last successful
  /// assertion for this credential.
  static DVWebAuthnVerification verifyAssertion({
    required Uint8List credentialPublicKey,
    required Uint8List authenticatorData,
    required String clientDataJson,
    required Uint8List signature,
    required Uint8List expectedChallenge,
    required String expectedOrigin,
    required String expectedRpId,
    int storedSignCount = 0,
    bool requireUserVerification = true,
  }) {
    // --- client data -------------------------------------------------------
    Object? decoded;
    try {
      decoded = jsonDecode(clientDataJson);
    } on FormatException {
      return const DVWebAuthnVerification.failed(
        'clientDataJSON was not JSON.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const DVWebAuthnVerification.failed(
        'clientDataJSON was not an object.',
      );
    }

    // webauthn.create and webauthn.get sign the same shape, so accepting
    // either would let a registration ceremony be replayed as a sign-in.
    if (decoded['type'] != 'webauthn.get') {
      return DVWebAuthnVerification.failed(
        'Expected a webauthn.get ceremony, got "${decoded['type']}".',
      );
    }

    // The anti-replay check.
    final Object? presentedChallenge = decoded['challenge'];
    if (presentedChallenge is! String ||
        !_sameBytes(_fromBase64Url(presentedChallenge), expectedChallenge)) {
      return const DVWebAuthnVerification.failed(
        'The challenge did not match the one issued.',
      );
    }

    // The anti-phishing check. Compared whole: a subdomain of the expected
    // origin is a different origin, and so is the same host over http.
    if (decoded['origin'] != expectedOrigin) {
      return DVWebAuthnVerification.failed(
        'The assertion came from "${decoded['origin']}", not $expectedOrigin.',
      );
    }

    // --- authenticator data ------------------------------------------------
    if (authenticatorData.length < _headerLength) {
      // Reading the flags or counter out of a short buffer would either throw
      // or read whatever follows it.
      return DVWebAuthnVerification.failed(
        'Authenticator data was ${authenticatorData.length} bytes, '
        'shorter than the $_headerLength-byte header.',
      );
    }

    final List<int> expectedRpHash =
        sha256.convert(utf8.encode(expectedRpId)).bytes;
    if (!_sameBytes(
      Uint8List.sublistView(authenticatorData, 0, 32),
      Uint8List.fromList(expectedRpHash),
    )) {
      return DVWebAuthnVerification.failed(
        'The assertion was produced for a different relying party than '
        '$expectedRpId.',
      );
    }

    final int flags = authenticatorData[32];
    if (flags & _flagUserPresent == 0) {
      // No human touched the authenticator.
      return const DVWebAuthnVerification.failed(
        'The user-presence flag was not set.',
      );
    }
    if (requireUserVerification && flags & _flagUserVerified == 0) {
      return const DVWebAuthnVerification.failed(
        'User verification was required and the flag was not set.',
      );
    }

    final int signCount =
        ByteData.sublistView(authenticatorData, 33, 37).getUint32(0);
    // A counter that went backwards means two authenticators share a
    // credential -- one of them a clone. Zero on both sides is not a
    // regression: authenticators that do not implement a counter always send
    // zero, and treating that as an attack locks those users out for good.
    if (!(signCount == 0 && storedSignCount == 0) &&
        signCount <= storedSignCount) {
      return DVWebAuthnVerification.failed(
        'The signature counter did not advance ($signCount after '
        '$storedSignCount), which suggests a cloned authenticator.',
      );
    }

    // --- signature ---------------------------------------------------------
    // Over the authenticator data actually presented, concatenated with the
    // hash of the client data actually presented. Verifying anything else
    // would let the flags and RP hash checked above be swapped after signing.
    final Uint8List signedPayload = Uint8List.fromList(<int>[
      ...authenticatorData,
      ...sha256.convert(utf8.encode(clientDataJson)).bytes,
    ]);

    final bool valid = _verifyP256(
      publicKey: credentialPublicKey,
      payload: signedPayload,
      derSignature: signature,
    );
    if (!valid) {
      return const DVWebAuthnVerification.failed(
        'The signature did not verify against the stored credential.',
      );
    }

    return DVWebAuthnVerification.passed(signCount);
  }

  static bool _verifyP256({
    required Uint8List publicKey,
    required Uint8List payload,
    required Uint8List derSignature,
  }) {
    try {
      final ECDomainParameters domain = ECDomainParameters('secp256r1');
      final ({BigInt r, BigInt s})? parsed = dvDecodeDerSignature(derSignature);
      if (parsed == null) return false;

      final ECDSASigner verifier = ECDSASigner(SHA256Digest())
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(
            ECPublicKey(domain.curve.decodePoint(publicKey), domain),
          ),
        );
      return verifier.verifySignature(
        payload,
        ECSignature(parsed.r, parsed.s),
      );
    } on Object {
      // A malformed key or signature is a refusal, not a crash: this runs on
      // attacker-supplied input by definition.
      return false;
    }
  }

  static Uint8List _fromBase64Url(String value) {
    final String padded = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return Uint8List.fromList(base64Url.decode(padded));
  }

  /// Constant-time-ish comparison. Length is compared first because an
  /// early return on length leaks nothing an attacker cannot already measure.
  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i += 1) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// Encodes an ECDSA signature as the DER SEQUENCE WebAuthn authenticators
/// produce.
Uint8List dvEncodeDerSignature(BigInt r, BigInt s) {
  List<int> integer(BigInt value) {
    List<int> bytes = _unsignedBytes(value);
    // DER integers are signed, so a leading bit of 1 needs a zero byte or the
    // value reads as negative.
    if (bytes.isEmpty || bytes.first & 0x80 != 0) bytes = <int>[0, ...bytes];
    return <int>[0x02, bytes.length, ...bytes];
  }

  final List<int> body = <int>[...integer(r), ...integer(s)];
  return Uint8List.fromList(<int>[0x30, body.length, ...body]);
}

/// Reads a DER-encoded ECDSA signature. Null when it is not one.
({BigInt r, BigInt s})? dvDecodeDerSignature(Uint8List der) {
  int at = 0;
  if (der.length < 8 || der[at++] != 0x30) return null;
  final int total = der[at++];
  if (total != der.length - 2) return null;

  BigInt? readInteger() {
    if (at >= der.length || der[at++] != 0x02) return null;
    if (at >= der.length) return null;
    final int length = der[at++];
    if (length <= 0 || at + length > der.length) return null;
    final Uint8List bytes = Uint8List.sublistView(der, at, at + length);
    at += length;
    BigInt value = BigInt.zero;
    for (final int byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  final BigInt? r = readInteger();
  final BigInt? s = readInteger();
  if (r == null || s == null || at != der.length) return null;
  return (r: r, s: s);
}

List<int> _unsignedBytes(BigInt value) {
  if (value == BigInt.zero) return <int>[0];
  final List<int> bytes = <int>[];
  BigInt remaining = value;
  while (remaining > BigInt.zero) {
    bytes.insert(0, (remaining & BigInt.from(0xff)).toInt());
    remaining = remaining >> 8;
  }
  return bytes;
}
