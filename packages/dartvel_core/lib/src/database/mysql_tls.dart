/// The TLS upgrade MySQL performs in the middle of its handshake.
library dartvel_core.database.mysql_tls;

import 'dart:typed_data';

import 'postgres_tls.dart' show DVSslMode;

/// `CLIENT_SSL`, the capability bit that says the server will speak TLS.
const int dvMySqlClientSsl = 0x0800;

/// Whether the greeting's capability flags advertise TLS.
bool dvMySqlServerSupportsTls(int capabilities) =>
    capabilities & dvMySqlClientSsl != 0;

/// Whether to ask at all.
bool dvMySqlShouldRequestTls(DVSslMode mode) => mode != DVSslMode.disable;

/// Whether a server that cannot do TLS ends the connection.
///
/// At [DVSslMode.require] and above it must. Continuing would put the password
/// on the wire in the clear while the caller believed the connection was
/// encrypted, which is worse than not connecting at all.
bool dvMySqlRefusalIsFatal(DVSslMode mode) =>
    mode == DVSslMode.require ||
    mode == DVSslMode.verifyCa ||
    mode == DVSslMode.verifyFull;

/// The 32-byte SSLRequest that goes between the greeting and the upgrade.
///
/// MySQL does not negotiate before its protocol starts, the way Postgres does.
/// The server speaks first with a greeting advertising what it supports; the
/// client answers with exactly this packet — the head of a handshake response
/// and nothing else, no username and no auth — the socket is upgraded, and
/// only then does the real handshake response travel encrypted.
///
/// The order is the whole point. Sending the real response first and
/// upgrading afterwards puts the password on the wire in the clear on a
/// connection that then looks encrypted for the rest of its life.
///
/// The server reads a fixed 32 bytes here, so any other length is a protocol
/// error rather than a short read.
Uint8List dvMySqlSslRequest({
  required int clientFlags,
  required int maxPacket,
  required int charset,
}) {
  final Uint8List packet = Uint8List(32);
  final ByteData view = packet.buffer.asByteData();

  // The bit is set here rather than left to the caller. The caller's flags
  // describe the session it wants; this packet is the one that says "and
  // encrypted", and a caller who forgets stays in plaintext silently.
  view.setUint32(0, clientFlags | dvMySqlClientSsl, Endian.little);
  view.setUint32(4, maxPacket, Endian.little);
  view.setUint8(8, charset);
  // The remaining 23 bytes are reserved and must be zero, which they already
  // are.
  return packet;
}
