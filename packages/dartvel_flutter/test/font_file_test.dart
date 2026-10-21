// Reading a font file's own tables: the family, style, weight, width and
// slant a font says it has, from `name`, `OS/2` and `head`.
//
// Windows, macOS and Android hand Dartvel font *files* (the registry, CoreText
// and /system/fonts list paths), and a family list built from file names is
// wrong in the quiet way: "arialbd.ttf" is not a family, and "DejaVu Sans
// Condensed" is a face of DejaVu Sans, not a family of its own. So the faces
// are read from the files, and the expected values below come from fontconfig
// (`fc-scan`) reading the same files -- an independent reader, not this one.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_flutter/src/platform/font_file.dart';
import 'package:flutter_test/flutter_test.dart';

const String dejavu = '/usr/share/fonts/truetype/dejavu';

void main() {
  final bool haveDejaVu = File('$dejavu/DejaVuSans.ttf').existsSync();
  final String? skipDejaVu = haveDejaVu ? null : 'DejaVu fonts are not installed here';

  Uint8List read(String name) => File('$dejavu/$name').readAsBytesSync();

  group('a real font file', () {
    test('regular', () {
      final List<DVFontFileFace> faces = dvReadFontFaces(read('DejaVuSans.ttf'));
      expect(faces, hasLength(1));
      expect(faces.single.family, 'DejaVu Sans');
      expect(faces.single.style, 'Book');
      expect(faces.single.weight, 400);
      expect(faces.single.italic, isFalse);
      expect(faces.single.width, 5);
      expect(faces.single.index, 0);
    }, skip: skipDejaVu);

    test('bold oblique is bold and italic', () {
      final DVFontFileFace face = dvReadFontFaces(read('DejaVuSans-BoldOblique.ttf')).single;
      expect(face.family, 'DejaVu Sans');
      expect(face.style, 'Bold Oblique');
      expect(face.weight, 700);
      expect(face.italic, isTrue);
    }, skip: skipDejaVu);

    test('the typographic family wins over the legacy one', () {
      // nameID 1 is "DejaVu Sans Light", a family Windows' four-style model
      // invented; nameID 16 says the face belongs to DejaVu Sans. fontconfig
      // lists "DejaVu Sans" first for the same reason.
      final DVFontFileFace face = dvReadFontFaces(read('DejaVuSans-ExtraLight.ttf')).single;
      expect(face.family, 'DejaVu Sans');
      expect(face.style, 'ExtraLight');
      expect(face.weight, 200);
    }, skip: skipDejaVu);

    test('a condensed face is a narrower face of the family, not a family', () {
      final DVFontFileFace face = dvReadFontFaces(read('DejaVuSansCondensed-BoldOblique.ttf')).single;
      expect(face.family, 'DejaVu Sans');
      expect(face.style, 'Condensed Bold Oblique');
      expect(face.width, lessThan(5));
    }, skip: skipDejaVu);
  });

  group('a collection (.ttc)', () {
    final Uint8List collection = buildCollection(<Uint8List>[
      buildFont(family: 'Probe Sans', style: 'Regular', weight: 400),
      buildFont(family: 'Probe Sans', style: 'Bold Italic', weight: 700, italic: true),
    ]);

    test('lists every face with its index', () {
      final List<DVFontFileFace> faces = dvReadFontFaces(collection);
      expect(faces.map((DVFontFileFace f) => f.index), <int>[0, 1]);
      expect(faces[1].style, 'Bold Italic');
      expect(faces[1].weight, 700);
      expect(faces[1].italic, isTrue);
    });

    test('one face comes out as a font of its own', () {
      // What the engine is given: FontLoader takes one font, and a collection
      // handed over whole loads its first face whatever was asked for.
      final Uint8List alone = dvExtractFontFace(collection, 1);
      final DVFontFileFace face = dvReadFontFaces(alone).single;
      expect(face.family, 'Probe Sans');
      expect(face.style, 'Bold Italic');
      expect(face.index, 0);
    });

    test('a face that is not there is refused', () {
      expect(() => dvExtractFontFace(collection, 2), throwsRangeError);
    });
  });

  test('a plain font is its own only face', () {
    final Uint8List font = buildFont(family: 'Probe Serif', style: 'Regular', weight: 400);
    expect(identical(dvExtractFontFace(font, 0), font), isTrue);
    expect(() => dvExtractFontFace(font, 1), throwsRangeError);
  });

  test('what is not a font is a FormatException, not a crash', () {
    expect(() => dvReadFontFaces(Uint8List.fromList(List<int>.filled(64, 7))), throwsFormatException);
    expect(() => dvReadFontFaces(Uint8List(3)), throwsFormatException);
  });

  test('a font with no name table is refused rather than given a made-up name', () {
    final Uint8List font = buildFont(family: 'x', style: 'x', weight: 400, withName: false);
    expect(() => dvReadFontFaces(font), throwsFormatException);
  });

  test('a style name alone gives the weight, slant and width', () {
    // The browser's Local Font Access API names a face's style and gives no
    // numbers. "ExtraLight" must not read as Light, nor "SemiBold" as Bold.
    expect(dvFontWeightFromStyle('Regular'), 400);
    expect(dvFontWeightFromStyle('Bold Italic'), 700);
    expect(dvFontWeightFromStyle('ExtraLight'), 200);
    expect(dvFontWeightFromStyle('Light'), 300);
    expect(dvFontWeightFromStyle('SemiBold Condensed'), 600);
    expect(dvFontWeightFromStyle('Extra-Bold'), 800);
    expect(dvFontItalicFromStyle('Bold Oblique'), isTrue);
    expect(dvFontItalicFromStyle('Book'), isFalse);
    expect(dvFontWidthFromStyle('SemiBold Condensed'), 3);
    expect(dvFontWidthFromStyle('Semi Condensed'), 4);
    expect(dvFontWidthFromStyle('Regular'), 5);
  });
}

