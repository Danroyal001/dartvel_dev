/// CRC-32C (Castagnoli), which Kafka's record batches are checksummed with.
library dartvel_core.queues.crc32c;

import 'dart:typed_data';

/// The reversed Castagnoli polynomial, 0x82F63B78.
///
/// Kafka uses CRC-32C rather than the CRC-32 in zlib, and the two produce
/// different values for the same bytes. A batch checksummed with the wrong one
/// is rejected by the broker as corrupt, which is a confusing way to be told
/// the polynomial is wrong.
final Uint32List _table = _buildTable();

Uint32List _buildTable() {
  final Uint32List table = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    int crc = i;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F63B78 : crc >> 1;
    }
    table[i] = crc;
  }
  return table;
}

/// The CRC-32C of [bytes].
int dvCrc32c(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
