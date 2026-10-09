/// Signing Shorebird patches, the way the updater checks them.
///
/// A release built with a public key refuses every patch whose signature does
/// not verify against it, and boots the last good patch or the release
/// instead (docs.shorebird.dev/code-push/guides/patch-signing). What the
/// updater verifies is fixed by its code, `library/src/cache/signing.rs` in
/// shorebirdtech/updater:
///
///  * the message is the ASCII of the patched file's hex SHA-256 -- the
///    64-character string, not the 32 raw bytes;
///  * the scheme is RSA PKCS#1 v1.5 with SHA-256 (`ring`'s
///    `RSA_PKCS1_2048_8192_SHA256`), so keys are 2048 to 8192 bits;
///  * the signature is standard base64;
///  * the public key the release carries (`patch_public_key` in the bundled
///    shorebird.yaml, which Shorebird's Flutter writes from the
///    `SHOREBIRD_PUBLIC_KEY` build variable) is base64 of a DER PKCS#1
///    RSAPublicKey -- `openssl rsa -pubin -RSAPublicKey_out -outform DER`.
///
/// Keys are PEM files, as `openssl genrsa -out private.pem 2048` and
/// `openssl rsa -in private.pem -pubout -out public.pem` make them; a private
/// key may be PKCS#8 (`BEGIN PRIVATE KEY`) or PKCS#1 (`BEGIN RSA PRIVATE
/// KEY`), a public key SubjectPublicKeyInfo (`BEGIN PUBLIC KEY`) or PKCS#1
/// (`BEGIN RSA PUBLIC KEY`).
library;

import 'dart:convert';
import 'dart:typed_data';

