/// WOFF2, in Dart: what `dartvel build web` and `web-server` turn each font
/// a page downloads into.
///
/// A web page's fonts used to ship as the TrueType files the project bundled,
/// and a TrueType file is mostly redundancy: the sigmadev.digital site sent
/// 1.3 MB of them to every first visitor. WOFF2 is the same tables in one
/// brotli stream, which every engine Flutter web runs on reads -- CanvasKit
/// and skwasm decode it with FreeType, the same way they load the Noto
/// fallback fonts Flutter itself fetches as WOFF2.
///
/// The tables are carried with the *null transform* (section 5 of the W3C
/// WOFF2 recommendation): glyf and loca go into the stream as they are rather
/// than re-encoded into WOFF2's glyph streams. The transform would save a few
/// per cent more and is a few hundred lines of geometry to get exactly right;
/// a font that decodes to its own bytes is the property worth having first.
///
/// Brotli is handed in by the caller, so this file has nothing native in it:
/// the build passes the encoder from the native library it already uses for
/// the web-server binary's assets.
///
/// Reading a font (tables, family, weight axis, which characters it draws) is
/// here too, because the build decides what to subset and what to drop from
/// those facts.
library;

import 'dart:convert' show latin1;
import 'dart:typed_data';

/// An OpenType font file (TrueType or CFF outlines), as its tables.
final class DVSfnt {
  DVSfnt._(this.flavor, this.tables);

  /// The sfnt version: 0x00010000 for TrueType, 'OTTO' for CFF.
  final int flavor;

  /// Each table's bytes, by tag, in the order the file lists them.
  final Map<String, Uint8List> tables;

  /// [bytes] as a font, or a [FormatException] for anything that is not a
  /// single, complete OpenType font: a collection, an already-compressed
  /// WOFF, or a table that runs past the end of the file.
  static DVSfnt parse(Uint8List bytes) {
    if (bytes.length < 12) throw const FormatException('not a font: too short');
    final ByteData data = ByteData.sublistView(bytes);
    final int flavor = data.getUint32(0);
    if (flavor != 0x00010000 && flavor != _tag('OTTO') && flavor != _tag('true')) {
      throw FormatException('not a single OpenType font (sfnt version '
          '0x${flavor.toRadixString(16)})');
    }
    final int count = data.getUint16(4);
    if (count == 0 || 12 + 16 * count > bytes.length) {
      throw const FormatException('font table directory is truncated');
    }
    final Map<String, Uint8List> tables = <String, Uint8List>{};
    for (int i = 0; i < count; i++) {
      final int record = 12 + 16 * i;
      final String tag = latin1.decode(bytes.sublist(record, record + 4));
      final int offset = data.getUint32(record + 8);
      final int length = data.getUint32(record + 12);
      if (offset + length > bytes.length) {
        throw FormatException('font table "$tag" runs past the end of the file');
      }
      tables[tag] = Uint8List.sublistView(bytes, offset, offset + length);
    }
    return DVSfnt._(flavor, tables);
  }
}

/// One variation axis of a variable font (`fvar`).
final class DVFontAxis {
  const DVFontAxis(this.tag, this.min, this.defaultValue, this.max);

  final String tag;
  final double min;
  final double defaultValue;
  final double max;
}

/// What the build needs to know about one font file.
final class DVFontFacts {
  const DVFontFacts({
    required this.family,
    required this.italic,
    required this.weight,
    required this.axes,
    required this.codepoints,
  });

  /// The typographic family (name ID 16, else 1): "Inter" for every Inter
  /// weight and for Inter's variable font alike.
  final String family;

  /// Whether this face is italic (OS/2 fsSelection, else head macStyle).
  final bool italic;

  /// OS/2 usWeightClass: 400 regular, 700 bold.
  final int weight;

  /// The variation axes; empty for a static font.
  final List<DVFontAxis> axes;

  /// Every character the font draws (a glyph other than .notdef).
  final Set<int> codepoints;

  /// The weight axis, or null.
  DVFontAxis? get weightAxis {
    for (final DVFontAxis axis in axes) {
      if (axis.tag == 'wght') return axis;
    }
    return null;
  }
}

