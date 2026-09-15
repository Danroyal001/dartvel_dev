/// QR codes, encoded in Dart, for showing an authenticator app the
/// `otpauth://` URI of a TOTP enrollment.
///
/// Encoded here rather than by a platform API or a web service because the
/// payload is the secret: it must not leave the device to be drawn, and a
/// native scanner library would be a platform channel this framework does not
/// use. What goes wrong in an encoder is silent -- a wrong block split or
/// format word still draws a plausible square -- so the tests read every
/// symbol back with a reader built from the standard's own tables.
///
/// Byte mode, error-correction level M, versions 1 to 40 (ISO/IEC 18004).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// A QR code symbol: a square of modules, true for dark.
class DVQrCode {
  DVQrCode._(this.version, this.mask, this.modules);

  /// Encodes [text] as UTF-8 at level M in the smallest version that holds
  /// it, with the mask that scores best. Throws [ArgumentError] when no
  /// version holds it, rather than drawing a code that says less.
  factory DVQrCode.encode(String text) {
    final List<int> bytes = utf8.encode(text);
    for (int version = 1; version <= 40; version++) {
      final int capacity = _dataCodewords(version) * 8;
      final int needed = 4 + (version < 10 ? 8 : 16) + bytes.length * 8;
      if (needed <= capacity) return _build(version, bytes);
    }
    throw ArgumentError.value(
      '${bytes.length} bytes',
      'text',
      'is longer than a QR code at error-correction level M holds',
    );
  }

  /// 1 to 40.
  final int version;

  /// The mask pattern applied, 0 to 7.
  final int mask;

  /// Rows of columns; `modules[y][x]` is true for a dark module.
  final List<List<bool>> modules;

  int get size => modules.length;

  // --- tables -----------------------------------------------------------------

  // Level M's error-correction codewords per block and number of blocks, per
  // version; index 0 is unused.
  static const List<int> _eccPerBlock = <int>[
    -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, //
    26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, //
    28, 28, 28, 28, 28,
  ];
  static const List<int> _blocks = <int>[
    -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, //
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, //
    47, 49,
  ];

  /// Level M's two format bits.
  static const int _levelBits = 0;

  static int _rawModules(int version) {
    int result = (16 * version + 128) * version + 64;
    if (version >= 2) {
      final int align = version ~/ 7 + 2;
      result -= (25 * align - 10) * align - 55;
      if (version >= 7) result -= 36;
    }
    return result;
  }

  static int _dataCodewords(int version) =>
      _rawModules(version) ~/ 8 - _eccPerBlock[version] * _blocks[version];

  static List<int> _alignmentPositions(int version) {
    if (version == 1) return const <int>[];
    final int count = version ~/ 7 + 2;
    final int step = version == 32
        ? 26
        : (version * 4 + count * 2 + 1) ~/ (count * 2 - 2) * 2;
    final List<int> result = List<int>.filled(count, 6);
    int position = version * 4 + 10;
    for (int i = count - 1; i >= 1; i--) {
      result[i] = position;
      position -= step;
    }
    return result;
  }

  // --- building ---------------------------------------------------------------

  static DVQrCode _build(int version, List<int> bytes) {
    final List<int> codewords = _withErrorCorrection(version, _data(version, bytes));
    final _Grid base = _Grid(version * 4 + 17);
    base.drawFunctionPatterns(version);
    base.drawCodewords(codewords);

    int bestMask = 0;
    int bestPenalty = -1;
    List<List<bool>>? best;
    for (int mask = 0; mask < 8; mask++) {
      final _Grid grid = base.copy()
        ..applyMask(mask)
        ..drawFormat(mask);
      final int penalty = grid.penalty();
      if (bestPenalty < 0 || penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
        best = grid.rows();
      }
    }
    return DVQrCode._(
      version,
      bestMask,
      List<List<bool>>.unmodifiable(
          best!.map((List<bool> row) => List<bool>.unmodifiable(row))),
    );
  }

