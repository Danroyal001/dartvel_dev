/// PWA icon generation, from one source image.
///
/// The manifest names four icons -- 192 and 512, plain and maskable -- and
/// Chrome refuses to install without the two sizes. Generating them needed a
/// PNG codec that was not a dependency, so the manifest pointed at files
/// nothing produced and every fresh project was uninstallable until someone
/// exported four PNGs by hand.
///
/// PNG is small enough to read and write here: a signature, IHDR, one zlib
/// stream of filtered scanlines, IEND. dart:io has the zlib. What has to be
/// right is the filtering on decode: a wrong Paeth predictor produces an
/// image that is plausibly coloured and subtly wrong, which is exactly the
/// kind of failure that ships.
library dartvel_cli.build.pwa_icons;

import 'dart:io';
import 'dart:typed_data';

/// Something that is not a PNG this code can read, or a file it cannot.
class DVPngError implements Exception {
  const DVPngError(this.message);
  final String message;
  @override
  String toString() => 'DVPngError: $message';
}

/// An 8-bit RGBA raster.
class DVRgbaImage {
  DVRgbaImage(this.width, this.height)
      : pixels = Uint8List(width * height * 4);

  final int width;
  final int height;

  /// Row-major RGBA.
  final Uint8List pixels;

  int _at(int x, int y) => (y * width + x) * 4;

