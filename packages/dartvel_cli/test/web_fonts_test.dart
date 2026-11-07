// The fonts a web page downloads before its first frame.
//
// Flutter web fetches every font in FontManifest.json, and the engine waits
// for them before it draws, so font bytes sit directly on the path to the
// first frame. The sigmadev.digital site sent 1.3 MB of them to each first
// visitor: four static Inter weights beside the variable Inter that already
// draws every weight, every font whole when the site writes in Latin, and
// Roboto from fonts.gstatic.com because the engine asks for it whenever the
// manifest has none.
//
// Each rule below drops or shrinks something a page might draw, so each is
// tested on the case that must NOT change: a static face the variable one
// cannot stand in for is kept, a family the app names is kept, a character
// the app's own text uses survives subsetting.
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_cli/src/build/web_fonts.dart';
import 'package:dartvel_cli/src/build/woff2.dart';
import 'package:dartvel_core/binary_payload.dart' show DVAssetEncoding;
import 'package:dartvel_shelf/native_codec.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

DVFontFacts facts({
  String family = 'Inter',
  int weight = 400,
  bool italic = false,
  List<DVFontAxis> axes = const <DVFontAxis>[],
  Set<int>? codepoints,
}) =>
    DVFontFacts(
      family: family,
      italic: italic,
      weight: weight,
      axes: axes,
      codepoints: codepoints ?? <int>{for (int c = 0x20; c < 0x250; c++) c},
    );

const DVFontAxis weightAxis = DVFontAxis('wght', 100, 400, 900);

/// The sigmadev.digital manifest, as Flutter wrote it.
List<DVManifestFamily> siteManifest() => dvParseFontManifest(jsonEncode(<Object?>[
      <String, Object?>{
        'family': 'MaterialIcons',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'fonts/MaterialIcons-Regular.otf'},
        ],
      },
      <String, Object?>{
        'family': 'InterVariable',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'assets/fonts/InterVariable.ttf'},
        ],
      },
      <String, Object?>{
        'family': 'Inter',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'assets/fonts/Inter-Regular.ttf'},
          <String, Object?>{'weight': 500, 'asset': 'assets/fonts/Inter-Medium.ttf'},
          <String, Object?>{'weight': 600, 'asset': 'assets/fonts/Inter-SemiBold.ttf'},
          <String, Object?>{'weight': 700, 'asset': 'assets/fonts/Inter-Bold.ttf'},
        ],
      },
    ]));

Map<String, DVFontFacts> siteFacts({DVFontFacts? bold}) => <String, DVFontFacts>{
      'assets/fonts/InterVariable.ttf': facts(axes: const <DVFontAxis>[weightAxis]),
      'assets/fonts/Inter-Regular.ttf': facts(),
      'assets/fonts/Inter-Medium.ttf': facts(weight: 500),
      'assets/fonts/Inter-SemiBold.ttf': facts(weight: 600),
      'assets/fonts/Inter-Bold.ttf': bold ?? facts(weight: 700),
    };