  /// The data codewords: one byte-mode segment, the terminator and padding.
  static List<int> _data(int version, List<int> bytes) {
    final List<bool> bits = <bool>[];
    void append(int value, int length) {
      for (int i = length - 1; i >= 0; i--) {
        bits.add((value >> i) & 1 == 1);
      }
    }

    final int capacity = _dataCodewords(version) * 8;
    append(0x4, 4);
    append(bytes.length, version < 10 ? 8 : 16);
    for (final int byte in bytes) {
      append(byte, 8);
    }
    append(0, (capacity - bits.length).clamp(0, 4));
    append(0, (8 - bits.length % 8) % 8);
    for (int pad = 0xEC; bits.length < capacity; pad ^= 0xEC ^ 0x11) {
      append(pad, 8);
    }
    return <int>[
      for (int i = 0; i < bits.length; i += 8)
        <bool>[for (int j = 0; j < 8; j++) bits[i + j]]
            .fold(0, (int v, bool bit) => (v << 1) | (bit ? 1 : 0)),
    ];
  }

  /// Splits [data] into blocks, appends each block's Reed-Solomon codewords
  /// and interleaves them: data column by column, then error correction.
  static List<int> _withErrorCorrection(int version, List<int> data) {
    final int blockCount = _blocks[version];
    final int ecc = _eccPerBlock[version];
    final int raw = _rawModules(version) ~/ 8;
    final int shortBlocks = blockCount - raw % blockCount;
    final int shortData = raw ~/ blockCount - ecc;
    final Uint8List divisor = _rsDivisor(ecc);
    final List<List<int>> dataBlocks = <List<int>>[];
    final List<List<int>> eccBlocks = <List<int>>[];
    int offset = 0;
    for (int i = 0; i < blockCount; i++) {
      final int length = shortData + (i < shortBlocks ? 0 : 1);
      final List<int> block = data.sublist(offset, offset + length);
      offset += length;
      dataBlocks.add(block);
      eccBlocks.add(_rsRemainder(block, divisor));
    }
    return <int>[
      for (int i = 0; i <= shortData; i++)
        for (final List<int> block in dataBlocks)
          if (i < block.length) block[i],
      for (int i = 0; i < ecc; i++)
        for (final List<int> block in eccBlocks) block[i],
    ];
  }