  List<int> get(int x, int y) {
    final int i = _at(x, y);
    return <int>[pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
  }

  void set(int x, int y, {required int r, required int g, required int b, int a = 255}) {
    final int i = _at(x, y);
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = a;
  }
}

const List<int> _signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

// ---------------------------------------------------------------------------
// Encoding

/// Encodes [image] as a PNG.
///
/// [filter] is the per-scanline filter type, 0 to 4, applied to every row.
/// The default is the plain one; the others exist so the decoder's handling
/// of each can be tested against a real stream rather than a fixture. [alpha]
/// false writes RGB, which is what most source icons are.
Uint8List dvPngEncode(DVRgbaImage image, {int filter = 0, bool alpha = true}) {
  if (filter < 0 || filter > 4) {
    throw ArgumentError.value(filter, 'filter', 'must be 0..4');
  }
  final int bpp = alpha ? 4 : 3;
  final int stride = image.width * bpp;
  final Uint8List raw = Uint8List((stride + 1) * image.height);
  final Uint8List prior = Uint8List(stride);
  final Uint8List row = Uint8List(stride);

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final int src = (y * image.width + x) * 4;
      final int dst = x * bpp;
      row[dst] = image.pixels[src];
      row[dst + 1] = image.pixels[src + 1];
      row[dst + 2] = image.pixels[src + 2];
      if (alpha) row[dst + 3] = image.pixels[src + 3];
    }
    final int base = y * (stride + 1);
    raw[base] = filter;
    for (var i = 0; i < stride; i++) {
      final int a = i >= bpp ? row[i - bpp] : 0;
      final int b = prior[i];
      final int c = i >= bpp ? prior[i - bpp] : 0;
      raw[base + 1 + i] = (row[i] - _predict(filter, a, b, c)) & 0xFF;
    }
    prior.setAll(0, row);
  }

  final BytesBuilder out = BytesBuilder(copy: false)..add(_signature);
  _chunk(out, 'IHDR', _ihdr(image.width, image.height, alpha ? 6 : 2));
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibEncoder().convert(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

Uint8List _ihdr(int width, int height, int colourType) {
  final ByteData d = ByteData(13);
  d.setUint32(0, width);
  d.setUint32(4, height);
  d.setUint8(8, 8); // bit depth
  d.setUint8(9, colourType);
  d.setUint8(10, 0); // compression
  d.setUint8(11, 0); // filter method
  d.setUint8(12, 0); // no interlace
  return d.buffer.asUint8List();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final ByteData len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final Uint8List typed = Uint8List.fromList(type.codeUnits + data);
  out.add(typed);
  final ByteData crc = ByteData(4)..setUint32(0, _crc32(typed));
  out.add(crc.buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final Uint32List t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final int b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// Decoding

/// Decodes an 8-bit RGB, RGBA, grey, grey+alpha or palette PNG.
///
/// Refuses anything else with a reason, and refuses a truncated stream rather
/// than reading it as a smaller image.
DVRgbaImage dvPngDecode(Uint8List bytes) {
  if (bytes.length < 8 ||
      !const _ListEq().equals(bytes.sublist(0, 8), _signature)) {
    throw const DVPngError('Not a PNG: the file does not start with the PNG '
        'signature.');
  }

  int? width;
  int? height;
  var bitDepth = 0;
  var colourType = 0;
  var interlace = 0;
  final BytesBuilder idat = BytesBuilder(copy: false);
  Uint8List? palette;
  Uint8List? paletteAlpha;
  var sawEnd = false;

  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final ByteData d = ByteData.sublistView(bytes, offset, offset + 8);
    final int length = d.getUint32(0);
    final String type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final int dataStart = offset + 8;
    final int dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) {
      throw const DVPngError('Truncated PNG: a chunk runs past the end of '
          'the file.');
    }
    final Uint8List data = bytes.sublist(dataStart, dataEnd);
    switch (type) {
      case 'IHDR':
        final ByteData h = ByteData.sublistView(data);
        width = h.getUint32(0);
        height = h.getUint32(4);
        bitDepth = h.getUint8(8);
        colourType = h.getUint8(9);
        interlace = h.getUint8(12);
      case 'PLTE':
        palette = data;
      case 'tRNS':
        paletteAlpha = data;
      case 'IDAT':
        idat.add(data);
      case 'IEND':
        sawEnd = true;
    }
    offset = dataEnd + 4; // skip CRC
    if (sawEnd) break;
  }

  if (width == null || height == null) {
    throw const DVPngError('Not a PNG this reader understands: no IHDR.');
  }
  if (!sawEnd) {
    throw const DVPngError('Truncated PNG: no IEND chunk.');
  }
  if (bitDepth != 8) {
    throw DVPngError('Unsupported PNG: $bitDepth-bit samples (only 8).');
  }
  if (interlace != 0) {
    throw const DVPngError('Unsupported PNG: interlaced (Adam7).');
  }
  final int channels = switch (colourType) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => throw DVPngError('Unsupported PNG colour type $colourType.'),
  };
  if (colourType == 3 && palette == null) {
    throw const DVPngError('Unsupported PNG: palette image with no PLTE.');
  }

  final Uint8List raw;
  try {
    raw = Uint8List.fromList(ZLibDecoder().convert(idat.toBytes()));
  } on Object {
    throw const DVPngError('Truncated or corrupt PNG: the image data does '
        'not inflate.');
  }
  final int stride = width * channels;
  if (raw.length < (stride + 1) * height) {
    throw const DVPngError('Truncated PNG: fewer scanlines than the header '
        'declares.');
  }

  final DVRgbaImage image = DVRgbaImage(width, height);
  final Uint8List prior = Uint8List(stride);
  final Uint8List row = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    final int base = y * (stride + 1);
    final int filter = raw[base];
    if (filter > 4) throw DVPngError('Corrupt PNG: filter type $filter.');
    for (var i = 0; i < stride; i++) {
      final int a = i >= channels ? row[i - channels] : 0;
      final int b = prior[i];
      final int c = i >= channels ? prior[i - channels] : 0;
      row[i] = (raw[base + 1 + i] + _predict(filter, a, b, c)) & 0xFF;
    }
    for (var x = 0; x < width; x++) {
      final int i = x * channels;
      switch (colourType) {
        case 0:
          image.set(x, y, r: row[i], g: row[i], b: row[i]);
        case 2:
          image.set(x, y, r: row[i], g: row[i + 1], b: row[i + 2]);
        case 3:
          final int p = row[i] * 3;
          final int alpha = paletteAlpha != null && row[i] < paletteAlpha.length
              ? paletteAlpha[row[i]]
              : 255;
          image.set(x, y, r: palette![p], g: palette[p + 1], b: palette[p + 2], a: alpha);
        case 4:
          image.set(x, y, r: row[i], g: row[i], b: row[i], a: row[i + 1]);
        case 6:
          image.set(x, y, r: row[i], g: row[i + 1], b: row[i + 2], a: row[i + 3]);
      }
    }
    prior.setAll(0, row);
  }
  return image;
}

/// The PNG filter predictors, as the specification defines them.
///
/// Paeth is the one that goes wrong quietly: the tie-breaking order is
/// a, then b, then c, and a decoder that picks c before b produces an image
/// that is plausibly coloured and subtly wrong.
int _predict(int filter, int a, int b, int c) => switch (filter) {
      0 => 0,
      1 => a,
      2 => b,
      3 => (a + b) >> 1,
      _ => () {
          final int p = a + b - c;
          final int pa = (p - a).abs();
          final int pb = (p - b).abs();
          final int pc = (p - c).abs();
          if (pa <= pb && pa <= pc) return a;
          if (pb <= pc) return b;
          return c;
        }(),
    };

