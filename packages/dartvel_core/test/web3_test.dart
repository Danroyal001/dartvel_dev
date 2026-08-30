// Web3 sign-in.
//
// A signature over a message is valid forever, so the cryptography is the easy
// half. What makes this a login rather than a permanent bearer credential is
// the nonce, the domain and the time window -- and a verifier that skips any
// of them still returns a signed-in user.
//
// Keccak is pinned to its published digest rather than to this code's own
// output: Ethereum uses original Keccak-256, not SHA3-256, and substituting
// one derives a different, entirely plausible address from every key.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

String hex(Uint8List bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Signs [message] the way a wallet does, returning 65-byte r||s||v.
Uint8List walletSign(BigInt privateKey, String message) {
  final ECDomainParameters domain = ECDomainParameters('secp256k1');
  final Uint8List hash = dvPersonalSignHash(message);

  final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(privateKey, domain)),
    );
  ECSignature signature = signer.generateSignature(hash) as ECSignature;

  // Wallets normalise s into the low half; a high-s signature is the malleable
  // twin of the same signature.
  if (signature.s > (domain.n >> 1)) {
    signature = ECSignature(signature.r, domain.n - signature.s);
  }

  final ECPoint expected = (domain.G * privateKey)!;
  for (int v = 0; v < 2; v += 1) {
    final Uint8List candidate = Uint8List.fromList(<int>[
      ..._bytes(signature.r),
      ..._bytes(signature.s),
      27 + v,
    ]);
    final String? recovered = dvRecoverSigner(message, candidate);
    if (recovered != null &&
        recovered.toLowerCase() ==
            dvEthereumAddress(expected.getEncoded(false)).toLowerCase()) {
      return candidate;
    }
  }
  throw StateError('no recovery id produced the signing address');
}

