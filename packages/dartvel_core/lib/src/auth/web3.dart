/// Web3 sign-in: proving control of an Ethereum address.
///
/// There is no password and no token to check against a server. The user signs
/// a message with their private key and the server recovers which address must
/// have produced that signature. Everything therefore rests on the message
/// being one the server issued and has not seen before -- a signature is
/// perfectly valid forever, so a verifier that does not bind it to a nonce, a
/// domain and a time window is a login anyone can replay.
///
/// The message format is EIP-4361 (Sign-In with Ethereum) hashed under
/// EIP-191's `personal_sign` prefix, which is what wallets actually sign.
library dartvel_core.auth.web3;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Keccak-256, which is what Ethereum uses.
///
/// Not SHA3-256: they differ in padding, produce different digests, and
/// substituting one silently derives the wrong address from every key.
Uint8List dvKeccak256(List<int> input) =>
    KeccakDigest(256).process(Uint8List.fromList(input));

/// The EIP-191 `personal_sign` digest of [message].
///
/// The prefix is what stops a signed login being replayable as a transaction:
/// a wallet will not sign raw bytes for `personal_sign`, so anything signed
/// this way cannot also be valid transaction RLP.
Uint8List dvPersonalSignHash(String message) {
  final List<int> payload = utf8.encode(message);
  return dvKeccak256(<int>[
    ...utf8.encode('Ethereum Signed Message:\n${payload.length}'),
    ...payload,
  ]);
}

/// The address for an uncompressed secp256k1 public key.
///
/// Keccak-256 of the 64 body bytes -- the `0x04` tag is dropped -- and the low
/// 20 bytes of that. Including the tag produces a different, plausible-looking
/// address for every key.
String dvEthereumAddress(Uint8List uncompressedPublicKey) {
  final Uint8List body = uncompressedPublicKey.length == 65
      ? Uint8List.sublistView(uncompressedPublicKey, 1)
      : uncompressedPublicKey;
  final Uint8List hash = dvKeccak256(body);
  final String hex = Uint8List.sublistView(hash, 12)
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return dvToChecksumAddress('0x$hex');
}

/// EIP-55 mixed-case checksum encoding.
///
/// Worth doing rather than lower-casing: the checksum is the only thing that
/// catches a mistyped address before funds or access move.
String dvToChecksumAddress(String address) {
  final String hex = address.toLowerCase().replaceFirst('0x', '');
  final Uint8List hash = dvKeccak256(utf8.encode(hex));
  final StringBuffer out = StringBuffer('0x');
  for (int i = 0; i < hex.length; i += 1) {
    final int nibble = i.isEven ? hash[i ~/ 2] >> 4 : hash[i ~/ 2] & 0x0f;
    out.write(nibble >= 8 ? hex[i].toUpperCase() : hex[i]);
  }
  return out.toString();
}

/// Recovers the address that produced [signature] over [message].
///
/// [signature] is the 65-byte r||s||v a wallet returns. Null when it does not
/// recover -- a malformed signature is a refusal, not an exception, because
/// this runs on input from whoever is trying to log in.
String? dvRecoverSigner(String message, Uint8List signature) {
  if (signature.length != 65) return null;

  final BigInt r = _toBigInt(Uint8List.sublistView(signature, 0, 32));
  final BigInt s = _toBigInt(Uint8List.sublistView(signature, 32, 64));
  int v = signature[64];
  // Wallets send 27/28; EIP-155 chains send 35 + 2 * chainId. Both reduce to a
  // recovery id of 0 or 1.
  if (v >= 35) {
    v = (v - 35) % 2;
  } else if (v >= 27) {
    v -= 27;
  }
  if (v != 0 && v != 1) return null;

  final ECDomainParameters domain = ECDomainParameters('secp256k1');
  final BigInt n = domain.n;
  if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return null;

  // Signatures with high s are malleable: the same signature exists with
  // n - s and recovers a different address, so a verifier that accepts both
  // lets one signature authenticate two identities.
  if (s > (n >> 1)) return null;

  try {
    final Uint8List hash = dvPersonalSignHash(message);
    final BigInt e = _toBigInt(hash);

    // R, reconstructed from r with the parity the recovery id names.
    final Uint8List encoded = Uint8List(33)
      ..[0] = v == 0 ? 0x02 : 0x03
      ..setRange(1, 33, _toBytes(r, 32));
    final ECPoint? pointR = domain.curve.decodePoint(encoded);
    if (pointR == null || !(pointR * n)!.isInfinity) return null;

    // Q = r^-1 (sR - eG)
    final BigInt rInverse = r.modInverse(n);
    final ECPoint? q =
        ((pointR * s)! - (domain.G * e)!)! * rInverse;
    if (q == null) return null;

    return dvEthereumAddress(q.getEncoded(false));
  } on Object {
    return null;
  }
}

/// A parsed EIP-4361 sign-in message.
class DVSiweMessage {
  const DVSiweMessage({
    required this.domain,
    required this.address,
    required this.uri,
    required this.version,
    required this.chainId,
    required this.nonce,
    required this.issuedAt,
    this.statement,
    this.expirationTime,
    this.notBefore,
  });