class _ListEq {
  const _ListEq();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Resizing

/// Resamples with a box filter: every destination pixel is the average of the
/// source area it covers.
///
/// Averaging rather than picking, because an icon is nearly always scaled
/// down and nearest-neighbour turns a checkerboard into one of its colours --
/// an off-by-one that happens to be wrong the same way every time.
DVRgbaImage dvResizeRgba(DVRgbaImage src, int width, int height) {
  final DVRgbaImage out = DVRgbaImage(width, height);
  final double sx = src.width / width;
  final double sy = src.height / height;
  for (var y = 0; y < height; y++) {
    final int y0 = (y * sy).floor();
    final int y1 = ((y + 1) * sy).ceil().clamp(y0 + 1, src.height);
    for (var x = 0; x < width; x++) {
      final int x0 = (x * sx).floor();
      final int x1 = ((x + 1) * sx).ceil().clamp(x0 + 1, src.width);
      var r = 0, g = 0, b = 0, a = 0, n = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          final int i = (yy * src.width + xx) * 4;
          r += src.pixels[i];
          g += src.pixels[i + 1];
          b += src.pixels[i + 2];
          a += src.pixels[i + 3];
          n++;
        }
      }
      out.set(x, y, r: (r / n).round(), g: (g / n).round(), b: (b / n).round(), a: (a / n).round());
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// The icon set

/// The four icons the manifest names, written under `into/icons/`.
///
/// Maskable icons are inset: launchers crop them to a circle inscribed in the
/// middle 80%, so artwork scaled to the edge loses its corners. The inset is
/// filled with [background], which is the manifest's background colour by
/// default. Returns the paths written, relative to [into].
List<String> dvGeneratePwaIcons({
  required File source,
  required Directory into,
  int background = 0xFFFFFFFF,
  List<int> sizes = const <int>[192, 512],
}) {
  if (!source.existsSync()) {
    throw DVPngError('Icon source ${source.path} does not exist.');
  }
  final DVRgbaImage art = dvPngDecode(source.readAsBytesSync());
  final Directory icons = Directory('${into.path}/icons')..createSync(recursive: true);
  final List<String> written = <String>[];

  for (final int size in sizes) {
    final DVRgbaImage plain = dvResizeRgba(art, size, size);
    File('${icons.path}/Icon-$size.png').writeAsBytesSync(dvPngEncode(plain));
    written.add('icons/Icon-$size.png');

    // Safe zone: the artwork occupies the central 80%, the rest is background.
    final int inner = (size * 0.8).round();
    final int offset = (size - inner) ~/ 2;
    final DVRgbaImage scaled = dvResizeRgba(art, inner, inner);
    final DVRgbaImage maskable = DVRgbaImage(size, size);
    final int br = (background >> 16) & 0xFF;
    final int bg = (background >> 8) & 0xFF;
    final int bb = background & 0xFF;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        maskable.set(x, y, r: br, g: bg, b: bb);
      }
    }
    for (var y = 0; y < inner; y++) {
      for (var x = 0; x < inner; x++) {
        final List<int> p = scaled.get(x, y);
        // Composited over the background, so a transparent source does not
        // punch a hole through the launcher tile.
        final double alpha = p[3] / 255;
        maskable.set(
          x + offset,
          y + offset,
          r: (p[0] * alpha + br * (1 - alpha)).round(),
          g: (p[1] * alpha + bg * (1 - alpha)).round(),
          b: (p[2] * alpha + bb * (1 - alpha)).round(),
        );
      }
    }
    File('${icons.path}/Icon-maskable-$size.png')
        .writeAsBytesSync(dvPngEncode(maskable));
    written.add('icons/Icon-maskable-$size.png');
  }
  return written;
}

// ---------------------------------------------------------------------------
// Finding the source, and the background colour

/// The PNG the icon set is generated from, or null when the project has none.
///
/// `dartvel.pwa.icon` wins; then `web/icon.png`, then `assets/icon.png`. A
/// configured path that does not exist is an error rather than a fallback,
/// because falling back would quietly ship a different image from the one the
/// project named. Nothing anywhere is null: a project with no icon gets no
/// icons and a plain message, not a build failure and not a placeholder that
/// ships to a store.
File? dvPwaIconSource(String root, Map<Object?, Object?> pwaSettings) {
  final Object? configured = pwaSettings['icon'];
  if (configured is String && configured.trim().isNotEmpty) {
    final File file = File('$root/${configured.trim()}');
    if (!file.existsSync()) {
      throw DVPngError('dartvel.pwa.icon names ${configured.trim()}, which '
          'does not exist.');
    }
    return file;
  }
  for (final String candidate in <String>['web/icon.png', 'assets/icon.png']) {
    final File file = File('$root/$candidate');
    if (file.existsSync()) return file;
  }
  return null;
}

/// `#RRGGBB` or `#RGB` as opaque ARGB. Anything else is white.
///
/// The manifest already tolerates a bad colour; the icon background should
/// not be the one place it becomes fatal.
int dvHexToArgb(String hex) {
  String h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) h = h.split('').map((String c) => '$c$c').join();
  if (h.length != 6) return 0xFFFFFFFF;
  final int? value = int.tryParse(h, radix: 16);
  return value == null ? 0xFFFFFFFF : 0xFF000000 | value;
}
