// A QR code reader for tests, written from the standard's tables rather than
// from the encoder under test.
//
// It shares no code with lib/src/auth/qr_code.dart: the format and version
// words, block structures and alignment positions are the published
// constants, so an encoder that computed any of them wrong produces a symbol
// this refuses. It reads byte-mode symbols of versions 1 to 10, which covers
// every otpauth:// URI an authenticator enrollment produces.
library;

/// Format information for each (level, mask), as ISO/IEC 18004 table C.1
/// lists it after masking.
const Map<String, List<int>> _formatWords = <String, List<int>>{
  'L': <int>[0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976],
  'M': <int>[0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0],
  'Q': <int>[0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED],
  'H': <int>[0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B],
};

/// Version information words, table D.1.
const Map<int, int> _versionWords = <int, int>{
  7: 0x07C94,
  8: 0x085BC,
  9: 0x09A99,
  10: 0x0A4D3,
};

/// Alignment pattern centre coordinates, table E.1.
const Map<int, List<int>> _alignment = <int, List<int>>{
  1: <int>[],
  2: <int>[6, 18],
  3: <int>[6, 22],
  4: <int>[6, 26],
  5: <int>[6, 30],
  6: <int>[6, 34],
  7: <int>[6, 22, 38],
  8: <int>[6, 24, 42],
  9: <int>[6, 26, 46],
  10: <int>[6, 28, 50],
};

/// Error-correction blocks per version and level, table 9: a list of
/// (count, data codewords per block), and the EC codewords per block.
const Map<String, Map<int, (List<(int, int)>, int)>> _blocks =
    <String, Map<int, (List<(int, int)>, int)>>{
  'L': <int, (List<(int, int)>, int)>{
    1: (<(int, int)>[(1, 19)], 7),
    2: (<(int, int)>[(1, 34)], 10),
    3: (<(int, int)>[(1, 55)], 15),
    4: (<(int, int)>[(1, 80)], 20),
    5: (<(int, int)>[(1, 108)], 26),
    6: (<(int, int)>[(2, 68)], 18),
    7: (<(int, int)>[(2, 78)], 20),
    8: (<(int, int)>[(2, 97)], 24),
    9: (<(int, int)>[(2, 116)], 30),
    10: (<(int, int)>[(2, 68), (2, 69)], 18),
  },
  'M': <int, (List<(int, int)>, int)>{
    1: (<(int, int)>[(1, 16)], 10),
    2: (<(int, int)>[(1, 28)], 16),
    3: (<(int, int)>[(1, 44)], 26),
    4: (<(int, int)>[(2, 32)], 18),
    5: (<(int, int)>[(2, 43)], 24),
    6: (<(int, int)>[(4, 27)], 16),
    7: (<(int, int)>[(4, 31)], 18),
    8: (<(int, int)>[(2, 38), (2, 39)], 22),
    9: (<(int, int)>[(3, 36), (2, 37)], 22),
    10: (<(int, int)>[(4, 43), (1, 44)], 26),
  },
};

class QrReadFailure implements Exception {
  QrReadFailure(this.reason);

  final String reason;

  @override
  String toString() => 'QrReadFailure: $reason';
}

/// What a symbol said, and how it said it.
class QrReading {
  QrReading(this.text, this.version, this.level, this.mask);

  final String text;
  final int version;
  final String level;
  final int mask;
}

int _hamming(int a, int b) {
  int x = a ^ b;
  int n = 0;
  while (x != 0) {
    n += x & 1;
    x >>= 1;
  }
  return n;
}

int _gfMul(int a, int b) {
  int r = 0;
  while (b > 0) {
    if (b & 1 == 1) r ^= a;
    a <<= 1;
    if (a & 0x100 != 0) a ^= 0x11D;
    b >>= 1;
  }
  return r;
}

