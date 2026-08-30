// Passkey (WebAuthn) assertion verification.
//
// Every check here exists because skipping it produces a *successful* login.
// That is what makes this worth testing exhaustively rather than happily: a
// verifier that returns true is indistinguishable from a correct one until
// somebody replays a captured assertion or phishes an origin.
//
// The signature primitive is ECDSA over P-256, already pinned elsewhere in
// this package against RFC 6979's published vectors. What is constructed here
// is the protocol around it -- challenge, origin, RP hash, flags, counter --
// which is logic rather than cryptography and is exactly where an
// implementation quietly does less than it claims.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

const String rpId = 'example.test';
const String origin = 'https://example.test';
final Uint8List challenge = Uint8List.fromList(List<int>.generate(32, (int i) => i));

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A deterministic P-256 key pair. [seed] distinguishes one key from another:
/// with a fixed seed, "a different key" is the same key and the test that
/// rejects a foreign signature passes for the wrong reason.
({ECPrivateKey private, Uint8List publicKey}) makeKey({int seed = 7}) {
  final ECDomainParameters domain = ECDomainParameters('secp256r1');
  final SecureRandom random = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List<int>.filled(32, seed))));
  final ECKeyGenerator generator = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(domain), random));
  final AsymmetricKeyPair<PublicKey, PrivateKey> pair =
      generator.generateKeyPair();
  final ECPublicKey public = pair.publicKey as ECPublicKey;
  return (
    private: pair.privateKey as ECPrivateKey,
    publicKey: public.Q!.getEncoded(false),
  );
}

/// Builds authenticator data: rpIdHash(32) | flags(1) | signCount(4).
Uint8List authenticatorData({
  String forRpId = rpId,
  bool userPresent = true,
  bool userVerified = true,
  int signCount = 1,
}) {
  final List<int> rpHash = sha256.convert(utf8.encode(forRpId)).bytes;
  int flags = 0;
  if (userPresent) flags |= 0x01;
  if (userVerified) flags |= 0x04;
  final ByteData counter = ByteData(4)..setUint32(0, signCount);
  return Uint8List.fromList(<int>[
    ...rpHash,
    flags,
    ...counter.buffer.asUint8List(),
  ]);
}

String clientData({
  String type = 'webauthn.get',
  Uint8List? forChallenge,
  String forOrigin = origin,
  bool crossOrigin = false,
}) =>
    jsonEncode(<String, Object?>{
      'type': type,
      'challenge': b64url(forChallenge ?? challenge),
      'origin': forOrigin,
      'crossOrigin': crossOrigin,
    });

/// Signs `authData || SHA-256(clientDataJSON)`, which is what an authenticator
/// signs and therefore what a verifier must check.
Uint8List sign(ECPrivateKey key, Uint8List authData, String json) {
  final Uint8List payload = Uint8List.fromList(<int>[
    ...authData,
    ...sha256.convert(utf8.encode(json)).bytes,
  ]);
  final ECDSASigner signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(key));
  final ECSignature signature = signer.generateSignature(payload) as ECSignature;
  return dvEncodeDerSignature(signature.r, signature.s);
}

