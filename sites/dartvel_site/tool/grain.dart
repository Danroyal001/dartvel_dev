// Writes the film-grain tile the page bands are textured with.
//
// A flat page needs depth and the usual answer is a gradient, which is the
// most recognisable mark of an interface nobody art-directed. Grain does the
// same job without saying so: a small tile of monochrome noise, repeated,
// at an opacity low enough that you see it only when it is taken away.
//
// Generated rather than committed as somebody's stock texture, and
// generated deterministically: the same seed writes the same bytes, so the
// file in the repository can be reproduced and a diff means somebody changed
// the recipe.
//
// Run: dart run tool/grain.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// The tile is square and a power of two, so it repeats without a seam at
/// any device pixel ratio.
const int kSize = 96;

/// The strongest a single grain pixel gets, out of 255. The tile is drawn
/// black and its alpha is what varies, so this is the whole dynamic range.
const int kMaxAlpha = 46;

void main() {
  final Random random = Random(20260924);
  // RGBA, black with varying alpha. Black rather than white so one tile
  // works over a light ground and, with a blend mode, over a dark one.
  final Uint8List pixels = Uint8List(kSize * kSize * 4);
  for (int i = 0; i < kSize * kSize; i++) {
    // Two draws averaged: one uniform draw gives an even fizz, and grain is
    // mostly quiet with occasional specks.
    final int a = (random.nextInt(kMaxAlpha) + random.nextInt(kMaxAlpha)) ~/ 2;
    pixels[i * 4 + 3] = a;
  }

  final File out = File('assets/texture/grain.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(_png(pixels, kSize, kSize));
  stdout.writeln('wrote ${out.path} (${out.lengthSync()} bytes)');
}

/// [pixels] as a PNG. RGBA, 8 bits a channel, one IDAT.
Uint8List _png(Uint8List pixels, int width, int height) {
  // Each row is preceded by its filter byte. Filter 0 is none, which is what
  // noise wants: every other filter predicts from a neighbour, and noise has
  // no neighbours worth predicting from.
  final BytesBuilder raw = BytesBuilder();
  for (int y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(pixels.sublist(y * width * 4, (y + 1) * width * 4));
  }

  final BytesBuilder png = BytesBuilder()
    ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ByteData header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type: RGBA
    ..setUint8(10, 0) // deflate
    ..setUint8(11, 0) // adaptive filtering
    ..setUint8(12, 0); // no interlace
  png.add(_chunk('IHDR', header.buffer.asUint8List()));
  png.add(_chunk(
    'IDAT',
    Uint8List.fromList(ZLibEncoder(level: 9).convert(raw.takeBytes())),
  ));
  png.add(_chunk('IEND', Uint8List(0)));
  return png.takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final Uint8List name = Uint8List.fromList(ascii.encode(type));
  final BytesBuilder out = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(name)
    ..add(data);
  final Uint8List body = Uint8List.fromList(<int>[...name, ...data]);
  out.add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  return out.takeBytes();
}

/// PNG's CRC-32, built once.
final List<int> _crcTable = List<int>.generate(256, (int n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) {
  int c = 0xFFFFFFFF;
  for (final int byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