  static int _gfMultiply(int x, int y) {
    int z = 0;
    for (int i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> i) & 1) * x;
    }
    return z & 0xFF;
  }

  static Uint8List _rsDivisor(int degree) {
    final Uint8List result = Uint8List(degree);
    result[degree - 1] = 1;
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

  static List<int> _rsRemainder(List<int> data, Uint8List divisor) {
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
}

class _Grid {
  _Grid(this.size)
      : _dark = List<List<bool>>.generate(size, (_) => List<bool>.filled(size, false)),
        _function =
            List<List<bool>>.generate(size, (_) => List<bool>.filled(size, false));

  _Grid._copy(this.size, this._dark, this._function);

  final int size;
  final List<List<bool>> _dark;
  final List<List<bool>> _function;

  _Grid copy() => _Grid._copy(
        size,
        <List<bool>>[for (final List<bool> row in _dark) List<bool>.of(row)],
        _function,
      );

  List<List<bool>> rows() =>
      <List<bool>>[for (final List<bool> row in _dark) List<bool>.of(row)];

  void _set(int x, int y, bool dark) {
    _dark[y][x] = dark;
    _function[y][x] = true;
  }

  void drawFunctionPatterns(int version) {
    for (int i = 0; i < size; i++) {
      _set(6, i, i.isEven);
      _set(i, 6, i.isEven);
    }
    _finder(3, 3);
    _finder(size - 4, 3);
    _finder(3, size - 4);
    final List<int> positions = DVQrCode._alignmentPositions(version);
    final int last = positions.length - 1;
    for (int i = 0; i < positions.length; i++) {
      for (int j = 0; j < positions.length; j++) {
        if ((i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)) {
          continue;
        }
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            _set(positions[i] + dx, positions[j] + dy,
                _chebyshev(dx, dy) != 1);
          }
        }
      }
    }
    // Reserved now so data is not placed there; drawn per mask.
    drawFormat(0);
    if (version >= 7) {
      int remainder = version;
      for (int i = 0; i < 12; i++) {
        remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25);
      }
      final int bits = version << 12 | remainder;
      for (int i = 0; i < 18; i++) {
        final bool bit = (bits >> i) & 1 == 1;
        final int a = size - 11 + i % 3;
        final int b = i ~/ 3;
        _set(a, b, bit);
        _set(b, a, bit);
      }
    }
  }

  static int _chebyshev(int dx, int dy) =>
      dx.abs() > dy.abs() ? dx.abs() : dy.abs();

  void _finder(int x, int y) {
    for (int dy = -4; dy <= 4; dy++) {
      for (int dx = -4; dx <= 4; dx++) {
        final int xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= size || yy >= size) continue;
        final int d = _chebyshev(dx, dy);
        _set(xx, yy, d != 2 && d != 4);
      }
    }
  }

  void drawFormat(int mask) {
    final int data = DVQrCode._levelBits << 3 | mask;
    int remainder = data;
    for (int i = 0; i < 10; i++) {
      remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537);
    }
    final int bits = (data << 10 | remainder) ^ 0x5412;
    bool bit(int i) => (bits >> i) & 1 == 1;
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

  void drawCodewords(List<int> codewords) {
    int index = 0;
    final int total = codewords.length * 8;
    for (int right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (int vertical = 0; vertical < size; vertical++) {
        for (int j = 0; j < 2; j++) {
          final int x = right - j;
          final bool upward = (right + 1) & 2 == 0;
          final int y = upward ? size - 1 - vertical : vertical;
          if (!_function[y][x] && index < total) {
            _dark[y][x] = (codewords[index >> 3] >> (7 - (index & 7))) & 1 == 1;
            index++;
          }
        }
      }
    }
  }

  void applyMask(int mask) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (_function[y][x]) continue;
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
        if (invert) _dark[y][x] = !_dark[y][x];
      }
    }
  }

  /// The standard's four penalty rules: long runs, 2x2 blocks, finder-like
  /// patterns and imbalance between dark and light.
  int penalty() {
    int result = 0;
    List<bool> line(int i, bool row) =>
        <bool>[for (int j = 0; j < size; j++) row ? _dark[i][j] : _dark[j][i]];
    for (int i = 0; i < size; i++) {
      for (final bool row in <bool>[true, false]) {
        final List<bool> cells = line(i, row);
        int run = 1;
        for (int j = 1; j <= size; j++) {
          if (j < size && cells[j] == cells[j - 1]) {
            run++;
          } else {
            if (run >= 5) result += 3 + (run - 5);
            run = 1;
          }
        }
        for (int j = 0; j + 7 <= size; j++) {
          final bool core = cells[j] &&
              !cells[j + 1] &&
              cells[j + 2] &&
              cells[j + 3] &&
              cells[j + 4] &&
              !cells[j + 5] &&
              cells[j + 6];
          if (!core) continue;
          bool lightRun(int from, int to) {
            for (int k = from; k < to; k++) {
              if (k >= 0 && k < size && cells[k]) return false;
            }
            return true;
          }

          if (lightRun(j - 4, j) || lightRun(j + 7, j + 11)) result += 40;
        }
      }
    }
    int dark = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (_dark[y][x]) dark++;
        if (x + 1 < size &&
            y + 1 < size &&
            _dark[y][x] == _dark[y][x + 1] &&
            _dark[y][x] == _dark[y + 1][x] &&
            _dark[y][x] == _dark[y + 1][x + 1]) {
          result += 3;
        }
      }
    }
    final int total = size * size;
    final int k = ((dark * 20 - total * 10).abs() + total - 1) ~/ total - 1;
    result += (k < 0 ? 0 : k) * 10;
    return result;
  }
}

/// A QR code drawn with a four-module quiet zone, dark on white whatever the
/// theme: a scanner needs contrast, and a light-on-dark code is one many
/// cameras will not read.
class DVQrImage extends StatelessWidget {
  DVQrImage({super.key, required this.data, this.size = 200})
      : code = DVQrCode.encode(data);

  /// What the code says.
  final String data;

  /// The width and height, quiet zone included.
  final double size;

  /// The symbol drawn.
  final DVQrCode code;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'QR code',
        image: true,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _DVQrPainter(code)),
        ),
      );
}

class _DVQrPainter extends CustomPainter {
  _DVQrPainter(this.code);

  final DVQrCode code;

  @override
  void paint(Canvas canvas, Size size) {
    const int quiet = 4;
    final double module = size.shortestSide / (code.size + quiet * 2);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final Paint dark = Paint()..color = const Color(0xFF000000);
    for (int y = 0; y < code.size; y++) {
      for (int x = 0; x < code.size; x++) {
        if (!code.modules[y][x]) continue;
        canvas.drawRect(
          Rect.fromLTWH((x + quiet) * module, (y + quiet) * module,
              module + 0.01, module + 0.01),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DVQrPainter oldDelegate) => oldDelegate.code != code;
}
