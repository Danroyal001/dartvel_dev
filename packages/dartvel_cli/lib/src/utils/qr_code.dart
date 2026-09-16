/// A QR code encoder, for printing a link a phone can scan.
///
/// Byte mode only, every version from 1 to 40, all four error correction
/// levels, and the mask chosen by the penalty rules of ISO/IEC 18004 unless one
/// is asked for. That is everything `dartvel dev` needs to put a pairing link
/// or a LAN address on screen, and nothing a terminal cannot show.
///
/// Written here rather than taken from pub because the CLI had no QR
/// dependency and this is small. It is checked module for module against an
/// independent encoder's output, decoded back to text, in
/// test/qr_code_test.dart.
library dartvel_cli.utils.qr_code;

import 'dart:convert';

enum DVQrErrorCorrection {
  /// About 7% of codewords recoverable.
  low(1),

  /// About 15%. The default: a code shown on a screen that somebody's phone
  /// may catch at an angle, and still small enough for a terminal.
  medium(0),

  /// About 25%.
  quartile(3),

  /// About 30%.
  high(2);

  const DVQrErrorCorrection(this.formatBits);

  /// The two bits the format information records for this level.
  final int formatBits;
}

class DVQrCode {
  DVQrCode._(this.version, this.errorCorrection, this.mask, this._modules)
    : size = version * 4 + 17;

  /// 1 to 40.
  final int version;

  /// Modules along each side, without the quiet zone.
  final int size;

  final DVQrErrorCorrection errorCorrection;

  /// 0 to 7.
  final int mask;

  final List<List<bool>> _modules;

  /// Whether the module in column [x], row [y] is dark.
  bool isDark(int x, int y) => _modules[y][x];

  /// The penalty score of this code as masked, by the standard's four rules.
  ///
  /// Lower reads more reliably; it is what an unforced mask is chosen by.
  int get penalty => _penalty(_modules);

  /// [text] as UTF-8 bytes.
  static DVQrCode encodeText(
    String text, {
    DVQrErrorCorrection errorCorrection = DVQrErrorCorrection.medium,
    int? mask,
  }) => encodeBytes(
    utf8.encode(text),
    errorCorrection: errorCorrection,
    mask: mask,
  );

  /// [data] in byte mode, in the smallest version that holds it.
  ///
  /// Throws [ArgumentError] when even version 40 cannot: a truncated link
  /// scans perfectly and points somewhere else.
  static DVQrCode encodeBytes(
    List<int> data, {
    DVQrErrorCorrection errorCorrection = DVQrErrorCorrection.medium,
    int? mask,
  }) {
    if (mask != null && (mask < 0 || mask > 7)) {
      throw ArgumentError.value(mask, 'mask', 'must be 0 to 7');
    }
    int? version;
    for (int v = 1; v <= 40; v++) {
      final int bits = 4 + (v <= 9 ? 8 : 16) + data.length * 8;
      if (bits <= _dataCodewords(v, errorCorrection) * 8) {
        version = v;
        break;
      }
    }
    if (version == null) {
      throw ArgumentError(
        '${data.length} bytes do not fit in a QR code at level '
        '${errorCorrection.name}.',
      );
    }

    // Mode, length, data, terminator, then pad to the capacity.
    final _Bits bits = _Bits()
      ..append(0x4, 4)
      ..append(data.length, version <= 9 ? 8 : 16);
    for (final int byte in data) {
      bits.append(byte & 0xff, 8);
    }
    final int capacity = _dataCodewords(version, errorCorrection) * 8;
    final int terminator = capacity - bits.length < 4
        ? capacity - bits.length
        : 4;
    bits.append(0, terminator);
    bits.append(0, (8 - bits.length % 8) % 8);
    for (int pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) {
      bits.append(pad, 8);
    }
    final List<int> codewords = List<int>.filled(bits.length ~/ 8, 0);
    for (int i = 0; i < bits.length; i++) {
      codewords[i >> 3] |= bits[i] << (7 - (i & 7));
    }

    final _Grid grid = _Grid(version);
    grid.drawFunctionPatterns();
    grid.drawCodewords(_interleave(codewords, version, errorCorrection));

    int chosen = mask ?? 0;
    if (mask == null) {
      int best = -1;
      for (int m = 0; m < 8; m++) {
        grid.applyMask(m);
        grid.drawFormatBits(errorCorrection, m);
        final int score = _penalty(grid.modules);
        if (best < 0 || score < best) {
          best = score;
          chosen = m;
        }
        grid.applyMask(m); // XOR undoes it.
      }
    }
    grid.applyMask(chosen);
    grid.drawFormatBits(errorCorrection, chosen);
    return DVQrCode._(version, errorCorrection, chosen, grid.modules);
  }
}

