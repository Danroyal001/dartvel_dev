// LDAP's BER encoding, pinned to bytes.
//
// This is the part where being nearly right is indistinguishable from being
// right until a real server is on the other end. A length field off by one is
// not visible in any Dart value: the encoder returns a list, the list looks
// fine, and the directory closes the connection without saying why.
//
// So these assert the actual bytes, computed by hand from X.690, rather than
// round-tripping through this file's own decoder -- which would agree with any
// mistake it shares.
import 'dart:convert';

import 'package:dartvel_core/src/auth/ldap.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  group('lengths', () {
    test('under 128 is a single byte', () {
      expect(DVBer.length(0), <int>[0x00]);
      expect(DVBer.length(1), <int>[0x01]);
      expect(DVBer.length(127), <int>[0x7f]);
    });

    test('128 crosses into the long form', () {
      // The boundary. Emitting 0x80 alone here means "indefinite length",
      // which is a different message entirely.
      expect(DVBer.length(128), <int>[0x81, 0x80]);
    });

    test('255 still fits one length byte', () {
      expect(DVBer.length(255), <int>[0x81, 0xff]);
    });

    test('256 needs two', () {
      expect(DVBer.length(256), <int>[0x82, 0x01, 0x00]);
    });

    test('a large value keeps its byte order', () {
      expect(DVBer.length(0x12345), <int>[0x83, 0x01, 0x23, 0x45]);
    });
  });

  group('integers', () {
    test('zero is one content byte, not zero', () {
      // An empty INTEGER is invalid BER; some servers reject the whole message.
      expect(DVBer.int32(0), <int>[0x02, 0x01, 0x00]);
    });

    test('small values are minimal', () {
      expect(DVBer.int32(1), <int>[0x02, 0x01, 0x01]);
      expect(DVBer.int32(3), <int>[0x02, 0x01, 0x03]);
      expect(DVBer.int32(127), <int>[0x02, 0x01, 0x7f]);
    });

    test('a high top bit gains a leading zero', () {
      // BER integers are signed. Without the pad, 128 reads as -128 and a
      // message id or size limit silently becomes negative.
      expect(DVBer.int32(128), <int>[0x02, 0x02, 0x00, 0x80]);
      expect(DVBer.int32(255), <int>[0x02, 0x02, 0x00, 0xff]);
    });

    test('a value that does not need padding does not get it', () {
      expect(DVBer.int32(256), <int>[0x02, 0x02, 0x01, 0x00]);
    });
  });

  group('strings', () {
    test('an octet string carries its byte length', () {
      expect(DVBer.string('abc'), <int>[0x04, 0x03, 0x61, 0x62, 0x63]);
    });

    test('an empty string is a zero-length element, not an absent one', () {
      expect(DVBer.string(''), <int>[0x04, 0x00]);
    });

    test('a multi-byte character is measured in bytes, not code units', () {
      // The length is UTF-8 bytes. Writing the Dart string length here sends a
      // short length and the server reads the remainder as the next element.
      final List<int> encoded = DVBer.string('é');
      expect(encoded, <int>[0x04, 0x02, 0xc3, 0xa9]);
      expect(encoded[1], utf8.encode('é').length);
    });
  });

  group('a bind request', () {
    test('is the exact message a directory expects', () {
      // LDAPMessage ::= SEQUENCE { messageID INTEGER, BindRequest }
      // BindRequest ::= [APPLICATION 0] SEQUENCE {
      //   version INTEGER, name LDAPDN, simple [0] OCTET STRING }
      final List<int> bindRequest = DVBer.tlv(DVBer.bindRequest, <int>[
        ...DVBer.int32(3),
        ...DVBer.string('cn=admin'),
        ...DVBer.tlv(0x80, utf8.encode('secret')),
      ]);
      final List<int> message = DVBer.tlv(DVBer.sequence, <int>[
        ...DVBer.int32(1),
        ...bindRequest,
      ]);

      // Lengths counted rather than eyeballed, because I got them wrong the
      // first time and the encoder was right:
      //   version   02 01 03                     ->  3 bytes
      //   name      04 08 "cn=admin"             -> 10 bytes
      //   simple    80 06 "secret"               ->  8 bytes
      //   BindRequest content                    -> 21 = 0x15
      //   messageID 02 01 01                     ->  3 bytes
      //   BindRequest element  60 15 + 21        -> 23 bytes
      //   LDAPMessage content                    -> 26 = 0x1a
      expect(
        hex(message),
        '30 1a 02 01 01 60 15 02 01 03 04 08 63 6e 3d 61 64 6d 69 6e '
        '80 06 73 65 63 72 65 74',
      );
    });

    test('the password is a primitive context tag, not an octet string', () {
      // 0x80, not 0x04. A server reading 0x04 there sees a malformed
      // BindRequest and drops the connection with no message.
      final List<int> simple = DVBer.tlv(0x80, utf8.encode('pw'));

      expect(simple.first, 0x80);
    });
  });

  test('an unbind request is an empty application element', () {
    // [APPLICATION 2] with no content. Sending a SEQUENCE here is a different
    // operation.
    expect(DVBer.tlv(DVBer.unbindRequest, const <int>[]), <int>[0x42, 0x00]);
  });

  test('a long value encodes its length in the long form end to end', () {
    // 200 bytes crosses the 127 boundary inside a real element, which is where
    // a short-form bug actually bites.
    final String long = 'a' * 200;
    final List<int> encoded = DVBer.string(long);

    expect(encoded[0], 0x04);
    expect(encoded[1], 0x81);
    expect(encoded[2], 200);
    expect(encoded.length, 203);
  });
}
