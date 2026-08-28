// The TLS handshake every managed Postgres requires.
//
// The adapter spoke the wire protocol in plaintext only, so it could reach a
// local server and nothing else. Aurora, Neon, Supabase, Cloud SQL and
// PlanetScale all require TLS and most refuse a plaintext connection outright
// -- so "Postgres and Postgres compatible" stopped at the edge of localhost.
//
// Postgres negotiates before the protocol starts: the client sends an
// eight-byte SSLRequest, and the server answers with a single byte, 'S' to
// proceed under TLS or 'N' to refuse. Nothing else is exchanged first, which
// is why this is testable without a socket.
import 'dart:typed_data';

import 'package:dartvel_core/src/database/postgres_tls.dart';
import 'package:test/test.dart';

void main() {
  group('the request', () {
    test('it is the eight bytes the server expects', () {
      final Uint8List request = dvPostgresSslRequest();

      expect(request, hasLength(8));
      // Length 8, then the magic 80877103 (1234 << 16 | 5679).
      expect(request.buffer.asByteData().getUint32(0), 8);
      expect(request.buffer.asByteData().getUint32(4), 80877103);
    });
  });

  group('the answer', () {
    test("'S' means the server will speak TLS", () {
      expect(dvPostgresSslReply(0x53), DVPostgresSslReply.proceed);
    });

    test("'N' means it will not", () {
      expect(dvPostgresSslReply(0x4E), DVPostgresSslReply.refused);
    });

    test('an error response is neither', () {
      // A server that answers 'E' is reporting a problem, not declining TLS,
      // and treating it as a refusal would silently drop to plaintext.
      expect(dvPostgresSslReply(0x45), DVPostgresSslReply.error);
    });

    test('anything else is an error rather than a guess', () {
      expect(dvPostgresSslReply(0x00), DVPostgresSslReply.error);
      expect(dvPostgresSslReply(0x7A), DVPostgresSslReply.error);
    });
  });

  group('what the mode decides', () {
    test('disable never asks', () {
      expect(dvPostgresShouldRequestTls(DVSslMode.disable), isFalse);
    });

    test('require, verifyCa and verifyFull all ask', () {
      for (final DVSslMode mode in <DVSslMode>[
        DVSslMode.require,
        DVSslMode.verifyCa,
        DVSslMode.verifyFull,
      ]) {
        expect(dvPostgresShouldRequestTls(mode), isTrue, reason: '$mode');
      }
    });

    test('a refusal is fatal under require, and not under prefer', () {
      // The distinction the mode exists for. Under require, falling back to
      // plaintext would send the password over the wire in the clear while
      // the caller believed the connection was encrypted.
      expect(dvPostgresRefusalIsFatal(DVSslMode.require), isTrue);
      expect(dvPostgresRefusalIsFatal(DVSslMode.verifyFull), isTrue);
      expect(dvPostgresRefusalIsFatal(DVSslMode.prefer), isFalse);
      expect(dvPostgresRefusalIsFatal(DVSslMode.disable), isFalse);
    });

    test('only verifyFull checks the hostname', () {
      // verify-ca proves the certificate chains to a trusted root; it does
      // not prove you reached the host you asked for.
      expect(dvPostgresChecksHostname(DVSslMode.verifyFull), isTrue);
      expect(dvPostgresChecksHostname(DVSslMode.verifyCa), isFalse);
      expect(dvPostgresChecksHostname(DVSslMode.require), isFalse);
    });
  });
}