/// [code] as text lines for a terminal, two module rows to a line.
///
/// With [ansi], black on white is painted explicitly, so the code reads the
/// same on a light or dark theme. Without it, the terminal's own colours are
/// assumed to be light glyphs on a dark background: a light module is a drawn
/// block and a dark module is left blank, which is the way round a camera
/// needs.
List<String> dvQrTerminalLines(
  DVQrCode code, {
  required bool ansi,
  int quietZone = 4,
}) {
  final int span = code.size + quietZone * 2;
  bool dark(int x, int y) {
    final int cx = x - quietZone;
    final int cy = y - quietZone;
    if (cx < 0 || cy < 0 || cx >= code.size || cy >= code.size) return false;
    return code.isDark(cx, cy);
  }

  final List<String> lines = <String>[];
  for (int y = 0; y < span; y += 2) {
    final StringBuffer line = StringBuffer();
    if (ansi) line.write('\x1b[30;47m');
    for (int x = 0; x < span; x++) {
      final bool top = dark(x, y);
      final bool bottom = y + 1 < span ? dark(x, y + 1) : false;
      if (ansi) {
        // Foreground black is dark: the glyph marks the dark halves.
        line.write(switch ((top, bottom)) {
          (true, true) => '█',
          (true, false) => '▀',
          (false, true) => '▄',
          (false, false) => ' ',
        });
      } else {
        // The glyph marks the light halves.
        line.write(switch ((top, bottom)) {
          (false, false) => '█',
          (false, true) => '▀',
          (true, false) => '▄',
          (true, true) => ' ',
        });
      }
    }
    if (ansi) line.write('\x1b[0m');
    lines.add(line.toString());
  }
  return lines;
}

// Codewords of error correction per block, by level and version (index 0 is
// unused), from the standard's table 9.
const Map<DVQrErrorCorrection, List<int>> _eccPerBlock =
    <DVQrErrorCorrection, List<int>>{
      DVQrErrorCorrection.low: <int>[
        -1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, //
        30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30,
        30, 30, 30, 30, 30,
      ],
      DVQrErrorCorrection.medium: <int>[
        -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, //
        26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        28, 28, 28, 28, 28,
      ],
      DVQrErrorCorrection.quartile: <int>[
        -1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, //
        28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30,
        30, 30, 30, 30, 30,
      ],
      DVQrErrorCorrection.high: <int>[
        -1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, //
        28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
        30, 30, 30, 30, 30,
      ],
    };

// Error correction blocks, by level and version.
const Map<DVQrErrorCorrection, List<int>> _blocks =
    <DVQrErrorCorrection, List<int>>{
      DVQrErrorCorrection.low: <int>[
        -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, //
        9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25,
      ],
      DVQrErrorCorrection.medium: <int>[
        -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, //
        17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45,
        47, 49,
      ],
      DVQrErrorCorrection.quartile: <int>[
        -1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, //
        20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59,
        62, 65, 68,
      ],
      DVQrErrorCorrection.high: <int>[
        -1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, //
        25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70,
        74, 77, 81,
      ],
    };