void main() {
  late ECPrivateKey privateKey;
  late Uint8List publicKey;

  setUpAll(() {
    final ({ECPrivateKey private, Uint8List publicKey}) key = makeKey();
    privateKey = key.private;
    publicKey = key.publicKey;
  });

  DVWebAuthnVerification verify({
    Uint8List? authData,
    String? json,
    Uint8List? signature,
    int storedSignCount = 0,
    bool requireUserVerification = true,
  }) {
    final Uint8List data = authData ?? authenticatorData();
    final String clientJson = json ?? clientData();
    return DVWebAuthn.verifyAssertion(
      credentialPublicKey: publicKey,
      authenticatorData: data,
      clientDataJson: clientJson,
      signature: signature ?? sign(privateKey, data, clientJson),
      expectedChallenge: challenge,
      expectedOrigin: origin,
      expectedRpId: rpId,
      storedSignCount: storedSignCount,
      requireUserVerification: requireUserVerification,
    );
  }

  test('a well-formed assertion verifies', () {
    final DVWebAuthnVerification result = verify();

    expect(result.ok, isTrue, reason: result.reason);
    expect(result.signCount, 1);
  });

  group('replay', () {
    test('a different challenge is refused', () {
      // Without this check a captured assertion logs the attacker in forever.
      final String json = clientData(
        forChallenge: Uint8List.fromList(List<int>.filled(32, 9)),
      );

      expect(verify(json: json).ok, isFalse);
    });

    test('a truncated challenge is not a prefix match', () {
      final String json =
          clientData(forChallenge: Uint8List.sublistView(challenge, 0, 16));

      expect(verify(json: json).ok, isFalse);
    });
  });

  group('origin', () {
    test('a different origin is refused', () {
      // The anti-phishing check. A verifier that skips it accepts an assertion
      // produced on any site the user visits.
      expect(verify(json: clientData(forOrigin: 'https://evil.test')).ok,
          isFalse);
    });

    test('a subdomain of the expected origin is not the expected origin', () {
      expect(
        verify(json: clientData(forOrigin: 'https://evil.example.test')).ok,
        isFalse,
      );
    });

    test('a scheme downgrade is refused', () {
      expect(verify(json: clientData(forOrigin: 'http://example.test')).ok,
          isFalse);
    });
  });

  group('ceremony type', () {
    test('a registration assertion is not a login assertion', () {
      // webauthn.create and webauthn.get sign the same shape. Accepting either
      // lets a registration ceremony be replayed as a sign-in.
      expect(verify(json: clientData(type: 'webauthn.create')).ok, isFalse);
    });
  });

  group('authenticator data', () {
    test('an assertion for another relying party is refused', () {
      final Uint8List data = authenticatorData(forRpId: 'other.test');

      expect(verify(authData: data).ok, isFalse);
    });

    test('user-presence unset is refused', () {
      // UP means a human touched the authenticator. Without it the assertion
      // may have been produced with no interaction at all.
      final Uint8List data = authenticatorData(userPresent: false);

      expect(verify(authData: data).ok, isFalse);
    });

    test('user-verification unset is refused when required', () {
      final Uint8List data = authenticatorData(userVerified: false);

      expect(verify(authData: data).ok, isFalse);
    });

    test('user-verification unset is allowed when not required', () {
      final Uint8List data = authenticatorData(userVerified: false);

      expect(verify(authData: data, requireUserVerification: false).ok, isTrue);
    });

    test('data shorter than the fixed header is refused, not read past', () {
      expect(
        verify(authData: Uint8List.fromList(<int>[1, 2, 3])).ok,
        isFalse,
      );
    });
  });

  group('signature counter', () {
    test('a counter that went backwards signals a cloned authenticator', () {
      final Uint8List data = authenticatorData(signCount: 5);
      final String json = clientData();

      final DVWebAuthnVerification result = DVWebAuthn.verifyAssertion(
        credentialPublicKey: publicKey,
        authenticatorData: data,
        clientDataJson: json,
        signature: sign(privateKey, data, json),
        expectedChallenge: challenge,
        expectedOrigin: origin,
        expectedRpId: rpId,
        storedSignCount: 9,
      );

      expect(result.ok, isFalse);
      expect(result.reason, contains('counter'));
    });

    test('a counter of zero on both sides is allowed', () {
      // Authenticators that do not implement a counter always send zero;
      // treating that as a regression locks those users out permanently.
      final Uint8List data = authenticatorData(signCount: 0);
      final String json = clientData();

      final DVWebAuthnVerification result = DVWebAuthn.verifyAssertion(
        credentialPublicKey: publicKey,
        authenticatorData: data,
        clientDataJson: json,
        signature: sign(privateKey, data, json),
        expectedChallenge: challenge,
        expectedOrigin: origin,
        expectedRpId: rpId,
        storedSignCount: 0,
      );

      expect(result.ok, isTrue, reason: result.reason);
    });
  });

  group('the signature itself', () {
    test('a signature from another key is refused', () {
      final ({ECPrivateKey private, Uint8List publicKey}) other =
          makeKey(seed: 21);
      final Uint8List data = authenticatorData();
      final String json = clientData();

      expect(
        verify(
          authData: data,
          json: json,
          signature: sign(other.private, data, json),
        ).ok,
        isFalse,
      );
    });

    test('a signature over different authenticator data is refused', () {
      // The signature must cover the data actually presented, or the flags and
      // RP hash above can be swapped freely after signing.
      final Uint8List signed = authenticatorData(signCount: 1);
      final Uint8List presented = authenticatorData(signCount: 2);
      final String json = clientData();

      expect(
        verify(
          authData: presented,
          json: json,
          signature: sign(privateKey, signed, json),
        ).ok,
        isFalse,
      );
    });

    test('a signature over different client data is refused', () {
      final Uint8List data = authenticatorData();
      final String signedJson = clientData();
      final String presentedJson = clientData(crossOrigin: true);

      expect(
        verify(
          authData: data,
          json: presentedJson,
          signature: sign(privateKey, data, signedJson),
        ).ok,
        isFalse,
      );
    });

    test('a malformed signature is refused rather than throwing', () {
      expect(
        verify(signature: Uint8List.fromList(<int>[0, 1, 2])).ok,
        isFalse,
      );
    });
  });

  test('malformed client data is refused rather than throwing', () {
    expect(verify(json: 'not json at all').ok, isFalse);
  });
}
