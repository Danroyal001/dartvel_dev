/// The TLS negotiation Postgres does before its protocol starts.
library dartvel_core.database.postgres_tls;

import 'dart:typed_data';

/// How much the client insists on encryption, matching libpq's `sslmode`.
///
/// The names are libpq's on purpose: a connection string copied from a
/// provider's console carries one of these, and a different vocabulary would
/// make it something to translate rather than something to paste.
enum DVSslMode {
  /// Never ask. Local sockets and test servers.
  disable,

  /// Ask, and carry on in plaintext if the server declines.
  prefer,

  /// Ask, and fail if the server declines. Encrypted, but the certificate is
  /// not checked — it stops passive eavesdropping and not an active attacker.
  require,

  /// As [require], and the certificate must chain to a trusted root.
  verifyCa,

  /// As [verifyCa], and the certificate must be for the host asked for.
  /// The only mode that resists an active attacker, and what a managed
  /// endpoint should be reached with.
  verifyFull,
}

/// What the server said to the SSLRequest.
enum DVPostgresSslReply {
  /// `S` — carry on under TLS.
  proceed,

  /// `N` — this server will not.
  refused,

  /// `E`, or anything unexpected. A server reporting a problem is not a
  /// server declining TLS, and treating it as one would drop to plaintext.
  error,
}

/// The eight bytes that ask.
///
/// Length 8, then 80877103 — the magic number Postgres reserves for this,
/// chosen so it cannot be confused with a protocol version. Nothing has been
/// sent before it, which is why the negotiation is a pure function of these
/// bytes and one byte back.
Uint8List dvPostgresSslRequest() {
  final Uint8List bytes = Uint8List(8);
  final ByteData view = bytes.buffer.asByteData();
  view.setUint32(0, 8);
  view.setUint32(4, 80877103);
  return bytes;
}

/// Read the server's single-byte answer.
DVPostgresSslReply dvPostgresSslReply(int byte) {
  switch (byte) {
    case 0x53: // 'S'
      return DVPostgresSslReply.proceed;
    case 0x4E: // 'N'
      return DVPostgresSslReply.refused;
    default:
      return DVPostgresSslReply.error;
  }
}

/// Whether to send the request at all.
bool dvPostgresShouldRequestTls(DVSslMode mode) => mode != DVSslMode.disable;

/// Whether a refusal ends the connection.
///
/// Under [DVSslMode.require] and above it has to. Falling back to plaintext
/// there would put the password on the wire in the clear while the caller
/// believed the connection was encrypted, which is worse than not connecting.
bool dvPostgresRefusalIsFatal(DVSslMode mode) =>
    mode == DVSslMode.require ||
    mode == DVSslMode.verifyCa ||
    mode == DVSslMode.verifyFull;

/// Whether the certificate's host has to match the one asked for.
///
/// Only [DVSslMode.verifyFull]. `verify-ca` proves the certificate chains to
/// a trusted root; it does not prove you reached the host you asked for.
bool dvPostgresChecksHostname(DVSslMode mode) => mode == DVSslMode.verifyFull;