/// Modules available for data and error correction in [version].
int _rawDataModules(int version) {
  int result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    final int align = version ~/ 7 + 2;
    result -= (25 * align - 10) * align - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

int _dataCodewords(int version, DVQrErrorCorrection level) =>
    _rawDataModules(version) ~/ 8 -
    _eccPerBlock[level]![version] * _blocks[level]![version];

List<int> _interleave(
  List<int> data,
  int version,
  DVQrErrorCorrection level,
) {
  final int blockCount = _blocks[level]![version];
  final int eccLength = _eccPerBlock[level]![version];
  final int raw = _rawDataModules(version) ~/ 8;
  final int shortBlocks = blockCount - raw % blockCount;
  final int shortLength = raw ~/ blockCount;
  final List<int> divisor = _reedSolomonDivisor(eccLength);

  final List<List<int>> blocks = <List<int>>[];
  int offset = 0;
  for (int i = 0; i < blockCount; i++) {
    final int length = shortLength - eccLength + (i < shortBlocks ? 0 : 1);
    final List<int> block = data.sublist(offset, offset + length);
    offset += length;
    final List<int> ecc = _reedSolomonRemainder(block, divisor);
    blocks.add(<int>[...block, if (i < shortBlocks) 0, ...ecc]);
  }

  final List<int> out = <int>[];
  for (int i = 0; i < blocks.first.length; i++) {
    for (int j = 0; j < blocks.length; j++) {
      // The padding a short block was given to line the columns up.
      if (i == shortLength - eccLength && j < shortBlocks) continue;
      out.add(blocks[j][i]);
    }
  }
  return out;
}

int _gfMultiply(int x, int y) {
  int z = 0;
  for (int i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >> 7) * 0x11d);
    z ^= ((y >> i) & 1) * x;
  }
  return z & 0xff;
}

List<int> _reedSolomonDivisor(int degree) {
  final List<int> result = List<int>.filled(degree, 0)..[degree - 1] = 1;
  int root = 1;
  for (int i = 0; i < degree; i++) {
    for (int j = 0; j < degree; j++) {
      result[j] = _gfMultiply(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = _gfMultiply(root, 0x02);
  }
  return result;
}

List<int> _reedSolomonRemainder(List<int> data, List<int> divisor) {
  final List<int> result = List<int>.filled(divisor.length, 0, growable: true);
  for (final int byte in data) {
    final int factor = byte ^ result.removeAt(0);
    result.add(0);
    for (int i = 0; i < result.length; i++) {
      result[i] ^= _gfMultiply(divisor[i], factor);
    }
  }
  return result;
}

class _Bits {
  final List<int> _bits = <int>[];
  int get length => _bits.length;
  int operator [](int i) => _bits[i];
  void append(int value, int count) {
    for (int i = count - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1);
    }
  }
}

class _Grid {
  _Grid(this.version)
    : size = version * 4 + 17,
      modules = List<List<bool>>.generate(
        version * 4 + 17,
        (_) => List<bool>.filled(version * 4 + 17, false),
      ),
      isFunction = List<List<bool>>.generate(
        version * 4 + 17,
        (_) => List<bool>.filled(version * 4 + 17, false),
      );

  final int version;
  final int size;
  final List<List<bool>> modules;
  final List<List<bool>> isFunction;

  void _set(int x, int y, bool dark) {
    modules[y][x] = dark;
    isFunction[y][x] = true;
  }

  void drawFunctionPatterns() {
    for (int i = 0; i < size; i++) {
      _set(6, i, i.isEven);
      _set(i, 6, i.isEven);
    }
    _finder(3, 3);
    _finder(size - 4, 3);
    _finder(3, size - 4);

    final List<int> positions = _alignmentPositions();
    final int last = positions.length - 1;
    for (int i = 0; i <= last; i++) {
      for (int j = 0; j <= last; j++) {
        final bool corner =
            (i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0);
        if (!corner) _alignment(positions[i], positions[j]);
      }
    }

    // Reserved now so data is not drawn over them; written once the mask is
    // known.
    drawFormatBits(DVQrErrorCorrection.medium, 0);
    _drawVersion();
  }

  List<int> _alignmentPositions() {
    if (version == 1) return const <int>[];
    final int count = version ~/ 7 + 2;
    final int step = (version * 8 + count * 3 + 5) ~/ (count * 4 - 4) * 2;
    final List<int> result = <int>[6];
    for (int pos = size - 7; result.length < count; pos -= step) {
      result.insert(1, pos);
    }
    return result;
  }

  void _finder(int x, int y) {
    for (int dy = -4; dy <= 4; dy++) {
      for (int dx = -4; dx <= 4; dx++) {
        final int distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        final int xx = x + dx;
        final int yy = y + dy;
        if (xx >= 0 && xx < size && yy >= 0 && yy < size) {
          _set(xx, yy, distance != 2 && distance != 4);
        }
      }
    }
  }

  void _alignment(int x, int y) {
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        _set(x + dx, y + dy, (dx.abs() > dy.abs() ? dx.abs() : dy.abs()) != 1);
      }
    }
  }

  void drawFormatBits(DVQrErrorCorrection level, int mask) {
    final int data = level.formatBits << 3 | mask;
    int remainder = data;
    for (int i = 0; i < 10; i++) {
      remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537);
    }
    final int bits = (data << 10 | remainder) ^ 0x5412;
    bool bit(int i) => (bits >> i) & 1 != 0;

    for (int i = 0; i <= 5; i++) {
      _set(8, i, bit(i));
    }
    _set(8, 7, bit(6));
    _set(8, 8, bit(7));
    _set(7, 8, bit(8));
    for (int i = 9; i < 15; i++) {
      _set(14 - i, 8, bit(i));
    }
    for (int i = 0; i < 8; i++) {
      _set(size - 1 - i, 8, bit(i));
    }
    for (int i = 8; i < 15; i++) {
      _set(8, size - 15 + i, bit(i));
    }
    _set(8, size - 8, true);
  }

  void _drawVersion() {
    if (version < 7) return;
    int remainder = version;
    for (int i = 0; i < 12; i++) {
      remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1f25);
    }
    final int bits = version << 12 | remainder;
    for (int i = 0; i < 18; i++) {
      final bool dark = (bits >> i) & 1 != 0;
      final int a = size - 11 + i % 3;
      final int b = i ~/ 3;
      _set(a, b, dark);
      _set(b, a, dark);
    }
  }

  void drawCodewords(List<int> data) {
    int i = 0;
    for (int right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (int vertical = 0; vertical < size; vertical++) {
        for (int j = 0; j < 2; j++) {
          final int x = right - j;
          final bool upward = ((right + 1) & 2) == 0;
          final int y = upward ? size - 1 - vertical : vertical;
          if (!isFunction[y][x] && i < data.length * 8) {
            modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1 != 0;
            i++;
          }
        }
      }
    }
  }

  void applyMask(int mask) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (isFunction[y][x]) continue;
        final bool invert = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => x * y % 2 + x * y % 3 == 0,
          6 => (x * y % 2 + x * y % 3) % 2 == 0,
          _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
        };
        if (invert) modules[y][x] = !modules[y][x];
      }
    }
  }
}

