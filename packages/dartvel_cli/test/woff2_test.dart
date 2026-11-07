// WOFF2, written by the build for every font a web page downloads.
//
// A font the engine cannot parse is silent in the worst way: CanvasKit and
// skwasm log a warning, draw the text in the fallback face, and the page
// still "works". So what is checked here is that the file decodes back to
// exactly the tables it was made from, read by a decoder written from the
// specification rather than by the encoder's own reader -- and that it is
// laid out the way a decoder is allowed to insist on (glyf and loca as a
// pair, sizes that add up). That CanvasKit's FreeType accepts the result is
// checked in a real browser; see docs/web-performance.md.
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_cli/src/build/woff2.dart';
import 'package:dartvel_core/binary_payload.dart' show DVAssetEncoding;
import 'package:dartvel_shelf/native_codec.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
      Uri.parse('package:dartvel_cli/src/build/woff2.dart'))!;
  final String packages =
      p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
  // The framework's own default face: a variable TrueType font with a weight
  // axis, which is the hardest ordinary case (glyf, loca, fvar, gvar).
  final Uint8List manrope = File(
          p.join(packages, 'dartvel_flutter', 'assets', 'fonts', 'Manrope.ttf'))
      .readAsBytesSync();
  final host = dvHostServerLibrary();
  final DVNativeCodec codec = DVNativeCodec.of(DynamicLibrary.open(
      p.join(packages, 'dartvel_shelf', 'lib', 'native', host.subdir, host.name)))!;
  Uint8List brotli(Uint8List bytes) => codec.encode(DVAssetEncoding.br, bytes)!;

  group('reading a font', () {
    test('lists its tables, each as the bytes it holds', () {
      final DVSfnt font = DVSfnt.parse(manrope);
      expect(font.flavor, 0x00010000);
      expect(font.tables.keys,
          containsAll(<String>['cmap', 'glyf', 'loca', 'head', 'fvar', 'gvar']));
      // head is 54 bytes and starts with version 1.0.
      expect(font.tables['head']!.length, 54);
      expect(font.tables['head']!.sublist(0, 4), <int>[0, 1, 0, 0]);
    });

    test('says what a font is: family, weight axis, the characters it has', () {
      final DVFontFacts facts = dvFontFacts(manrope);
      expect(facts.family, 'Manrope');
      expect(facts.italic, isFalse);
      final DVFontAxis weight = facts.axes.firstWhere((DVFontAxis a) => a.tag == 'wght');
      expect(weight.min, 200);
      expect(weight.max, 800);
      expect(facts.codepoints, containsAll('AZaz09'.codeUnits));
      // A character Manrope does not draw is not claimed.
      expect(facts.codepoints, isNot(contains(0x4E2D))); // 中
    });

    test('refuses something that is not a font, rather than guessing', () {
      expect(() => DVSfnt.parse(Uint8List.fromList('<!doctype html>'.codeUnits)),
          throwsFormatException);
      // A table directory pointing past the end of the file.
      final Uint8List truncated = Uint8List.fromList(manrope.sublist(0, 400));
      expect(() => DVSfnt.parse(truncated), throwsFormatException);
    });
  });

  group('UIntBase128', () {
    test('is big-endian base 128 with no leading zero byte', () {
      expect(dvUIntBase128(0), <int>[0]);
      expect(dvUIntBase128(63), <int>[63]);
      expect(dvUIntBase128(127), <int>[127]);
      expect(dvUIntBase128(128), <int>[0x81, 0x00]);
      expect(dvUIntBase128(16384), <int>[0x81, 0x80, 0x00]);
      expect(dvUIntBase128(0xFFFFFFFF), <int>[0x8F, 0xFF, 0xFF, 0xFF, 0x7F]);
    });
  });

  group('the WOFF2 file', () {
    late Uint8List woff2;
    late _Woff2 decoded;
    setUpAll(() {
      woff2 = dvWoff2Encode(manrope, brotli: brotli);
      decoded = _Woff2.decode(woff2, codec);
    });

    test('decodes back to every table, byte for byte', () {
      final DVSfnt original = DVSfnt.parse(manrope);
      expect(decoded.tables.keys.toSet(), original.tables.keys.toSet());
      for (final String tag in original.tables.keys) {
        expect(decoded.tables[tag], original.tables[tag], reason: tag);
      }
    });

    test('has a header whose sizes add up', () {
      expect(decoded.signature, 0x774F4632); // 'wOF2'
      expect(decoded.flavor, 0x00010000);
      expect(decoded.length, woff2.length);
      expect(woff2.length % 4, 0);
      final DVSfnt original = DVSfnt.parse(manrope);
      int sfnt = 12 + 16 * original.tables.length;
      for (final Uint8List t in original.tables.values) {
        sfnt += (t.length + 3) & ~3;
      }
      expect(decoded.totalSfntSize, sfnt);
    });

    test('keeps glyf and loca as an untransformed pair, loca right after glyf', () {
      final int glyf = decoded.order.indexOf('glyf');
      expect(decoded.order[glyf + 1], 'loca');
      expect(decoded.transform['glyf'], 3);
      expect(decoded.transform['loca'], 3);
      for (final String tag in decoded.order) {
        if (tag != 'glyf' && tag != 'loca') expect(decoded.transform[tag], 0, reason: tag);
      }
    });

    test('is much smaller than the TrueType it came from', () {
      expect(woff2.length, lessThan(manrope.length * 0.6));
    });

    test('is the same bytes every time, so a rebuild changes no file name', () {
      expect(dvWoff2Encode(manrope, brotli: brotli), woff2);
    });
  });
}

