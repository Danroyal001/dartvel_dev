// CRC-32C, against values that are not this implementation's own output.
//
// A checksum tested only against itself passes whatever it computes. These
// vectors come from RFC 3720 appendix B, which is where the iSCSI
// specification pins CRC-32C, and Kafka uses the same polynomial.
import 'package:dartvel_core/src/queues/crc32c.dart';
import 'package:test/test.dart';

void main() {
  test('the empty input', () {
    expect(dvCrc32c(<int>[]), 0);
  });

  test('thirty-two zero bytes', () {
    // RFC 3720 B.4: 32 bytes of zero.
    expect(dvCrc32c(List<int>.filled(32, 0)), 0x8A9136AA);
  });

  test('thirty-two 0xFF bytes', () {
    expect(dvCrc32c(List<int>.filled(32, 0xFF)), 0x62A8AB43);
  });

  test('the bytes 0 to 31 in order', () {
    expect(dvCrc32c(List<int>.generate(32, (int i) => i)), 0x46DD794E);
  });

  test('"123456789", the standard check value', () {
    expect(dvCrc32c('123456789'.codeUnits), 0xE3069283);
  });

  test('it is not CRC-32, which would silently corrupt every batch', () {
    // zlib's CRC-32 of "123456789" is 0xCBF43926. Kafka rejects a batch
    // checksummed with it, and the error says corrupt rather than wrong
    // polynomial.
    expect(dvCrc32c('123456789'.codeUnits), isNot(0xCBF43926));
  });
}
