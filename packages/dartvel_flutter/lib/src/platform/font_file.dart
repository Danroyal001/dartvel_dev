/// What a font file says about itself: the family, style, weight, width and
/// slant in its own `name`, `OS/2` and `head` tables.
///
/// Windows, macOS and Android hand Dartvel font files rather than families
/// (the registry, CoreText and `/system/fonts` all list paths), so the faces
/// behind `DV.Platform.fonts` are read from the files there. Pure Dart over
/// bytes, so it runs on every target and is tested against fontconfig's own
/// reading of the same files.
///
/// Reads TrueType and OpenType (`0x00010000`, `true`, `OTTO`) and collections
/// (`ttcf`). Not WOFF/WOFF2, which are web formats nobody installs.
library dartvel_flutter.platform.font_file;

import 'dart:convert' show latin1;
import 'dart:typed_data';

/// One face in a font file.
class DVFontFileFace {
  const DVFontFileFace({
    required this.family,
    required this.style,
    required this.weight,
    required this.italic,
    this.width = 5,
    this.index = 0,
  });

  /// The typographic family (`name` ID 16), else the legacy family (ID 1).
  final String family;

  /// The typographic subfamily (ID 17), else the legacy one (ID 2).
  final String style;

  /// `OS/2.usWeightClass`, 1-1000; 400 is regular, 700 bold.
  final int weight;

  /// `OS/2.fsSelection` ITALIC or OBLIQUE, or `head.macStyle` italic.
  final bool italic;

  /// `OS/2.usWidthClass`, 1-9; 5 is normal, below it condensed.
  final int width;

  /// The face's index in a collection; 0 in a plain font.
  final int index;

  @override
  String toString() => 'DVFontFileFace($family $style, $weight${italic ? ' italic' : ''}, width $width, #$index)';
}

/// Reads [length] bytes at [offset] of a font file. Returns fewer at the end.
typedef DVFontFileReader = Uint8List Function(int offset, int length);

/// Every face in the font held in [bytes].
///
/// Throws [FormatException] when [bytes] is not a font, or a face has no
/// family name: a face listed under a name the file does not contain would be
/// a name no `TextStyle` can ever match.
List<DVFontFileFace> dvReadFontFaces(Uint8List bytes) =>
    dvReadFontFacesWith((int offset, int length) {
      if (offset < 0 || offset >= bytes.length) return Uint8List(0);
      final int end = offset + length > bytes.length ? bytes.length : offset + length;
      return Uint8List.sublistView(bytes, offset, end);
    });

/// [dvReadFontFaces] over a reader, so a caller with a file reads only the
/// header and the three tables rather than a 20 MB CJK font.
List<DVFontFileFace> dvReadFontFacesWith(DVFontFileReader read) {
  final ByteData header = _view(read(0, 12), 12);
  final int tag = header.getUint32(0);
  if (tag == _ttcf) {
    final int count = header.getUint32(8);
    if (count == 0 || count > 4096) throw const FormatException('A font collection with no faces.');
    final ByteData offsets = _view(read(12, 4 * count), 4 * count);
    return <DVFontFileFace>[
      for (int i = 0; i < count; i++) _readFace(read, offsets.getUint32(4 * i), i),
    ];
  }
  if (!_isSfnt(tag)) throw const FormatException('Not a TrueType or OpenType font.');
  return <DVFontFileFace>[_readFace(read, 0, 0)];
}

/// Face [index] of the font in [bytes] as a font of its own.
///
/// FontLoader takes one font. A collection handed over whole loads its first
/// face whatever was asked for, so a face from a `.ttc` is rebuilt as a plain
/// font: its tables copied after a new table directory. A plain font is
/// returned as it is for index 0.
Uint8List dvExtractFontFace(Uint8List bytes, int index) {
  final ByteData data = _view(bytes, 12);
  final int tag = data.getUint32(0);
  if (tag != _ttcf) {
    if (!_isSfnt(tag)) throw const FormatException('Not a TrueType or OpenType font.');
    if (index != 0) throw RangeError.range(index, 0, 0, 'index');
    return bytes;
  }
  final int count = data.getUint32(8);
  if (index < 0 || index >= count) throw RangeError.range(index, 0, count - 1, 'index');
  final int start = _view(bytes, 16 + 4 * count).getUint32(12 + 4 * index);
  final ByteData face = _view(Uint8List.sublistView(bytes, start), 12);
  final int tables = face.getUint16(4);
  final int directory = 12 + 16 * tables;
  final ByteData records = _view(Uint8List.sublistView(bytes, start), directory);

  int total = directory;
  for (int i = 0; i < tables; i++) {
    total += (records.getUint32(12 + 16 * i + 12) + 3) & ~3;
  }
  final Uint8List out = Uint8List(total);
  final ByteData outData = ByteData.sublistView(out);
  out.setRange(0, 12, bytes, start);
  int at = directory;
  for (int i = 0; i < tables; i++) {
    final int record = 12 + 16 * i;
    final int offset = records.getUint32(record + 8);
    final int length = records.getUint32(record + 12);
    if (offset + length > bytes.length) throw const FormatException('A table runs past the end of the file.');
    out.setRange(record, record + 16, bytes, start + record);
    outData.setUint32(record + 8, at);
    out.setRange(at, at + length, bytes, offset);
    at += (length + 3) & ~3;
  }
  return out;
}

const int _ttcf = 0x74746366;

bool _isSfnt(int tag) => tag == 0x00010000 || tag == 0x74727565 || tag == 0x4F54544F;

ByteData _view(Uint8List bytes, int needed) {
  if (bytes.length < needed) throw const FormatException('The font file is cut short.');
  return ByteData.sublistView(bytes);
}