int _penalty(List<List<bool>> modules) {
  const int n1 = 3, n2 = 3, n3 = 40, n4 = 10;
  final int size = modules.length;
  int result = 0;

  void addHistory(int run, List<int> history) {
    if (history[0] == 0) run += size; // The light border before the edge.
    for (int i = history.length - 1; i > 0; i--) {
      history[i] = history[i - 1];
    }
    history[0] = run;
  }

  int countPatterns(List<int> h) {
    final int n = h[1];
    final bool core =
        n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n;
    return (core && h[0] >= n * 4 && h[6] >= n ? 1 : 0) +
        (core && h[6] >= n * 4 && h[0] >= n ? 1 : 0);
  }

  int terminate(bool color, int run, List<int> history) {
    if (color) {
      addHistory(run, history);
      run = 0;
    }
    run += size;
    addHistory(run, history);
    return countPatterns(history);
  }

  // Rows, then columns: runs of one colour and finder-like patterns.
  for (int pass = 0; pass < 2; pass++) {
    for (int a = 0; a < size; a++) {
      bool color = false;
      int run = 0;
      final List<int> history = List<int>.filled(7, 0);
      for (int b = 0; b < size; b++) {
        final bool module = pass == 0 ? modules[a][b] : modules[b][a];
        if (module == color) {
          run++;
          if (run == 5) {
            result += n1;
          } else if (run > 5) {
            result++;
          }
        } else {
          addHistory(run, history);
          if (!color) result += countPatterns(history) * n3;
          color = module;
          run = 1;
        }
      }
      result += terminate(color, run, history) * n3;
    }
  }

  // Two-by-two blocks of one colour.
  for (int y = 0; y < size - 1; y++) {
    for (int x = 0; x < size - 1; x++) {
      final bool c = modules[y][x];
      if (c == modules[y][x + 1] &&
          c == modules[y + 1][x] &&
          c == modules[y + 1][x + 1]) {
        result += n2;
      }
    }
  }

  // Balance of dark and light.
  int dark = 0;
  for (final List<bool> row in modules) {
    for (final bool m in row) {
      if (m) dark++;
    }
  }
  final int total = size * size;
  final int k = ((dark * 20 - total * 10).abs() + total - 1) ~/ total - 1;
  result += k * n4;
  return result;
}
