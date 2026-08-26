/// Deciding whether a screenshot shows a running application.
///
/// The runtime-verification jobs each ended with `test -s capture.png`, which
/// asserts a file is non-empty and nothing else. Every capture tool in those
/// jobs produces a full-size image whether or not the application drew: `import
/// -window root` photographs the Xvfb root window, `adb exec-out screencap`
/// photographs the launcher, `screencapture` photographs the desktop. A crash
/// before the first frame yields a full-size PNG of one colour, a few kilobytes
/// on disk, and a green job.
///
/// So the check has to look at pixels. Two properties separate a rendered
/// application from an empty screen without knowing what the application looks
/// like: it uses more than one colour, and no single colour covers essentially
/// all of it. A caller that does know can add [verifyCapture]'s `expectColour`.
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// What a capture turned out to be.
class CaptureVerdict {
  const CaptureVerdict({
    required this.ok,
    required this.reasons,
    required this.width,
    required this.height,
    required this.distinctColours,
    required this.dominantFraction,
  });

  /// Whether this capture shows an application.
  final bool ok;

  /// Why not, in the order the checks ran. Empty when [ok].
  final List<String> reasons;

  final int width;
  final int height;

  /// How many distinct RGB values appear. One means a blank screen.
  final int distinctColours;

  /// The share of pixels held by the most common colour. A window that opened
  /// and painted nothing but its background sits very close to 1.
  final double dominantFraction;
}

CaptureVerdict _rejected(String reason) => CaptureVerdict(
      ok: false,
      reasons: <String>[reason],
      width: 0,
      height: 0,
      distinctColours: 0,
      dominantFraction: 1,
    );

/// Whether [bytes] is a PNG showing a rendered application.
///
/// [minWidth] and [minHeight] reject a capture too small to be a screen — a
/// tool that failed and wrote a placeholder, or a window that never sized.
/// [maxDominantFraction] is the share of one colour above which the image is
/// called blank; 0.99 leaves room for a UI that is mostly background while
/// still rejecting a screen with a few stray pixels on it.
CaptureVerdict verifyCapture(
  List<int> bytes, {
  int minWidth = 1,
  int minHeight = 1,
  double maxDominantFraction = 0.99,
  List<int>? expectColour,
}) {
  final image = _decodePng(bytes);
  if (image == null) {
    return _rejected(
        'Not a PNG this can read: expected an 8-bit greyscale, truecolour, '
        'palette or truecolour-alpha image.');
  }

  final counts = <int, int>{};
  for (final colour in image.pixels) {
    counts[colour] = (counts[colour] ?? 0) + 1;
  }
  var dominant = 0;
  for (final count in counts.values) {
    if (count > dominant) dominant = count;
  }
  final fraction = image.pixels.isEmpty ? 1.0 : dominant / image.pixels.length;

  final reasons = <String>[];
  if (image.width < minWidth || image.height < minHeight) {
    reasons.add('The capture is ${image.width}x${image.height}, smaller than '
        'the ${minWidth}x$minHeight a rendered window would be.');
  }
  if (counts.length <= 1) {
    reasons.add('The capture is one colour. Nothing was drawn — this is what '
        'a crash before the first frame looks like.');
  } else if (fraction > maxDominantFraction) {
    reasons.add('One background colour covers '
        '${(fraction * 100).toStringAsFixed(2)}% of the capture. The window '
        'opened but painted nothing.');
  }
  if (expectColour != null) {
    final wanted = _packed(expectColour[0], expectColour[1], expectColour[2]);
    if (!counts.containsKey(wanted)) {
      reasons.add('The expected colour rgb(${expectColour.join(',')}) is not '
          'in the capture.');
    }
  }

  return CaptureVerdict(
    ok: reasons.isEmpty,
    reasons: reasons,
    width: image.width,
    height: image.height,
    distinctColours: counts.length,
    dominantFraction: fraction,
  );
}

int _packed(int r, int g, int b) => (r << 16) | (g << 8) | b;

