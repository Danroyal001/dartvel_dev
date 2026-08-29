// The TLS upgrade MySQL does in the middle of its handshake.
//
// Postgres asks before its protocol starts. MySQL does not: the server speaks
// first with a greeting that advertises what it supports, the client replies
// with a 32-byte SSLRequest, the socket is upgraded, and only then does the
// real handshake response go over the encrypted connection. Getting the order
// wrong sends the password in the clear on a connection that then looks
// encrypted.
//
// PlanetScale, Aurora, Cloud SQL and Azure Database all require it, so without
// this the adapter reached a local server and nothing else.
import 'dart:typed_data';

import 'package:dartvel_core/src/database/mysql_tls.dart';
import 'package:dartvel_core/src/database/postgres_tls.dart' show DVSslMode;
import 'package:test/test.dart';

void main() {
  group('what the server said it supports', () {
    test('the TLS bit is read from the capability flags', () {
      // CLIENT_SSL is 0x0800.
      expect(dvMySqlServerSupportsTls(0x0800), isTrue);
      expect(dvMySqlServerSupportsTls(0xFFFF), isTrue);
      expect(dvMySqlServerSupportsTls(0x0000), isFalse);
      expect(dvMySqlServerSupportsTls(0xF7FF), isFalse);
    });
  });

  group('the SSLRequest packet', () {
    final Uint8List request = dvMySqlSslRequest(
      clientFlags: 0x000A0285,
      maxPacket: 16777215,
      charset: 45,
    );

    test('it is exactly the 32 bytes the server reads', () {
      // The server reads a fixed-size header here and nothing else. A packet
      // of any other length is a protocol error, not a short read.
      expect(request, hasLength(32));
    });

    test('it turns CLIENT_SSL on whatever the caller passed', () {
      // The caller's flags describe the session it wants; this packet is the
      // one that says "and encrypted". Leaving the bit to the caller is how
      // a connection silently stays plaintext.
      final int flags = request.buffer.asByteData().getUint32(0, Endian.little);

      expect(flags & 0x0800, 0x0800);
      expect(flags & 0x000A0285, 0x000A0285, reason: 'the rest survives');
    });

    test('the max packet size and charset are where the server looks', () {
      final ByteData view = request.buffer.asByteData();

      expect(view.getUint32(4, Endian.little), 16777215);
      expect(view.getUint8(8), 45);
    });

    test('the last 23 bytes are the reserved filler', () {
      expect(request.sublist(9), everyElement(0));
    });
  });

  group('what a refusal means', () {
    test('require and above will not carry on without it', () {
      // The whole point of the mode. Continuing would put the password on the
      // wire in the clear while the caller believed otherwise.
      expect(dvMySqlRefusalIsFatal(DVSslMode.require), isTrue);
      expect(dvMySqlRefusalIsFatal(DVSslMode.verifyCa), isTrue);
      expect(dvMySqlRefusalIsFatal(DVSslMode.verifyFull), isTrue);
    });

    test('prefer and disable carry on', () {
      expect(dvMySqlRefusalIsFatal(DVSslMode.prefer), isFalse);
      expect(dvMySqlRefusalIsFatal(DVSslMode.disable), isFalse);
    });

    test('disable does not ask at all', () {
      expect(dvMySqlShouldRequestTls(DVSslMode.disable), isFalse);
      expect(dvMySqlShouldRequestTls(DVSslMode.prefer), isTrue);
      expect(dvMySqlShouldRequestTls(DVSslMode.verifyFull), isTrue);
    });
  });
}