// --- A minimal sfnt builder: name, OS/2 and head, which is all the reader
// reads. Enough to make a collection without shipping one.

Uint8List buildFont({
  required String family,
  required String style,
  required int weight,
  bool italic = false,
  bool withName = true,
}) {
  final Map<String, Uint8List> tables = <String, Uint8List>{
    'OS/2': _os2(weight, italic),
    'head': _head(italic),
    if (withName) 'name': _name(<int, String>{1: family, 2: style}),
  };
  return _sfnt(tables, 0);
}

Uint8List _sfnt(Map<String, Uint8List> tables, int base) {
  final List<String> tags = tables.keys.toList()..sort();
  final int headerLength = 12 + 16 * tags.length;
  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(headerLength);
  header.setUint32(0, 0x00010000);
  header.setUint16(4, tags.length);
  int offset = headerLength;
  final List<Uint8List> bodies = <Uint8List>[];
  for (int i = 0; i < tags.length; i++) {
    final Uint8List body = tables[tags[i]]!;
    final int record = 12 + 16 * i;
    for (int c = 0; c < 4; c++) {
      header.setUint8(record + c, tags[i].codeUnitAt(c));
    }
    header.setUint32(record + 8, base + offset);
    header.setUint32(record + 12, body.length);
    final int padded = (body.length + 3) & ~3;
    bodies.add(Uint8List(padded)..setRange(0, body.length, body));
    offset += padded;
  }
  out.add(header.buffer.asUint8List());
  for (final Uint8List body in bodies) {
    out.add(body);
  }
  return out.toBytes();
}

Uint8List buildCollection(List<Uint8List> fonts) {
  // Table offsets in a collection are from the start of the file, so each
  // font is rebuilt at its place rather than copied in.
  final int headerLength = 12 + 4 * fonts.length;
  final List<Uint8List> placed = <Uint8List>[];
  int at = headerLength;
  for (final Uint8List font in fonts) {
    final Uint8List rebuilt = _rebase(font, at);
    placed.add(rebuilt);
    at += rebuilt.length;
  }
  final ByteData header = ByteData(headerLength);
  header.setUint32(0, 0x74746366); // 'ttcf'
  header.setUint32(4, 0x00010000);
  header.setUint32(8, fonts.length);
  int offset = headerLength;
  for (int i = 0; i < placed.length; i++) {
    header.setUint32(12 + 4 * i, offset);
    offset += placed[i].length;
  }
  final BytesBuilder out = BytesBuilder()..add(header.buffer.asUint8List());
  for (final Uint8List font in placed) {
    out.add(font);
  }
  return out.toBytes();
}

Uint8List _rebase(Uint8List font, int base) {
  final ByteData data = ByteData.sublistView(font);
  final Uint8List copy = Uint8List.fromList(font);
  final ByteData out = ByteData.sublistView(copy);
  final int count = data.getUint16(4);
  for (int i = 0; i < count; i++) {
    final int record = 12 + 16 * i;
    out.setUint32(record + 8, data.getUint32(record + 8) + base);
  }
  return copy;
}

Uint8List _os2(int weight, bool italic) {
  final ByteData os2 = ByteData(78);
  os2.setUint16(0, 4); // version
  os2.setUint16(4, weight); // usWeightClass
  os2.setUint16(6, 5); // usWidthClass
  os2.setUint16(62, italic ? 0x01 : 0x40); // fsSelection: ITALIC or REGULAR
  return os2.buffer.asUint8List();
}

Uint8List _head(bool italic) {
  final ByteData head = ByteData(54);
  head.setUint32(0, 0x00010000);
  head.setUint32(12, 0x5F0F3CF5); // magic
  head.setUint16(44, italic ? 0x02 : 0x00); // macStyle
  return head.buffer.asUint8List();
}

Uint8List _name(Map<int, String> names) {
  // Format 0, Windows Unicode BMP, US English: UTF-16BE strings.
  final List<MapEntry<int, String>> entries = names.entries.toList();
  final int storage = 6 + 12 * entries.length;
  final BytesBuilder strings = BytesBuilder();
  final ByteData header = ByteData(storage);
  header.setUint16(0, 0);
  header.setUint16(2, entries.length);
  header.setUint16(4, storage);
  int offset = 0;
  for (int i = 0; i < entries.length; i++) {
    final ByteData text = ByteData(entries[i].value.length * 2);
    for (int c = 0; c < entries[i].value.length; c++) {
      text.setUint16(c * 2, entries[i].value.codeUnitAt(c));
    }
    final int record = 6 + 12 * i;
    header.setUint16(record, 3);
    header.setUint16(record + 2, 1);
    header.setUint16(record + 4, 0x0409);
    header.setUint16(record + 6, entries[i].key);
    header.setUint16(record + 8, text.lengthInBytes);
    header.setUint16(record + 10, offset);
    strings.add(text.buffer.asUint8List());
    offset += text.lengthInBytes;
  }
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(strings.toBytes()))
      .toBytes();
}