DVFontFileFace _readFace(DVFontFileReader read, int start, int index) {
  final ByteData header = _view(read(start, 12), 12);
  if (!_isSfnt(header.getUint32(0))) throw const FormatException('Not a TrueType or OpenType face.');
  final int count = header.getUint16(4);
  final ByteData records = _view(read(start + 12, 16 * count), 16 * count);
  final Map<String, (int, int)> tables = <String, (int, int)>{};
  for (int i = 0; i < count; i++) {
    final int record = 16 * i;
    final String tag = String.fromCharCodes(<int>[
      for (int c = 0; c < 4; c++) records.getUint8(record + c),
    ]);
    tables[tag] = (records.getUint32(record + 8), records.getUint32(record + 12));
  }

  Uint8List? table(String tag) {
    final (int, int)? where = tables[tag];
    if (where == null) return null;
    final Uint8List bytes = read(where.$1, where.$2);
    return bytes.length < where.$2 ? null : bytes;
  }

  final Uint8List? name = table('name');
  if (name == null) throw const FormatException('The font has no name table.');
  final Map<int, String> names = _names(name);
  final String? family = names[16] ?? names[1];
  if (family == null || family.trim().isEmpty) throw const FormatException('The font names no family.');
  final String style = names[17] ?? names[2] ?? 'Regular';

  int weight = 400;
  int width = 5;
  bool italic = false;
  final Uint8List? os2 = table('OS/2');
  if (os2 != null && os2.length >= 64) {
    final ByteData data = ByteData.sublistView(os2);
    final int declared = data.getUint16(4);
    if (declared >= 1 && declared <= 1000) weight = declared;
    final int declaredWidth = data.getUint16(6);
    if (declaredWidth >= 1 && declaredWidth <= 9) width = declaredWidth;
    final int selection = data.getUint16(62);
    // ITALIC (bit 0), or OBLIQUE (bit 9, OS/2 version 4 and later).
    italic = selection & 0x01 != 0 || selection & 0x200 != 0;
  }
  final Uint8List? head = table('head');
  if (!italic && head != null && head.length >= 46) {
    italic = ByteData.sublistView(head).getUint16(44) & 0x02 != 0;
  }
  return DVFontFileFace(
    family: family.trim(),
    style: style.trim(),
    weight: weight,
    italic: italic,
    width: width,
    index: index,
  );
}

/// The names in a `name` table by ID, preferring Windows Unicode US English,
/// then any Windows Unicode, then Unicode, then Mac Roman.
Map<int, String> _names(Uint8List table) {
  if (table.length < 6) return const <int, String>{};
  final ByteData data = ByteData.sublistView(table);
  final int count = data.getUint16(2);
  final int storage = data.getUint16(4);
  final Map<int, (int, String)> best = <int, (int, String)>{};
  for (int i = 0; i < count; i++) {
    final int record = 6 + 12 * i;
    if (record + 12 > table.length) break;
    final int platform = data.getUint16(record);
    final int encoding = data.getUint16(record + 2);
    final int language = data.getUint16(record + 4);
    final int id = data.getUint16(record + 6);
    final int length = data.getUint16(record + 8);
    final int offset = storage + data.getUint16(record + 10);
    if (offset + length > table.length) continue;
    final int rank;
    if (platform == 3 && (encoding == 1 || encoding == 10)) {
      rank = language == 0x0409 ? 0 : 1;
    } else if (platform == 0) {
      rank = 2;
    } else if (platform == 1 && encoding == 0) {
      rank = language == 0 ? 3 : 4;
    } else {
      continue;
    }
    if (best[id] != null && best[id]!.$1 <= rank) continue;
    final Uint8List raw = Uint8List.sublistView(table, offset, offset + length);
    final String text = platform == 1 ? latin1.decode(raw) : _utf16be(raw);
    if (text.isEmpty) continue;
    best[id] = (rank, text);
  }
  return <int, String>{for (final MapEntry<int, (int, String)> e in best.entries) e.key: e.value.$2};
}

String _utf16be(Uint8List raw) {
  final List<int> units = <int>[
    for (int i = 0; i + 1 < raw.length; i += 2) (raw[i] << 8) | raw[i + 1],
  ];
  return String.fromCharCodes(units);
}

// Where a platform gives a face's style only as a name ("Bold Italic",
// "Light") and no numbers -- the browser's Local Font Access API does, so weight, slant and width are read from the name. The bytes the
// engine is given carry the real ones; these only choose which face of a
// family fills which weight.

int dvFontWeightFromStyle(String style) {
  final String s = style.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final (String word, int weight) in const <(String, int)>[
    ('thin', 100), ('hairline', 100),
    ('extralight', 200), ('ultralight', 200),
    ('semibold', 600), ('demibold', 600),
    ('extrabold', 800), ('ultrabold', 800),
    ('black', 900), ('heavy', 900),
    ('light', 300), ('medium', 500), ('bold', 700),
  ]) {
    if (s.contains(word)) return weight;
  }
  return 400;
}

bool dvFontItalicFromStyle(String style) {
  final String s = style.toLowerCase();
  return s.contains('italic') || s.contains('oblique');
}

int dvFontWidthFromStyle(String style) {
  final String s = style.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (s.contains('ultracondensed')) return 1;
  if (s.contains('extracondensed')) return 2;
  if (s.contains('semicondensed')) return 4;
  if (s.contains('condensed') || s.contains('narrow')) return 3;
  if (s.contains('semiexpanded')) return 6;
  if (s.contains('extraexpanded')) return 8;
  if (s.contains('expanded') || s.contains('wide')) return 7;
  return 5;
}