void main() {
  group('the manifest', () {
    test('reads and writes back the way Flutter wrote it', () {
      final List<DVManifestFamily> manifest = siteManifest();
      expect(manifest.map((DVManifestFamily f) => f.family),
          <String>['MaterialIcons', 'InterVariable', 'Inter']);
      expect(manifest[2].fonts[1].weight, 500);
      expect(manifest[2].fonts[0].weight, isNull);
      final List<Object?> again =
          jsonDecode(dvEncodeFontManifest(manifest)) as List<Object?>;
      expect(again[2], <String, Object?>{
        'family': 'Inter',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'assets/fonts/Inter-Regular.ttf'},
          <String, Object?>{'weight': 500, 'asset': 'assets/fonts/Inter-Medium.ttf'},
          <String, Object?>{'weight': 600, 'asset': 'assets/fonts/Inter-SemiBold.ttf'},
          <String, Object?>{'weight': 700, 'asset': 'assets/fonts/Inter-Bold.ttf'},
        ],
      });
    });
  });

  group('static weights a variable font already draws', () {
    test('are served by the variable font', () {
      // The engine sets the wght axis from every TextStyle's FontWeight
      // (CanvasKit and skwasm alike), so one variable file draws 400, 500,
      // 600 and 700 -- the four static files were a second copy.
      expect(dvVariableReplacements(siteManifest(), siteFacts()),
          <String, String>{'Inter': 'assets/fonts/InterVariable.ttf'});
    });

    test('are kept when one of them is italic and the variable one is not', () {
      expect(
          dvVariableReplacements(
              siteManifest(), siteFacts(bold: facts(weight: 700, italic: true))),
          isEmpty);
    });

    test('are kept when one is outside the weight axis', () {
      expect(
          dvVariableReplacements(siteManifest(), <String, DVFontFacts>{
            ...siteFacts(),
            'assets/fonts/InterVariable.ttf':
                facts(axes: const <DVFontAxis>[DVFontAxis('wght', 100, 400, 600)]),
          }),
          isEmpty);
    });

    test('are kept when one draws a character the variable font does not', () {
      expect(
          dvVariableReplacements(
              siteManifest(),
              siteFacts(
                  bold: facts(
                      weight: 700,
                      codepoints: <int>{for (int c = 0x20; c < 0x250; c++) c, 0x0416}))),
          isEmpty);
    });

    test('are served by the variable font when what it lacks is nothing the page writes',
        () {
      // Inter 4.1's static files draw ♪ ♫ and the som sign; the variable
      // file beside them does not. A page that writes none of them draws
      // nothing differently, and a reader who types one gets the engine's
      // Noto fallback either way once the fonts are subset.
      final Set<int> gap = <int>{0x266A, 0x266B, 0x20C0};
      expect(
          dvVariableReplacements(
              siteManifest(),
              siteFacts(
                  bold: facts(
                      weight: 700,
                      codepoints: <int>{for (int c = 0x20; c < 0x250; c++) c, ...gap})),
              required: dvFontSubsetCharacters(project: const <int>{}, base: dvFontCoreRanges)),
          <String, String>{'Inter': 'assets/fonts/InterVariable.ttf'});
      // ...and kept when the page does write one.
      expect(
          dvVariableReplacements(
              siteManifest(),
              siteFacts(
                  bold: facts(
                      weight: 700,
                      codepoints: <int>{for (int c = 0x20; c < 0x250; c++) c, ...gap})),
              required: dvFontSubsetCharacters(project: <int>{0x266A}, base: dvFontCoreRanges)),
          isEmpty);
    });

    test('are kept when the designs are different families', () {
      expect(
          dvVariableReplacements(siteManifest(), <String, DVFontFacts>{
            ...siteFacts(),
            'assets/fonts/InterVariable.ttf':
                facts(family: 'Roboto Flex', axes: const <DVFontAxis>[weightAxis]),
          }),
          isEmpty);
    });

    test('match a variable font named "<Family> Variable"', () {
      expect(
          dvVariableReplacements(siteManifest(), <String, DVFontFacts>{
            ...siteFacts(),
            'assets/fonts/InterVariable.ttf':
                facts(family: 'Inter Variable', axes: const <DVFontAxis>[weightAxis]),
          }),
          <String, String>{'Inter': 'assets/fonts/InterVariable.ttf'});
    });
  });

  group('families nothing names', () {
    final List<DVManifestFamily> manifest = dvParseFontManifest(jsonEncode(<Object?>[
      <String, Object?>{
        'family': 'SpaceGrotesk',
        'fonts': <Object?>[<String, Object?>{'asset': 'assets/fonts/SpaceGrotesk-Regular.ttf'}],
      },
      <String, Object?>{
        'family': 'packages/dartvel_flutter/Manrope',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'packages/dartvel_flutter/assets/fonts/Manrope.ttf'},
        ],
      },
      <String, Object?>{
        'family': 'MaterialIcons',
        'fonts': <Object?>[<String, Object?>{'asset': 'fonts/MaterialIcons-Regular.otf'}],
      },
    ]));
    Uint8List code(String text) => Uint8List.fromList(utf8.encode(text));

    test('are dropped when no compiled code and no data names them', () {
      expect(
          dvUnusedFamilies(manifest,
              code: <Uint8List>[code('var a="SpaceGrotesk",b="MaterialIcons";')],
              texts: const <String>[]),
          <String>{'packages/dartvel_flutter/Manrope'});
    });

    test('are kept when the code builds the name from its package path', () {
      // dart2js keeps 'packages/$fontPackage/Manrope' as a concatenation.
      expect(
          dvUnusedFamilies(manifest,
              code: <Uint8List>[code('x="packages/"+p+"/Manrope";y="SpaceGrotesk";z="MaterialIcons"')],
              texts: const <String>[]),
          isEmpty);
    });

    test('are kept when only data (a Studio page, a JSON asset) names them', () {
      expect(
          dvUnusedFamilies(manifest,
              code: <Uint8List>[code('"MaterialIcons"')],
              texts: const <String>['{"fontFamily":"SpaceGrotesk","x":"Manrope"}']),
          isEmpty);
    });

    test('are found in a wasm module, whose strings are UTF-8 or UTF-16', () {
      final Uint8List wasm = Uint8List.fromList(<int>[
        0, 0x61, 0x73, 0x6d,
        ...utf8.encode('SpaceGrotesk'),
        for (final int unit in 'Manrope'.codeUnits) ...<int>[unit, 0],
        ...utf8.encode('MaterialIcons'),
      ]);
      expect(dvUnusedFamilies(manifest, code: <Uint8List>[wasm], texts: const <String>[]),
          isEmpty);
    });

    test('are all kept when there is no compiled code to look in', () {
      expect(dvUnusedFamilies(manifest, code: const <Uint8List>[], texts: const <String>[]),
          isEmpty);
    });
  });

  group('the characters kept', () {
    late Directory project;
    setUp(() => project = Directory.systemTemp.createTempSync('dv_web_fonts_chars_'));
    tearDown(() => project.deleteSync(recursive: true));

    test('are every Latin letter and common symbol, and what the app writes', () {
      File(p.join(project.path, 'lib', 'home.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync("const greeting = 'Ẹ káàbọ̀ — Привет ₦';");
      File(p.join(project.path, 'assets', 'copy.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"title":"Ελλάδα"}');
      // Build output and tool caches are not the app's text.
      File(p.join(project.path, 'build', 'web', 'x.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('"中文"');
      final Set<int> keep = dvFontSubsetCharacters(project: dvProjectCharacters(project.path));
      for (final String c in <String>['A', 'z', 'é', 'ß', 'ẹ', 'ọ', 'ɗ', '₦', '€', '—', '“', '→']) {
        expect(keep, contains(c.runes.single), reason: c);
      }
      for (final String c in <String>['П', 'и', 'Ε', 'λ']) {
        expect(keep, contains(c.runes.single), reason: c);
      }
      expect(keep, contains(0x0300)); // combining grave, for ẹ̀
      expect(keep, isNot(contains('中'.runes.single)));
    });

    test('include what the project lists under dartvel.web.fonts.characters', () {
      final Set<int> keep = dvFontSubsetCharacters(
          project: const <int>{}, extra: dvParseCharacters(<Object?>['U+0400-04FF', 'ŋ']));
      expect(keep, contains(0x0416));
      expect(keep, contains('ŋ'.runes.single));
    });
  });

  group('a build', () {
    final Uri cli = Isolate.resolvePackageUriSync(
        Uri.parse('package:dartvel_cli/src/build/web_fonts.dart'))!;
    final String packages =
        p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
    final Uint8List manrope = File(
            p.join(packages, 'dartvel_flutter', 'assets', 'fonts', 'Manrope.ttf'))
        .readAsBytesSync();
    final host = dvHostServerLibrary();
    final DVNativeCodec codec = DVNativeCodec.of(DynamicLibrary.open(
        p.join(packages, 'dartvel_shelf', 'lib', 'native', host.subdir, host.name)))!;
    final String? flutterRoot = dvFlutterRootSync();
    final String? subsetTool = flutterRoot == null ? null : dvFontSubsetTool(flutterRoot);
    final File? roboto = flutterRoot == null ? null : dvRobotoSource(flutterRoot);

    late Directory web;
    setUp(() {
      web = Directory.systemTemp.createTempSync('dv_web_fonts_build_');
      File(p.join(web.path, 'assets', 'packages', 'dartvel_flutter', 'assets', 'fonts', 'Manrope.ttf'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(manrope);
      File(p.join(web.path, 'assets', 'FontManifest.json')).writeAsStringSync(jsonEncode(<Object?>[
        <String, Object?>{
          'family': 'packages/dartvel_flutter/Manrope',
          'fonts': <Object?>[
            <String, Object?>{'asset': 'packages/dartvel_flutter/assets/fonts/Manrope.ttf'},
          ],
        },
      ]));
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync('x="packages/"+p+"/Manrope"');
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('serves subset WOFF2 under a content-hashed name, and Roboto from the site',
        () async {
      if (subsetTool == null || roboto == null) {
        markTestSkipped('no Flutter SDK with font-subset and material_fonts here');
        return;
      }
      final DVWebFontsReport report = await dvOptimizeWebFonts(
        web: web,
        characters: dvFontSubsetCharacters(project: <int>{'ŋ'.runes.single}),
        subsetTool: subsetTool,
        roboto: roboto,
        brotli: (Uint8List b) => codec.encode(DVAssetEncoding.br, b)!,
      );
      final List<DVManifestFamily> manifest = dvParseFontManifest(
          File(p.join(web.path, 'assets', 'FontManifest.json')).readAsStringSync());
      expect(manifest.map((DVManifestFamily f) => f.family),
          <String>['packages/dartvel_flutter/Manrope', 'Roboto']);
      for (final DVManifestFamily family in manifest) {
        final String asset = family.fonts.single.asset;
        // A hashed name is what lets a server send it as immutable.
        expect(asset, matches(RegExp(r'^dartvel/fonts/[A-Za-z-]+\.[0-9a-f]{16}\.woff2$')));
        final Uint8List bytes = File(p.join(web.path, 'assets', asset)).readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'wOF2');
      }
      // Manrope keeps its weight axis and the app's own characters, and loses
      // what nobody here writes.
      final Uint8List woff2 = File(p.join(web.path, 'assets', manifest[0].fonts.single.asset))
          .readAsBytesSync();
      final DVFontFacts subset = dvFontFacts(_decodeWoff2(woff2, codec));
      // HarfBuzz keeps name IDs 1-6 only, so the file's own name becomes the
      // default instance's legacy one ("Manrope ExtraLight"). The engine
      // registers a face under the manifest's family, never the file's, so
      // that name is not what text asks for.
      expect(subset.family, startsWith('Manrope'));
      expect(subset.weightAxis?.max, 800);
      expect(subset.codepoints, containsAll('AZaz09€ŋ'.runes));
      // Manrope draws Cyrillic; nothing in this project writes any.
      expect(dvFontFacts(manrope).codepoints, contains('Ж'.runes.single));
      expect(subset.codepoints, isNot(contains('Ж'.runes.single)));
      expect(woff2.length, lessThan(manrope.length ~/ 2));
      // The original stays where it was: rootBundle may still ask for it.
      expect(
          File(p.join(web.path, 'assets', 'packages', 'dartvel_flutter', 'assets', 'fonts',
                  'Manrope.ttf'))
              .existsSync(),
          isTrue);
      expect(report.lines.join('\n'), matches(RegExp(r'fonts: [\d.]+ [KM]B -> [\d.]+ KB')));
      expect(report.bytesAfter, lessThan(report.bytesBefore));
    });

    test('never subsets away an icon font\'s icons', () async {
      // MaterialIcons maps a few ASCII letters as well as its icons, which
      // live in the Private Use Area. Subsetting it to "Latin" would keep the
      // letters and blank every icon on the page.
      final File? icons = flutterRoot == null
          ? null
          : File(p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts',
              'MaterialIcons-Regular.otf'));
      if (subsetTool == null || icons == null || !icons.existsSync()) {
        markTestSkipped('no Flutter SDK with font-subset and material_fonts here');
        return;
      }
      final Uint8List source = icons.readAsBytesSync();
      File(p.join(web.path, 'assets', 'fonts', 'MaterialIcons-Regular.otf'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(source);
      File(p.join(web.path, 'assets', 'FontManifest.json')).writeAsStringSync(jsonEncode(<Object?>[
        <String, Object?>{
          'family': 'MaterialIcons',
          'fonts': <Object?>[<String, Object?>{'asset': 'fonts/MaterialIcons-Regular.otf'}],
        },
      ]));
      File(p.join(web.path, 'main.dart.js')).writeAsStringSync('f="MaterialIcons"');
      await dvOptimizeWebFonts(
        web: web,
        characters: dvFontSubsetCharacters(project: const <int>{}),
        subsetTool: subsetTool,
        brotli: (Uint8List b) => codec.encode(DVAssetEncoding.br, b)!,
      );
      final List<DVManifestFamily> manifest = dvParseFontManifest(
          File(p.join(web.path, 'assets', 'FontManifest.json')).readAsStringSync());
      final String asset = manifest.single.fonts.single.asset;
      final Uint8List out = File(p.join(web.path, 'assets', asset)).readAsBytesSync();
      final Uint8List font =
          asset.endsWith('.woff2') ? _decodeWoff2(out, codec) : out;
      final Set<int> privateUse = <int>{
        for (final int c in dvFontFacts(source).codepoints)
          if (c >= 0xE000 && c <= 0xF8FF) c,
      };
      expect(privateUse, isNotEmpty);
      expect(dvFontFacts(font).codepoints, containsAll(privateUse));
    });

    test('leaves the manifest alone when it is switched off', () async {
      final String before =
          File(p.join(web.path, 'assets', 'FontManifest.json')).readAsStringSync();
      await dvOptimizeWebFonts(
        web: web,
        characters: dvFontSubsetCharacters(project: const <int>{}),
        options: const DVWebFontsOptions(enabled: false),
        subsetTool: subsetTool,
        roboto: roboto,
        brotli: (Uint8List b) => codec.encode(DVAssetEncoding.br, b)!,
      );
      expect(File(p.join(web.path, 'assets', 'FontManifest.json')).readAsStringSync(), before);
    });
  });
}

/// The sfnt a WOFF2 file with null-transformed tables decodes to: enough of
/// a reconstruction for [dvFontFacts] to read it back.
Uint8List _decodeWoff2(Uint8List woff2, DVNativeCodec codec) {
  final ByteData d = ByteData.sublistView(woff2);
  final int count = d.getUint16(12);
  const List<String> known = <String>[
    'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ',
    'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp',
    'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF',
    'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL',
    'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc',
    'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx',
    'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill',
  ];
  int at = 48;
  int base128() {
    int v = 0;
    while (true) {
      final int b = woff2[at++];
      v = (v << 7) | (b & 0x7F);
      if (b & 0x80 == 0) return v;
    }
  }

  final List<(String, int)> tables = <(String, int)>[];
  for (int i = 0; i < count; i++) {
    final int flags = woff2[at++];
    String tag;
    if (flags & 0x3F == 63) {
      tag = String.fromCharCodes(woff2.sublist(at, at + 4));
      at += 4;
    } else {
      tag = known[flags & 0x3F];
    }
    tables.add((tag, base128()));
  }
  final int total = tables.fold(0, (int a, (String, int) t) => a + t.$2);
  final Uint8List stream =
      codec.decode(DVAssetEncoding.br, woff2.sublist(at, at + d.getUint32(20)), total);
  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(12 + 16 * count)
    ..setUint32(0, d.getUint32(4))
    ..setUint16(4, count);
  int offset = 12 + 16 * count;
  int read = 0;
  final List<Uint8List> bodies = <Uint8List>[];
  for (int i = 0; i < count; i++) {
    final (String tag, int length) = tables[i];
    for (int k = 0; k < 4; k++) {
      header.setUint8(12 + 16 * i + k, tag.codeUnitAt(k));
    }
    header
      ..setUint32(12 + 16 * i + 8, offset)
      ..setUint32(12 + 16 * i + 12, length);
    final Uint8List body = stream.sublist(read, read + length);
    read += length;
    bodies.add(Uint8List((length + 3) & ~3)..setAll(0, body));
    offset += (length + 3) & ~3;
  }
  out.add(header.buffer.asUint8List());
  for (final Uint8List b in bodies) {
    out.add(b);
  }
  return out.takeBytes();
}