List<int> _bytes(BigInt value) {
  final Uint8List out = Uint8List(32);
  BigInt remaining = value;
  for (int i = 31; i >= 0; i -= 1) {
    out[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return out;
}

final BigInt privateKey = BigInt.parse(
  '4646464646464646464646464646464646464646464646464646464646464646',
  radix: 16,
);

String get address {
  final ECDomainParameters domain = ECDomainParameters('secp256k1');
  return dvEthereumAddress((domain.G * privateKey)!.getEncoded(false));
}

String siwe({
  String domain = 'app.example',
  String? forAddress,
  String nonce = 'abc123xyz',
  DateTime? issuedAt,
  DateTime? expirationTime,
  DateTime? notBefore,
}) {
  final StringBuffer out = StringBuffer()
    ..writeln('$domain wants you to sign in with your Ethereum account:')
    ..writeln(forAddress ?? address)
    ..writeln()
    ..writeln('Sign in to Dartvel.')
    ..writeln()
    ..writeln('URI: https://$domain')
    ..writeln('Version: 1')
    ..writeln('Chain ID: 1')
    ..writeln('Nonce: $nonce')
    ..write('Issued At: '
        '${(issuedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String()}');
  if (expirationTime != null) {
    out.write('\nExpiration Time: ${expirationTime.toIso8601String()}');
  }
  if (notBefore != null) {
    out.write('\nNot Before: ${notBefore.toIso8601String()}');
  }
  return out.toString();
}

void main() {
  group('keccak', () {
    test('matches the published digest of the empty string', () {
      // The check that this is Keccak-256 and not SHA3-256. SHA3-256 of the
      // empty string is a completely different value, and a build that
      // silently used it would derive wrong addresses everywhere.
      expect(
        hex(dvKeccak256(<int>[])),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
    });

    test('matches the published digest of "abc"', () {
      expect(
        hex(dvKeccak256(utf8.encode('abc'))),
        '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
      );
    });
  });

  group('addresses', () {
    test('EIP-55 checksums the known example', () {
      // From the EIP-55 specification's own list.
      expect(
        dvToChecksumAddress('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'),
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
      expect(
        dvToChecksumAddress('0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359'),
        '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      );
    });

    test('an already-checksummed address round-trips', () {
      const String checksummed = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

      expect(dvToChecksumAddress(checksummed), checksummed);
    });
  });

  group('recovery', () {
    test('a signature recovers the address that produced it', () {
      final Uint8List signature = walletSign(privateKey, 'hello dartvel');

      expect(dvRecoverSigner('hello dartvel', signature), address);
    });

    test('a different message recovers a different address', () {
      // Recovery always yields *some* address. A verifier that does not
      // compare it to the expected one accepts every signature there is.
      final Uint8List signature = walletSign(privateKey, 'hello dartvel');

      expect(dvRecoverSigner('goodbye dartvel', signature), isNot(address));
    });

    test('a high-s signature is refused as malleable', () {
      // The same signature exists with n - s and recovers a different address.
      // Accepting both lets one signature authenticate two identities.
      final ECDomainParameters domain = ECDomainParameters('secp256k1');
      final Uint8List valid = walletSign(privateKey, 'hello dartvel');
      final BigInt s = BigInt.parse(hex(Uint8List.sublistView(valid, 32, 64)),
          radix: 16);
      final Uint8List malleable = Uint8List.fromList(<int>[
        ...Uint8List.sublistView(valid, 0, 32),
        ..._bytes(domain.n - s),
        valid[64] == 27 ? 28 : 27,
      ]);

      expect(dvRecoverSigner('hello dartvel', malleable), isNull);
    });

    test('a malformed signature is refused rather than throwing', () {
      expect(dvRecoverSigner('hello', Uint8List(65)), isNull);
      expect(dvRecoverSigner('hello', Uint8List.fromList(<int>[1, 2, 3])),
          isNull);
    });

    test('an out-of-range recovery id is refused', () {
      final Uint8List signature = walletSign(privateKey, 'hello dartvel');
      final Uint8List bad = Uint8List.fromList(signature)..[64] = 9;

      expect(dvRecoverSigner('hello dartvel', bad), isNull);
    });
  });

  group('sign-in', () {
    test('a well-formed message and signature signs the user in', () {
      final String message = siwe();
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isTrue, reason: result.reason);
      expect(result.address, address);
    });

    test('a nonce the server did not issue is refused', () {
      // Without this the signature is a bearer token that never expires.
      final String message = siwe(nonce: 'replayed');
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isFalse);
      expect(result.reason, contains('nonce'));
    });

    test('a message issued for another domain is refused', () {
      // A signature collected by any dapp the user visits would otherwise be a
      // login here.
      final String message = siwe(domain: 'evil.example');
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isFalse);
    });

    test('an expired message is refused', () {
      final String message = siwe(expirationTime: DateTime.utc(2026, 1, 1, 12));
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isFalse);
      expect(result.reason, contains('expired'));
    });

    test('a message not yet valid is refused', () {
      final String message = siwe(notBefore: DateTime.utc(2026, 6, 1));
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isFalse);
    });

    test('a signature from another key is refused', () {
      final String message = siwe();
      final BigInt other = BigInt.parse(
        '1111111111111111111111111111111111111111111111111111111111111111',
        radix: 16,
      );

      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(other, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isFalse);
    });

    test('a lower-case address in the message still matches', () {
      // Wallets write the address either way; refusing on case would turn a
      // perfectly good signature into a failed login.
      final String message = siwe(forAddress: address.toLowerCase());
      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: walletSign(privateKey, message),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
        now: DateTime.utc(2026, 1, 2),
      );

      expect(result.ok, isTrue, reason: result.reason);
    });

    test('a message missing a nonce is refused, not treated as nonce-free', () {
      const String message = 'app.example wants you to sign in with your '
          'Ethereum account:\n0x0000000000000000000000000000000000000001\n\n'
          'URI: https://app.example\nVersion: 1\nChain ID: 1\n'
          'Issued At: 2026-01-01T00:00:00.000Z';

      final DVWeb3Verification result = dvVerifySiwe(
        message: message,
        signature: Uint8List(65),
        expectedDomain: 'app.example',
        expectedNonce: 'abc123xyz',
      );

      expect(result.ok, isFalse);
    });
  });
}