/// The facts about the font in [bytes].
DVFontFacts dvFontFacts(Uint8List bytes) {
  final DVSfnt font = DVSfnt.parse(bytes);
  final Uint8List? os2 = font.tables['OS/2'];
  final Uint8List? head = font.tables['head'];
  int weight = 400;
  bool italic = false;
  if (os2 != null && os2.length >= 64) {
    final ByteData d = ByteData.sublistView(os2);
    weight = d.getUint16(4);
    italic = d.getUint16(62) & 1 == 1;
  } else if (head != null && head.length >= 46) {
    italic = ByteData.sublistView(head).getUint16(44) & 2 == 2;
  }
  return DVFontFacts(
    family: _family(font.tables['name']) ?? '',
    italic: italic,
    weight: weight,
    axes: _axes(font.tables['fvar']),
    codepoints: _codepoints(font.tables['cmap']),
  );
}

String? _family(Uint8List? name) {
  if (name == null || name.length < 6) return null;
  final ByteData d = ByteData.sublistView(name);
  final int count = d.getUint16(2);
  final int strings = d.getUint16(4);
  // Best first: typographic family before legacy family, Windows US English
  // before any other Windows record, Windows before Unicode before Mac.
  String? best;
  int bestScore = -1;
  for (int i = 0; i < count; i++) {
    final int r = 6 + 12 * i;
    if (r + 12 > name.length) break;
    final int platform = d.getUint16(r);
    final int encoding = d.getUint16(r + 2);
    final int language = d.getUint16(r + 4);
    final int id = d.getUint16(r + 6);
    final int length = d.getUint16(r + 8);
    final int offset = strings + d.getUint16(r + 10);
    if (id != 1 && id != 16) continue;
    if (offset + length > name.length) continue;
    final Uint8List raw = name.sublist(offset, offset + length);
    final String text;
    int score = id == 16 ? 100 : 0;
    if (platform == 3 && (encoding == 1 || encoding == 10) || platform == 0) {
      text = _utf16be(raw);
      score += platform == 3 ? (language == 0x409 ? 30 : 20) : 10;
    } else if (platform == 1 && encoding == 0) {
      text = latin1.decode(raw);
    } else {
      continue;
    }
    if (text.isNotEmpty && score > bestScore) {
      best = text;
      bestScore = score;
    }
  }
  return best;
}

String _utf16be(Uint8List raw) {
  final List<int> units = <int>[
    for (int i = 0; i + 1 < raw.length; i += 2) (raw[i] << 8) | raw[i + 1],
  ];
  return String.fromCharCodes(units);
}

List<DVFontAxis> _axes(Uint8List? fvar) {
  if (fvar == null || fvar.length < 16) return const <DVFontAxis>[];
  final ByteData d = ByteData.sublistView(fvar);
  final int offset = d.getUint16(4);
  final int count = d.getUint16(8);
  final int size = d.getUint16(10);
  double fixed(int at) => d.getInt32(at) / 65536;
  return <DVFontAxis>[
    for (int i = 0; i < count; i++)
      if (offset + i * size + 20 <= fvar.length)
        DVFontAxis(
          latin1.decode(fvar.sublist(offset + i * size, offset + i * size + 4)),
          fixed(offset + i * size + 4),
          fixed(offset + i * size + 8),
          fixed(offset + i * size + 12),
        ),
  ];
}

/// Every character with a glyph, from every Unicode cmap subtable (formats 4
/// and 12, which between them are what a text font carries).
Set<int> _codepoints(Uint8List? cmap) {
  final Set<int> out = <int>{};
  if (cmap == null || cmap.length < 4) return out;
  final ByteData d = ByteData.sublistView(cmap);
  final int count = d.getUint16(2);
  for (int i = 0; i < count; i++) {
    final int r = 4 + 8 * i;
    if (r + 8 > cmap.length) break;
    final int platform = d.getUint16(r);
    final int encoding = d.getUint16(r + 2);
    final bool unicode =
        platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
    if (!unicode) continue;
    final int at = d.getUint32(r + 4);
    if (at + 2 > cmap.length) continue;
    switch (d.getUint16(at)) {
      case 4:
        _format4(d, at, out);
      case 12:
        _format12(d, at, out);
    }
  }
  return out;
}

void _format4(ByteData d, int at, Set<int> out) {
  if (at + 14 > d.lengthInBytes) return;
  final int segments = d.getUint16(at + 6) ~/ 2;
  final int ends = at + 14;
  final int starts = ends + 2 * segments + 2;
  final int deltas = starts + 2 * segments;
  final int ranges = deltas + 2 * segments;
  if (ranges + 2 * segments > d.lengthInBytes) return;
  for (int s = 0; s < segments; s++) {
    final int end = d.getUint16(ends + 2 * s);
    final int start = d.getUint16(starts + 2 * s);
    final int delta = d.getUint16(deltas + 2 * s);
    final int range = d.getUint16(ranges + 2 * s);
    for (int c = start; c <= end && c != 0xFFFF; c++) {
      int glyph;
      if (range == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        final int address = ranges + 2 * s + range + 2 * (c - start);
        if (address + 2 > d.lengthInBytes) continue;
        glyph = d.getUint16(address);
        if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
      }
      if (glyph != 0) out.add(c);
    }
  }
}