// asn1.dart is not part of pointycastle's export.dart barrel.
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// A key or signature that cannot be used, and why.
class DVPatchSigningException implements Exception {
  const DVPatchSigningException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DVPatchSigning {
  const DVPatchSigning._();

  /// The DigestInfo prefix of SHA-256, which PKCS#1 v1.5 signs under.
  static const String _sha256Oid = '0609608648016503040201';

  static final RegExp _hexSha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Signs [hash], the hex SHA-256 of the patched file, with the PEM private
  /// key [privateKeyPem]. Returns the base64 signature the updater verifies.
  static String signHash(String hash, String privateKeyPem) {
    _checkHash(hash);
    final RSAPrivateKey key = privateKey(privateKeyPem);
    _checkSize(key.modulus!);
    final RSASigner signer = RSASigner(SHA256Digest(), _sha256Oid)
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final RSASignature signature = signer.generateSignature(
      Uint8List.fromList(ascii.encode(hash)),
    );
    return base64.encode(signature.bytes);
  }

  /// Whether [signature] (base64) is a signature of [hash] by the key a
  /// release carries, [releasePublicKey] -- base64 DER PKCS#1, as in
  /// shorebird.yaml's `patch_public_key`. Never throws for a bad signature;
  /// a key that cannot be read is an exception, since it is a configuration
  /// fault and not a forged patch.
  static bool verifyHash(
    String hash,
    String signature,
    String releasePublicKey,
  ) {
    final RSAPublicKey key = _pkcs1PublicKey(_base64(releasePublicKey));
    final Uint8List bytes;
    try {
      bytes = base64.decode(signature.trim());
    } on FormatException {
      return false;
    }
    final RSASigner verifier = RSASigner(SHA256Digest(), _sha256Oid)
      ..init(false, PublicKeyParameter<RSAPublicKey>(key));
    try {
      return verifier.verifySignature(
        Uint8List.fromList(ascii.encode(hash)),
        RSASignature(bytes),
      );
    } on Object {
      return false;
    }
  }

  /// The value a release carries for [publicKeyPem]: base64 of the DER
  /// PKCS#1 RSAPublicKey, which is what `SHOREBIRD_PUBLIC_KEY` takes.
  static String releasePublicKey(String publicKeyPem) {
    final RSAPublicKey key = publicKey(publicKeyPem);
    _checkSize(key.modulus!);
    return base64.encode(_encodePkcs1PublicKey(key));
  }

  /// The release public key of [privateKeyPem]'s key pair, so a patch can be
  /// checked against the release before anything is published.
  static String releasePublicKeyOf(String privateKeyPem) {
    final RSAPrivateKey key = privateKey(privateKeyPem);
    return base64.encode(
      _encodePkcs1PublicKey(
        RSAPublicKey(key.modulus!, _publicExponent(privateKeyPem)),
      ),
    );
  }

  /// The public exponent written in a PEM private key.
  static BigInt _publicExponent(String privateKeyPem) {
    final (String label, Uint8List der) = _pem(privateKeyPem);
    Uint8List pkcs1 = der;
    if (label == 'PRIVATE KEY') {
      pkcs1 = (_sequence(der).elements![2] as ASN1OctetString).valueBytes!;
    }
    return _integer(_sequence(pkcs1), 2);
  }

  /// Reads a PEM RSA public key, SubjectPublicKeyInfo or PKCS#1.
  static RSAPublicKey publicKey(String pem) {
    final (String label, Uint8List der) = _pem(pem);
    switch (label) {
      case 'RSA PUBLIC KEY':
        return _pkcs1PublicKey(der);
      case 'PUBLIC KEY':
        final ASN1Sequence spki = _sequence(der);
        final ASN1Object bits = spki.elements![1];
        if (bits is! ASN1BitString) {
          throw const DVPatchSigningException(
            'The public key is not a SubjectPublicKeyInfo.',
          );
        }
        return _pkcs1PublicKey(Uint8List.fromList(bits.stringValues!));
      default:
        throw DVPatchSigningException(
          'A "$label" PEM block is not an RSA public key. Make one with '
          '`openssl rsa -in private.pem -pubout -out public.pem`.',
        );
    }
  }

  /// Reads a PEM RSA private key, PKCS#8 or PKCS#1.
  static RSAPrivateKey privateKey(String pem) {
    final (String label, Uint8List der) = _pem(pem);
    switch (label) {
      case 'RSA PRIVATE KEY':
        return _pkcs1PrivateKey(der);
      case 'PRIVATE KEY':
        final ASN1Sequence info = _sequence(der);
        final ASN1Object octets = info.elements![2];
        if (octets is! ASN1OctetString) {
          throw const DVPatchSigningException(
            'The private key is not PKCS#8.',
          );
        }
        return _pkcs1PrivateKey(octets.valueBytes!);
      case 'ENCRYPTED PRIVATE KEY':
        throw const DVPatchSigningException(
          'The private key is encrypted. Decrypt it into a file only the '
          'build can read (`openssl pkey -in key.pem -out private.pem`).',
        );
      default:
        throw DVPatchSigningException(
          'A "$label" PEM block is not an RSA private key. Make one with '
          '`openssl genrsa -out private.pem 2048`.',
        );
    }
  }

  static void _checkHash(String hash) {
    if (!_hexSha256.hasMatch(hash)) {
      throw const DVPatchSigningException(
        'What is signed is the patched file\'s hex SHA-256.',
      );
    }
  }

  static void _checkSize(BigInt modulus) {
    final int bits = modulus.bitLength;
    if (bits < 2048 || bits > 8192) {
      throw DVPatchSigningException(
        'The key is $bits bits; the updater verifies RSA keys of 2048 to '
        '8192 bits only, so every device would refuse the patch.',
      );
    }
  }

  static (String, Uint8List) _pem(String pem) {
    final Match? block = RegExp(
      r'-----BEGIN ([A-Z ]+)-----([\s\S]*?)-----END \1-----',
    ).firstMatch(pem);
    if (block == null) {
      throw const DVPatchSigningException('That is not a PEM key file.');
    }
    final String body = block.group(2)!;
    if (body.contains('Proc-Type:')) {
      throw const DVPatchSigningException(
        'The private key is encrypted. Decrypt it first.',
      );
    }
    return (block.group(1)!, _base64(body));
  }

  static Uint8List _base64(String text) {
    try {
      return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const DVPatchSigningException('The key is not valid base64.');
    }
  }

  static ASN1Sequence _sequence(Uint8List der) {
    try {
      final ASN1Object object = ASN1Parser(der).nextObject();
      if (object is ASN1Sequence) return object;
    } on Object {
      // Reported below.
    }
    throw const DVPatchSigningException('The key is not DER.');
  }

  static BigInt _integer(ASN1Sequence sequence, int index) {
    final ASN1Object value = sequence.elements![index];
    if (value is! ASN1Integer) {
      throw const DVPatchSigningException('The key is not an RSA key.');
    }
    return value.integer!;
  }

  static RSAPublicKey _pkcs1PublicKey(Uint8List der) {
    final ASN1Sequence key = _sequence(der);
    if (key.elements == null || key.elements!.length != 2) {
      throw const DVPatchSigningException(
        'The public key is not a PKCS#1 RSAPublicKey.',
      );
    }
    return RSAPublicKey(_integer(key, 0), _integer(key, 1));
  }

  static RSAPrivateKey _pkcs1PrivateKey(Uint8List der) {
    final ASN1Sequence key = _sequence(der);
    if (key.elements == null || key.elements!.length < 9) {
      throw const DVPatchSigningException(
        'The private key is not a PKCS#1 RSAPrivateKey.',
      );
    }
    // No public exponent is passed: pointycastle derives one from d modulo
    // phi(n) and rejects a key whose d was made modulo lambda(n), which is
    // how OpenSSL 3 makes them. Signing needs n and d only; e is read
    // from the key itself by [_publicExponent].
    return RSAPrivateKey(
      _integer(key, 1),
      _integer(key, 3),
      _integer(key, 4),
      _integer(key, 5),
    );
  }

  static Uint8List _encodePkcs1PublicKey(RSAPublicKey key) {
    final ASN1Sequence sequence = ASN1Sequence()
      ..add(ASN1Integer(key.modulus))
      ..add(ASN1Integer(key.exponent));
    return sequence.encode();
  }
}