/// A WOFF2 reader written from the specification (section 5), independent of
/// the encoder: header, table directory, one brotli stream.
final class _Woff2 {
  _Woff2(this.signature, this.flavor, this.length, this.totalSfntSize,
      this.order, this.transform, this.tables);

  final int signature;
  final int flavor;
  final int length;
  final int totalSfntSize;
  final List<String> order;
  final Map<String, int> transform;
  final Map<String, Uint8List> tables;

  static const List<String> _known = <String>[
    'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ',
    'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp',
    'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF',
    'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL',
    'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc',
    'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx',
    'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill',
  ];

  static _Woff2 decode(Uint8List bytes, DVNativeCodec codec) {
    final ByteData data = ByteData.sublistView(bytes);
    int offset = 48;
    int base128() {
      int value = 0;
      for (int i = 0; i < 5; i++) {
        final int b = bytes[offset++];
        if (i == 0 && b == 0x80) throw const FormatException('leading zero');
        value = (value << 7) | (b & 0x7F);
        if (b & 0x80 == 0) return value;
      }
      throw const FormatException('UIntBase128 over five bytes');
    }

    final int numTables = data.getUint16(12);
    final List<String> order = <String>[];
    final Map<String, int> transform = <String, int>{};
    final Map<String, int> lengths = <String, int>{};
    for (int i = 0; i < numTables; i++) {
      final int flags = bytes[offset++];
      final int index = flags & 0x3F;
      final String tag;
      if (index == 63) {
        tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        offset += 4;
      } else {
        tag = _known[index];
      }
      final int version = flags >> 6;
      final int origLength = base128();
      final bool transformed = (tag == 'glyf' || tag == 'loca') ? version != 3 : version != 0;
      if (transformed) base128();
      order.add(tag);
      transform[tag] = version;
      lengths[tag] = origLength;
    }
    final int compressed = data.getUint32(20);
    final int total = lengths.values.fold(0, (int a, int b) => a + b);
    final Uint8List stream =
        codec.decode(DVAssetEncoding.br, bytes.sublist(offset, offset + compressed), total);
    final Map<String, Uint8List> tables = <String, Uint8List>{};
    int at = 0;
    for (final String tag in order) {
      tables[tag] = stream.sublist(at, at + lengths[tag]!);
      at += lengths[tag]!;
    }
    return _Woff2(data.getUint32(0), data.getUint32(4), data.getUint32(8),
        data.getUint32(16), order, transform, tables);
  }
}