/// Reads [modules], rows of columns with true dark, refusing any symbol that
/// is not exactly a valid byte-mode QR code.
QrReading readQr(List<List<bool>> modules) {
  final int size = modules.length;
  if (size < 21 || (size - 17) % 4 != 0) {
    throw QrReadFailure('a symbol $size modules wide is not a QR code');
  }
  for (final List<bool> row in modules) {
    if (row.length != size) throw QrReadFailure('the symbol is not square');
  }
  final int version = (size - 17) ~/ 4;
  if (version > 10) throw QrReadFailure('version $version is beyond this reader');
  bool dark(int x, int y) => modules[y][x];

  // Finder patterns, with their separators.
  for (final (int cx, int cy) in <(int, int)>[(3, 3), (size - 4, 3), (3, size - 4)]) {
    for (int dy = -4; dy <= 4; dy++) {
      for (int dx = -4; dx <= 4; dx++) {
        final int x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        final int d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        final bool want = d != 2 && d != 4;
        if (dark(x, y) != want) {
          throw QrReadFailure('finder pattern at ($cx, $cy) is wrong at ($x, $y)');
        }
      }
    }
  }
  for (int i = 8; i < size - 8; i++) {
    if (dark(i, 6) != i.isEven || dark(6, i) != i.isEven) {
      throw QrReadFailure('timing pattern is wrong at $i');
    }
  }
  if (!dark(8, size - 8)) throw QrReadFailure('the dark module is missing');

  // Format information, both copies.
  int first = 0, second = 0;
  final List<(int, int)> firstCells = <(int, int)>[
    for (int i = 0; i <= 5; i++) (8, i),
    (8, 7), (8, 8), (7, 8),
    for (int i = 9; i < 15; i++) (14 - i, 8),
  ];
  final List<(int, int)> secondCells = <(int, int)>[
    for (int i = 0; i < 8; i++) (size - 1 - i, 8),
    for (int i = 8; i < 15; i++) (8, size - 15 + i),
  ];
  for (int i = 0; i < 15; i++) {
    if (dark(firstCells[i].$1, firstCells[i].$2)) first |= 1 << i;
    if (dark(secondCells[i].$1, secondCells[i].$2)) second |= 1 << i;
  }
  if (first != second) throw QrReadFailure('the two format copies disagree');
  String? level;
  int? mask;
  _formatWords.forEach((String l, List<int> words) {
    for (int m = 0; m < 8; m++) {
      if (_hamming(words[m], first) == 0) {
        level = l;
        mask = m;
      }
    }
  });
  if (level == null) {
    throw QrReadFailure('format word 0x${first.toRadixString(16)} is not in the table');
  }

  // Version information, both copies, from version 7.
  final Set<String> function = <String>{};
  void reserve(int x, int y) => function.add('$x,$y');
  for (int y = 0; y < 9; y++) {
    for (int x = 0; x < 9; x++) {
      reserve(x, y);
    }
  }
  for (int y = 0; y < 9; y++) {
    for (int x = size - 8; x < size; x++) {
      reserve(x, y);
    }
  }
  for (int y = size - 8; y < size; y++) {
    for (int x = 0; x < 9; x++) {
      reserve(x, y);
    }
  }
  for (int i = 0; i < size; i++) {
    reserve(i, 6);
    reserve(6, i);
  }
  final List<int> centres = _alignment[version]!;
  for (final int ay in centres) {
    for (final int ax in centres) {
      if ((ax == 6 && ay == 6) ||
          (ax == 6 && ay == size - 7) ||
          (ax == size - 7 && ay == 6)) {
        continue;
      }
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          final int d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
          if (dark(ax + dx, ay + dy) != (d != 1)) {
            throw QrReadFailure('alignment pattern at ($ax, $ay) is wrong');
          }
          reserve(ax + dx, ay + dy);
        }
      }
    }
  }
  if (version >= 7) {
    int a = 0, b = 0;
    for (int i = 0; i < 18; i++) {
      final int x = size - 11 + i % 3, y = i ~/ 3;
      if (dark(x, y)) a |= 1 << i;
      if (dark(y, x)) b |= 1 << i;
      reserve(x, y);
      reserve(y, x);
    }
    if (a != _versionWords[version] || b != _versionWords[version]) {
      throw QrReadFailure('version information does not say $version');
    }
  }

  // Codewords, in the placement order, unmasked.
  bool masked(int x, int y) => switch (mask!) {
        0 => (x + y) % 2 == 0,
        1 => y % 2 == 0,
        2 => x % 3 == 0,
        3 => (x + y) % 3 == 0,
        4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
        5 => (x * y) % 2 + (x * y) % 3 == 0,
        6 => ((x * y) % 2 + (x * y) % 3) % 2 == 0,
        _ => ((x + y) % 2 + (x * y) % 3) % 2 == 0,
      };
  final List<bool> bits = <bool>[];
  bool upward = true;
  for (int right = size - 1; right >= 1; right -= 2) {
    if (right == 6) right = 5;
    for (int step = 0; step < size; step++) {
      final int y = upward ? size - 1 - step : step;
      for (final int x in <int>[right, right - 1]) {
        if (function.contains('$x,$y')) continue;
        bits.add(dark(x, y) != masked(x, y));
      }
    }
    upward = !upward;
  }
  final (List<(int, int)> groups, int ecPerBlock) =
      (_blocks[level] ?? const <int, (List<(int, int)>, int)>{})[version] ??
          (throw QrReadFailure('level $level is beyond this reader'));
  final List<int> dataLengths = <int>[
    for (final (int count, int length) in groups)
      for (int i = 0; i < count; i++) length,
  ];
  final int total = dataLengths.fold(0, (int a, int b) => a + b) +
      ecPerBlock * dataLengths.length;
  final List<int> codewords = <int>[
    for (int i = 0; i + 8 <= bits.length && i ~/ 8 < total; i += 8)
      <bool>[for (int j = 0; j < 8; j++) bits[i + j]]
          .fold(0, (int v, bool bit) => (v << 1) | (bit ? 1 : 0)),
  ];
  if (codewords.length != total) {
    throw QrReadFailure('${codewords.length} codewords where $total fit');
  }

  // De-interleave and check each block's syndromes are zero.
  final List<List<int>> blocks = <List<int>>[for (final _ in dataLengths) <int>[]];
  int k = 0;
  final int longest = dataLengths.reduce((int a, int b) => a > b ? a : b);
  for (int i = 0; i < longest; i++) {
    for (int b = 0; b < blocks.length; b++) {
      if (i < dataLengths[b]) blocks[b].add(codewords[k++]);
    }
  }
  for (int i = 0; i < ecPerBlock; i++) {
    for (int b = 0; b < blocks.length; b++) {
      blocks[b].add(codewords[k++]);
    }
  }
  int root = 1;
  for (int s = 0; s < ecPerBlock; s++) {
    for (int b = 0; b < blocks.length; b++) {
      int value = 0;
      for (final int c in blocks[b]) {
        value = _gfMul(value, root) ^ c;
      }
      if (value != 0) {
        throw QrReadFailure('block $b fails error-correction syndrome $s');
      }
    }
    root = _gfMul(root, 2);
  }

  // The data: one byte-mode segment.
  final List<int> data = <int>[
    for (int b = 0; b < blocks.length; b++) ...blocks[b].take(dataLengths[b]),
  ];
  final List<bool> stream = <bool>[
    for (final int byte in data)
      for (int j = 7; j >= 0; j--) (byte >> j) & 1 == 1,
  ];
  int cursor = 0;
  int read(int n) {
    int v = 0;
    for (int i = 0; i < n; i++) {
      v = (v << 1) | (stream[cursor++] ? 1 : 0);
    }
    return v;
  }

  final int mode = read(4);
  if (mode != 4) throw QrReadFailure('mode $mode is not byte mode');
  final int count = read(version < 10 ? 8 : 16);
  final List<int> bytes = <int>[for (int i = 0; i < count; i++) read(8)];
  return QrReading(String.fromCharCodes(bytes), version, level!, mask!);
}
