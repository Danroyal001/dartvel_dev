// The ECDSA signature itself, pinned to RFC 6979's published vectors.
//
// The VAPID suite next door verifies RFC 8292's own token with RFC 8292's own
// key, which proves the *verifier*. The signer was only ever round-tripped
// through that verifier, and a signer whose mistake the verifier mirrors would
// pass: both read the token's segments back, so neither notices if the bytes
// they agree on are the wrong bytes.
//
// Ordinary ECDSA cannot be pinned to a published example, because the
// signature depends on a random k nobody publishes. This implementation does
// not use a random k -- it derives k from the key and the message per RFC
// 6979, which is a security property first (a repeated k leaks the private
// key) and makes the output reproducible second.
//
// So the exact signature is a published fact. RFC 6979 A.2.5 gives P-256 with
// SHA-256: a private key, two messages, and the r and s each must produce.
// Anything that changes the curve, the digest, the k derivation or the
// integer encoding moves these bytes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// RFC 6979 A.2.5, "private key".
const String rfcPrivateKeyHex =
    'C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721';

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  group('RFC 6979 A.2.5, P-256 with SHA-256', () {
    final key = hexToBytes(rfcPrivateKeyHex);

    test('message "sample" produces the published r and s', () {
      const String r =
          'EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716';
      const String s =
          'F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8';

      final signature = dvWebPushSignEs256(utf8.encode('sample'), key);

      expect(signature.length, 64, reason: 'JWS wants a fixed-width r||s');
      expect(bytesToHex(signature.sublist(0, 32)), r);
      expect(bytesToHex(signature.sublist(32)), s);
    });

    test('message "test" produces the published r and s', () {
      const String r =
          'F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367';
      // Note the leading zero byte. An implementation that stripped it, or
      // that emitted the minimal big-endian integer DER would use, produces
      // 63 bytes here and a signature every push service rejects.
      const String s =
          '019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083';

      final signature = dvWebPushSignEs256(utf8.encode('test'), key);

      expect(bytesToHex(signature.sublist(0, 32)), r);
      expect(bytesToHex(signature.sublist(32)), s);
      expect(signature[32], 0x01,
          reason: 's begins 01, so byte 32 pins the padding');
    });

    test('the same message signs identically every time', () {
      // Not a tautology: it is the property that makes the vectors above
      // checkable at all, and the one a random k would remove.
      final first = dvWebPushSignEs256(utf8.encode('sample'), key);
      final second = dvWebPushSignEs256(utf8.encode('sample'), key);

      expect(first, orderedEquals(second));
    });

    test('a different message signs differently', () {
      final sample = dvWebPushSignEs256(utf8.encode('sample'), key);
      final other = dvWebPushSignEs256(utf8.encode('test'), key);

      expect(sample, isNot(orderedEquals(other)));
    });
  });
}