  final String domain;
  final String address;
  final String? statement;
  final String uri;
  final String version;
  final int chainId;
  final String nonce;
  final DateTime issuedAt;
  final DateTime? expirationTime;
  final DateTime? notBefore;

  /// Parses the EIP-4361 text a wallet was asked to sign. Null when it is not
  /// a well-formed message: a verifier must not guess at fields it cannot
  /// find, because a missing nonce reads as "no replay protection required".
  static DVSiweMessage? parse(String message) {
    final List<String> lines = message.split('\n');
    if (lines.length < 6) return null;

    final RegExpMatch? header =
        RegExp(r'^(.+?) wants you to sign in with your Ethereum account:$')
            .firstMatch(lines[0]);
    if (header == null) return null;
    final String address = lines[1].trim();
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) return null;

    String? field(String name) {
      for (final String line in lines) {
        if (line.startsWith('$name: ')) {
          return line.substring(name.length + 2).trim();
        }
      }
      return null;
    }

    final String? uri = field('URI');
    final String? version = field('Version');
    final String? chainId = field('Chain ID');
    final String? nonce = field('Nonce');
    final String? issuedAt = field('Issued At');
    if (uri == null ||
        version == null ||
        chainId == null ||
        nonce == null ||
        issuedAt == null) {
      return null;
    }

    DateTime? time(String? value) =>
        value == null ? null : DateTime.tryParse(value);
    final DateTime? issued = time(issuedAt);
    if (issued == null) return null;

    // The statement is the optional free-text line between the address and the
    // blank line before URI.
    String? statement;
    if (lines.length > 3 && lines[2].trim().isEmpty && lines[3].trim().isNotEmpty) {
      statement = lines[3].trim();
    }

    return DVSiweMessage(
      domain: header.group(1)!,
      address: address,
      statement: statement,
      uri: uri,
      version: version,
      chainId: int.tryParse(chainId) ?? 0,
      nonce: nonce,
      issuedAt: issued,
      expirationTime: time(field('Expiration Time')),
      notBefore: time(field('Not Before')),
    );
  }
}

/// The outcome of a Web3 sign-in.
class DVWeb3Verification {
  const DVWeb3Verification._(this.ok, this.reason, this.address);

  const DVWeb3Verification.failed(String reason)
      : this._(false, reason, null);

  const DVWeb3Verification.passed(String address)
      : this._(true, null, address);

  final bool ok;
  final String? reason;

  /// The checksummed address that signed. Null when refused.
  final String? address;
}

/// Verifies a Sign-In with Ethereum message and its signature.
///
/// A signature never expires, so the checks that make this a login rather than
/// a permanent credential are the nonce, the domain and the time window --
/// not the cryptography.
DVWeb3Verification dvVerifySiwe({
  required String message,
  required Uint8List signature,
  required String expectedDomain,
  required String expectedNonce,
  DateTime? now,
}) {
  final DVSiweMessage? parsed = DVSiweMessage.parse(message);
  if (parsed == null) {
    return const DVWeb3Verification.failed(
      'The message was not a well-formed EIP-4361 request.',
    );
  }

  // Bound to the site that issued it, or a signature collected by any dapp the
  // user visits is a login here.
  if (parsed.domain != expectedDomain) {
    return DVWeb3Verification.failed(
      'The message was issued for "${parsed.domain}", not $expectedDomain.',
    );
  }

  // Bound to one attempt, or the signature is a bearer token forever.
  if (parsed.nonce != expectedNonce) {
    return const DVWeb3Verification.failed(
      'The nonce did not match the one issued.',
    );
  }

  final DateTime at = now ?? DateTime.now().toUtc();
  if (parsed.expirationTime != null && !at.isBefore(parsed.expirationTime!)) {
    return const DVWeb3Verification.failed('The message has expired.');
  }
  if (parsed.notBefore != null && at.isBefore(parsed.notBefore!)) {
    return const DVWeb3Verification.failed('The message is not yet valid.');
  }

  final String? recovered = dvRecoverSigner(message, signature);
  if (recovered == null) {
    return const DVWeb3Verification.failed(
      'The signature did not recover an address.',
    );
  }

  // Compared case-insensitively: the message may carry a lower-case address
  // while recovery produces the checksummed form, and rejecting on case would
  // refuse a perfectly good signature.
  if (recovered.toLowerCase() != parsed.address.toLowerCase()) {
    return DVWeb3Verification.failed(
      'The signature was produced by $recovered, not ${parsed.address}.',
    );
  }

  return DVWeb3Verification.passed(recovered);
}

BigInt _toBigInt(Uint8List bytes) {
  BigInt value = BigInt.zero;
  for (final int byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _toBytes(BigInt value, int length) {
  final Uint8List out = Uint8List(length);
  BigInt remaining = value;
  for (int i = length - 1; i >= 0; i -= 1) {
    out[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return out;
}
