/// Reading files out of a zip -- an APK, a downloaded tool -- with dart:io
/// alone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

/// The contents of every entry in the zip at [path] whose name [wanted]
/// accepts. Stored and deflated entries only, which is what APKs and
/// published tool archives use. Throws [FormatException] for anything that
/// is not a readable zip.
Map<String, Uint8List> dvReadZipEntries(
  String path,
  bool Function(String name) wanted,
) {
  final RandomAccessFile file = File(path).openSync();
  try {
    final int length = file.lengthSync();
    final int tail = length < 65557 ? length : 65557;
    file.setPositionSync(length - tail);
    final Uint8List end = file.readSync(tail);
    int at = -1;
    for (int i = end.length - 22; i >= 0; i--) {
      if (_u32(end, i) == 0x06054b50) {
        at = i;
        break;
      }
    }
    if (at < 0) throw FormatException('$path is not a zip.');
    final int count = _u16(end, at + 10);
    final int size = _u32(end, at + 12);
    final int offset = _u32(end, at + 16);
    if (offset + size > length) throw FormatException('$path is truncated.');
    file.setPositionSync(offset);
    final Uint8List central = file.readSync(size);

    final Map<String, Uint8List> found = <String, Uint8List>{};
    int i = 0;
    for (int n = 0; n < count; n++) {
      if (i + 46 > central.length || _u32(central, i) != 0x02014b50) {
        throw FormatException('$path has a malformed central directory.');
      }
      final int method = _u16(central, i + 10);
      final int compressed = _u32(central, i + 20);
      final int nameLength = _u16(central, i + 28);
      final int extra = _u16(central, i + 30);
      final int comment = _u16(central, i + 32);
      final int local = _u32(central, i + 42);
      final String name = utf8.decode(
        central.sublist(i + 46, i + 46 + nameLength),
        allowMalformed: true,
      );
      i += 46 + nameLength + extra + comment;
      if (name.endsWith('/') || !wanted(name)) continue;

      file.setPositionSync(local);
      final Uint8List header = file.readSync(30);
      if (header.length < 30 || _u32(header, 0) != 0x04034b50) {
        throw FormatException('$path has a malformed entry for $name.');
      }
      file.setPositionSync(local + 30 + _u16(header, 26) + _u16(header, 28));
      final Uint8List data = file.readSync(compressed);
      found[name] = switch (method) {
        0 => data,
        8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(data)),
        _ => throw FormatException(
          '$path stores $name with compression method $method.',
        ),
      };
    }
    return found;
  } finally {
    file.closeSync();
  }
}