class _Image {
  const _Image(this.width, this.height, this.pixels);
  final int width;
  final int height;

  /// Packed 24-bit RGB, alpha discarded: a transparent black screen and an
  /// opaque one are equally blank.
  final List<int> pixels;
}

/// Decode the PNG colour types a screenshot tool actually emits, at 8 bits per
/// channel. Anything else returns null rather than a guess — a wrong guess here
/// would report a blank screen as rendered, which is the failure this exists to
/// prevent.
_Image? _decodePng(List<int> bytes) {
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 8 + 25) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != signature[i]) return null;
  }

  final data = Uint8List.fromList(bytes);
  final view = ByteData.view(data.buffer, data.offsetInBytes, data.length);

  int? width;
  int? height;
  int? bitDepth;
  int? colourType;
  final idat = BytesBuilder();
  List<int>? palette;

  var offset = 8;
  while (offset + 8 <= data.length) {
    final length = view.getUint32(offset);
    if (offset + 12 + length > data.length) return null;
    final type = ascii.decode(data.sublist(offset + 4, offset + 8));
    final body = data.sublist(offset + 8, offset + 8 + length);
    switch (type) {
      case 'IHDR':
        if (length < 13) return null;
        width = ByteData.view(body.buffer, body.offsetInBytes).getUint32(0);
        height = ByteData.view(body.buffer, body.offsetInBytes).getUint32(4);
        bitDepth = body[8];
        colourType = body[9];
        // Interlaced images would need a different reassembly; no screenshot
        // tool writes one, and reading it as non-interlaced would produce
        // plausible garbage rather than an error.
        if (body[12] != 0) return null;
      case 'PLTE':
        palette = body;
      case 'IDAT':
        idat.add(body);
      case 'IEND':
        offset = data.length;
        continue;
    }
    offset += 12 + length;
  }

  if (width == null || height == null || bitDepth != 8 || colourType == null) {
    return null;
  }

  final channels = switch (colourType) {
    0 => 1, // greyscale
    2 => 3, // truecolour
    3 => 1, // palette index
    4 => 2, // greyscale + alpha
    6 => 4, // truecolour + alpha
    _ => 0,
  };
  if (channels == 0) return null;
  if (colourType == 3 && palette == null) return null;

  final Uint8List inflated;
  try {
    inflated = Uint8List.fromList(ZLibDecoder().convert(idat.toBytes()));
  } catch (_) {
    return null;
  }

  final stride = width * channels;
  if (inflated.length < (stride + 1) * height) return null;

  final raw = Uint8List(stride * height);
  var source = 0;
  for (var y = 0; y < height; y++) {
    final filter = inflated[source++];
    final rowStart = y * stride;
    for (var x = 0; x < stride; x++) {
      final value = inflated[source + x];
      final left = x >= channels ? raw[rowStart + x - channels] : 0;
      final up = y > 0 ? raw[rowStart - stride + x] : 0;
      final upLeft =
          (y > 0 && x >= channels) ? raw[rowStart - stride + x - channels] : 0;
      raw[rowStart + x] = switch (filter) {
        0 => value,
        1 => value + left,
        2 => value + up,
        3 => value + ((left + up) >> 1),
        4 => value + _paeth(left, up, upLeft),
        _ => value,
      };
    }
    source += stride;
  }

  final pixels = List<int>.filled(width * height, 0);
  for (var i = 0; i < width * height; i++) {
    final base = i * channels;
    pixels[i] = switch (colourType) {
      0 || 4 => _packed(raw[base], raw[base], raw[base]),
      2 || 6 => _packed(raw[base], raw[base + 1], raw[base + 2]),
      3 => () {
          final index = raw[base] * 3;
          if (index + 2 >= palette!.length) return 0;
          return _packed(palette[index], palette[index + 1], palette[index + 2]);
        }(),
      _ => 0,
    };
  }

  return _Image(width, height, pixels);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
