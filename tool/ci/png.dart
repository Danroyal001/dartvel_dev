/// Writes PNGs, for the CI steps that need a picture rather than a library.
///
///     dart tool/ci/png.dart solid out.png 80 80 4B3B82   # a filled tile
///     dart tool/ci/png.dart from-ppm frame.ppm frame.png # a captured frame
///
/// Two jobs that both come down to the same four chunks. webOS shows an icon
/// on the home screen and refuses a package whose appinfo names one that is
/// not there, and a framebuffer capture arrives as a PPM that nothing else
/// reads.
///
/// dart:io gives zlib; the CRC is the eight lines below. No package imports,
/// so this runs from a checkout with nothing resolved.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: png.dart solid <out> <w> <h> <rrggbb>');
    stderr.writeln('       png.dart from-ppm <in.ppm> <out.png>');
    return 2;
  }
  switch (arguments.first) {
    case 'solid':
      if (arguments.length != 5) return _usage();
      final int width = int.parse(arguments[2]);
      final int height = int.parse(arguments[3]);
      final int colour = int.parse(arguments[4], radix: 16);
      final List<int> pixel = <int>[
        (colour >> 16) & 0xFF,
        (colour >> 8) & 0xFF,
        colour & 0xFF,
      ];
      final BytesBuilder rows = BytesBuilder();
      for (int y = 0; y < height; y++) {
        // The filter byte, then the row. Zero is "none", which is what a
        // solid colour compresses to nothing anyway.
        rows.addByte(0);
        for (int x = 0; x < width; x++) {
          rows.add(pixel);
        }
      }
      File(arguments[1])
          .writeAsBytesSync(_png(width, height, rows.takeBytes()));
      return 0;
    case 'from-ppm':
      if (arguments.length != 3) return _usage();
      final Uint8List data = File(arguments[1]).readAsBytesSync();
      final (int width, int height, int offset)? header = _ppmHeader(data);
      if (header == null) {
        stderr.writeln('${arguments[1]} is not a binary PPM');
        return 1;
      }
      final (int width, int height, int start) = header;
      final BytesBuilder rows = BytesBuilder();
      for (int y = 0; y < height; y++) {
        rows.addByte(0);
        rows.add(data.sublist(start + y * width * 3, start + (y + 1) * width * 3));
      }
      File(arguments[2])
          .writeAsBytesSync(_png(width, height, rows.takeBytes()));
      return 0;
    default:
      return _usage();
  }
}

int _usage() {
  stderr.writeln('usage: png.dart solid <out> <w> <h> <rrggbb>');
  stderr.writeln('       png.dart from-ppm <in.ppm> <out.png>');
  return 2;
}

/// The width, height and where the pixels start in a binary (P6) PPM.
///
/// Read field by field rather than by splitting on newlines: the maximum
/// value and the dimensions may share a line or be separated by comments,
/// and a reader that assumed one shape produced an image offset by a few
/// bytes -- which is a picture that is almost right, and the worst kind to
/// debug.
(int, int, int)? _ppmHeader(Uint8List data) {
  int at = 0;
  String field() {
    while (at < data.length) {
      final int byte = data[at];
      if (byte == 0x23) {
        while (at < data.length && data[at] != 0x0A) {
          at++;
        }
        continue;
      }
      if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
        at++;
        continue;
      }
      break;
    }
    final int start = at;
    while (at < data.length) {
      final int byte = data[at];
      if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) break;
      at++;
    }
    return ascii.decode(data.sublist(start, at));
  }

  if (field() != 'P6') return null;
  final int? width = int.tryParse(field());
  final int? height = int.tryParse(field());
  final int? maximum = int.tryParse(field());
  if (width == null || height == null || maximum != 255) return null;
  // Exactly one whitespace byte after the maximum, and the pixels follow.
  return (width, height, at + 1);
}

/// A truecolour, eight-bit PNG of [rows], which are filter-prefixed already.
Uint8List _png(int width, int height, Uint8List rows) {
  final BytesBuilder out = BytesBuilder()
    ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final BytesBuilder header = BytesBuilder()
    ..add(_be32(width))
    ..add(_be32(height))
    ..add(<int>[8, 2, 0, 0, 0]);
  out.add(_chunk('IHDR', header.takeBytes()));
  out.add(_chunk(
      'IDAT', Uint8List.fromList(ZLibEncoder().convert(rows))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String tag, Uint8List body) {
  final Uint8List tagged = Uint8List.fromList(<int>[...ascii.encode(tag), ...body]);
  return Uint8List.fromList(<int>[
    ..._be32(body.length),
    ...tagged,
    ..._be32(_crc32(tagged)),
  ]);
}

List<int> _be32(int value) => <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

int _crc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