void _format12(ByteData d, int at, Set<int> out) {
  if (at + 16 > d.lengthInBytes) return;
  final int groups = d.getUint32(at + 12);
  for (int g = 0; g < groups; g++) {
    final int r = at + 16 + 12 * g;
    if (r + 12 > d.lengthInBytes) return;
    final int start = d.getUint32(r);
    final int end = d.getUint32(r + 4).clamp(0, 0x10FFFF);
    final int glyph = d.getUint32(r + 8);
    for (int c = start; c <= end; c++) {
      if (glyph + (c - start) != 0) out.add(c);
    }
  }
}

/// [value] as a WOFF2 UIntBase128: big-endian, seven bits a byte, the high
/// bit set on every byte but the last, never a leading zero byte.
List<int> dvUIntBase128(int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw RangeError.range(value, 0, 0xFFFFFFFF, 'value');
  }
  final List<int> out = <int>[value & 0x7F];
  value >>= 7;
  while (value > 0) {
    out.insert(0, 0x80 | (value & 0x7F));
    value >>= 7;
  }
  return out;
}

/// The tags WOFF2 encodes in one byte (its "known tables"), by index.
const List<String> _knownTags = <String>[
  'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ',
  'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp',
  'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF',
  'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL',
  'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc',
  'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx',
  'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill',
];

int _tag(String tag) =>
    (tag.codeUnitAt(0) << 24) | (tag.codeUnitAt(1) << 16) | (tag.codeUnitAt(2) << 8) | tag.codeUnitAt(3);

/// The font in [sfnt] as WOFF2, compressing with [brotli].
///
/// Deterministic: the same font and the same encoder give the same bytes,
/// which matters because the build names each file by its hash.
Uint8List dvWoff2Encode(Uint8List sfnt, {required Uint8List Function(Uint8List) brotli}) {
  final DVSfnt font = DVSfnt.parse(sfnt);
  // Sorted by tag, as an sfnt directory is, with loca moved to straight after
  // glyf: the order WOFF2 requires of the pair.
  final List<String> order = font.tables.keys.toList()
    ..sort((String a, String b) => _tag(a).compareTo(_tag(b)));
  if (order.contains('glyf') != order.contains('loca')) {
    throw const FormatException('font has one of glyf and loca without the other');
  }
  if (order.contains('glyf')) {
    order.remove('loca');
    order.insert(order.indexOf('glyf') + 1, 'loca');
  }

  final BytesBuilder directory = BytesBuilder(copy: false);
  final BytesBuilder stream = BytesBuilder(copy: false);
  int sfntSize = 12 + 16 * order.length;
  for (final String tag in order) {
    final Uint8List table = font.tables[tag]!;
    final int known = _knownTags.indexOf(tag);
    // Transform version 3 is the null transform for glyf and loca; 0 is the
    // null transform for every other table. Neither carries a
    // transformLength.
    final int version = (tag == 'glyf' || tag == 'loca') ? 3 : 0;
    directory.addByte((version << 6) | (known < 0 ? 63 : known));
    if (known < 0) directory.add(latin1.encode(tag));
    directory.add(dvUIntBase128(table.length));
    stream.add(table);
    sfntSize += (table.length + 3) & ~3;
  }
  final Uint8List compressed = brotli(stream.takeBytes());
  final Uint8List dir = directory.takeBytes();
  final int unpadded = 48 + dir.length + compressed.length;
  final int length = (unpadded + 3) & ~3;

  final Uint8List out = Uint8List(length);
  final ByteData header = ByteData.sublistView(out);
  header
    ..setUint32(0, _tag('wOF2'))
    ..setUint32(4, font.flavor)
    ..setUint32(8, length)
    ..setUint16(12, order.length)
    ..setUint16(14, 0)
    ..setUint32(16, sfntSize)
    ..setUint32(20, compressed.length)
    ..setUint16(24, 1)
    ..setUint16(26, 0);
  // metaOffset, metaLength, metaOrigLength, privOffset, privLength: zero.
  out.setRange(48, 48 + dir.length, dir);
  out.setRange(48 + dir.length, unpadded, compressed);
  return out;
}
