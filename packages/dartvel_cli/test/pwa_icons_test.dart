// PWA icon generation, from one source image.
//
// The manifest names four icons -- 192 and 512, plain and maskable -- and
// Chrome refuses to install without the two sizes. Generating them needed a
// PNG encoder that was not a dependency, so the manifest pointed at files
// nothing produced and every fresh project was uninstallable until someone
// exported four PNGs by hand.
//
// PNG is small enough to read and write here: a signature, IHDR, one zlib
// stream of filtered scanlines, IEND. dart:io has the zlib. What has to be
// right is the filtering on decode -- a wrong Paeth predictor produces an
// image that is plausibly coloured and subtly wrong, which is exactly the
// kind of failure that ships.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:test/test.dart';

/// A 4x4 RGBA image with a distinct colour per pixel, so any mis-indexing
/// on decode or resize changes an asserted value.
DVRgbaImage sample() {
  final DVRgbaImage image = DVRgbaImage(4, 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      image.set(x, y, r: x * 60, g: y * 60, b: (x + y) * 30, a: 255);
    }
  }
  return image;
}

void main() {
  group('PNG round trip', () {
    test('encode then decode gives the pixels back', () {
      final DVRgbaImage image = sample();
      final DVRgbaImage back = dvPngDecode(dvPngEncode(image));

      expect(back.width, 4);
      expect(back.height, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          expect(back.get(x, y), image.get(x, y), reason: '($x,$y)');
        }
      }
    });

    test('the output starts with the PNG signature', () {
      final Uint8List bytes = dvPngEncode(sample());
      expect(bytes.sublist(0, 8),
          <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });

    test('every filter type decodes', () {
      // An encoder elsewhere may pick any of the five per scanline. A decoder
      // that only handles filter 0 reads the others as garbage without error.
      for (var filter = 0; filter <= 4; filter++) {
        final DVRgbaImage image = sample();
        final DVRgbaImage back =
            dvPngDecode(dvPngEncode(image, filter: filter));
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            expect(back.get(x, y), image.get(x, y),
                reason: 'filter $filter at ($x,$y)');
          }
        }
      }
    });

    test('an RGB image without alpha decodes as opaque', () {
      // Most source icons are RGB. Reading them as RGBA with the wrong stride
      // shears the image diagonally.
      final Uint8List rgb = dvPngEncode(sample(), alpha: false);
      final DVRgbaImage back = dvPngDecode(rgb);
      expect(back.get(1, 2), sample().get(1, 2));
      expect(back.get(3, 3)[3], 255);
    });

    test('something that is not a PNG is refused with a reason', () {
      expect(() => dvPngDecode(Uint8List.fromList(<int>[1, 2, 3])),
          throwsA(isA<DVPngError>()));
      expect(
          () => dvPngDecode(Uint8List.fromList(
              'GIF89a'.codeUnits + List<int>.filled(20, 0))),
          throwsA(isA<DVPngError>().having(
              (DVPngError e) => e.message, 'message', contains('PNG'))));
    });

    test('a truncated PNG is refused rather than read as a smaller image', () {
      final Uint8List whole = dvPngEncode(sample());
      final Uint8List cut = whole.sublist(0, whole.length - 20);
      expect(() => dvPngDecode(cut), throwsA(isA<DVPngError>()));
    });
  });

  group('resizing', () {
    test('a solid image stays solid at every size', () {
      final DVRgbaImage solid = DVRgbaImage(8, 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          solid.set(x, y, r: 10, g: 200, b: 30, a: 255);
        }
      }
      for (final int size in <int>[3, 16, 192]) {
        final DVRgbaImage out = dvResizeRgba(solid, size, size);
        expect(out.get(0, 0), <int>[10, 200, 30, 255], reason: '$size');
        expect(out.get(size - 1, size - 1), <int>[10, 200, 30, 255]);
      }
    });

    test('downscaling averages rather than dropping pixels', () {
      // A checkerboard halved is grey, not black or white: a nearest-
      // neighbour resize would keep one colour and look like an
      // off-by-one that happens to be wrong the same way every time.
      final DVRgbaImage board = DVRgbaImage(4, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final int v = (x + y).isEven ? 0 : 255;
          board.set(x, y, r: v, g: v, b: v, a: 255);
        }
      }
      final DVRgbaImage half = dvResizeRgba(board, 2, 2);
      final List<int> px = half.get(0, 0);
      expect(px[0], inInclusiveRange(120, 135));
    });

    test('the source is left alone', () {
      final DVRgbaImage image = sample();
      dvResizeRgba(image, 2, 2);
      expect(image.get(3, 3), sample().get(3, 3));
    });
  });

  group('the icon set', () {
    late Directory dir;
    late File source;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dv_icons_');
      source = File('${dir.path}/logo.png')
        ..writeAsBytesSync(dvPngEncode(sample()));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes the four icons the manifest names', () {
      final List<String> written =
          dvGeneratePwaIcons(source: source, into: Directory('${dir.path}/web'));

      expect(written, containsAll(<String>[
        'icons/Icon-192.png',
        'icons/Icon-512.png',
        'icons/Icon-maskable-192.png',
        'icons/Icon-maskable-512.png',
      ]));
      for (final String path in written) {
        final DVRgbaImage image =
            dvPngDecode(File('${dir.path}/web/$path').readAsBytesSync());
        final int size = path.contains('512') ? 512 : 192;
        expect(image.width, size, reason: path);
        expect(image.height, size, reason: path);
      }
    });

    test('a maskable icon keeps the artwork inside the safe zone', () {
      // Launchers crop maskable icons to a circle inscribed in the middle
      // 80%. Artwork in the corners is cut off, so it is inset with the
      // background colour rather than scaled to the edge.
      dvGeneratePwaIcons(
        source: source,
        into: Directory('${dir.path}/web'),
        background: 0xFF112233,
      );
      final DVRgbaImage maskable = dvPngDecode(
          File('${dir.path}/web/icons/Icon-maskable-192.png').readAsBytesSync());

      expect(maskable.get(2, 2), <int>[0x11, 0x22, 0x33, 255],
          reason: 'a corner is background');
      expect(maskable.get(96, 96)[3], 255, reason: 'the centre is artwork');
      expect(maskable.get(96, 96), isNot(<int>[0x11, 0x22, 0x33, 255]));
    });

    test('a plain icon is scaled to the edge', () {
      dvGeneratePwaIcons(source: source, into: Directory('${dir.path}/web'));
      final DVRgbaImage plain = dvPngDecode(
          File('${dir.path}/web/icons/Icon-192.png').readAsBytesSync());
      // Top-left of the sample is (0,0,0,255); the plain icon's corner is it.
      expect(plain.get(0, 0), <int>[0, 0, 0, 255]);
    });

    test('a missing source is an error that names the path', () {
      expect(
        () => dvGeneratePwaIcons(
            source: File('${dir.path}/nope.png'),
            into: Directory('${dir.path}/web')),
        throwsA(isA<DVPngError>()
            .having((DVPngError e) => e.message, 'message', contains('nope.png'))),
      );
    });
  });

  group('a PNG another encoder wrote', () {
    // The round-trip tests share one predictor between encoder and decoder,
    // so a bug in it cancels out: invert the Paeth tie-break and every
    // round-trip still passes. Every real icon comes from another encoder,
    // which is exactly the case a round trip cannot see. This is a 4x4 RGBA
    // PNG written by an independent implementation with filter 4 on every
    // row. The pixel values were searched for, not chosen: a first fixture
    // picked by hand contained no tie at which b and c differ, and the
    // inverted tie-break passed against it too. This one is checked to hold
    // at least two.
    const List<int> fixture = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 4, 0, 0, 0, 4, 8, 6, 0, 0, 0, 169, 241, 158, 126, 0, 0, 0, 79, 73, 68, 65, 84, 120, 156, 1, 68, 0, 187, 255, 4, 33, 134, 111, 255, 166, 220, 61, 0, 231, 160, 234, 0, 172, 5, 67, 0, 4, 237, 217, 128, 0, 220, 121, 205, 0, 213, 113, 175, 0, 54, 219, 102, 0, 4, 35, 6, 163, 0, 237, 45, 94, 0, 244, 80, 107, 0, 125, 25, 228, 0, 4, 117, 48, 247, 0, 69, 44, 147, 0, 26, 4, 88, 0, 14, 143, 189, 0, 192, 56, 24, 251, 30, 177, 117, 115, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];

    test('decodes to the pixels that encoder was given', () {
      final DVRgbaImage image = dvPngDecode(Uint8List.fromList(fixture));
      expect(image.width, 4);
      expect(image.get(0, 0), <int>[33, 134, 111, 255], reason: '(0,0)');
      expect(image.get(1, 0), <int>[199, 98, 172, 255], reason: '(1,0)');
      expect(image.get(2, 0), <int>[174, 2, 150, 255], reason: '(2,0)');
      expect(image.get(3, 0), <int>[90, 7, 217, 255], reason: '(3,0)');
      expect(image.get(0, 1), <int>[14, 95, 239, 255], reason: '(0,1)');
      expect(image.get(1, 1), <int>[163, 216, 188, 255], reason: '(1,1)');
      expect(image.get(2, 1), <int>[120, 211, 91, 255], reason: '(2,1)');
      expect(image.get(3, 1), <int>[144, 174, 252, 255], reason: '(3,1)');
      expect(image.get(0, 2), <int>[49, 101, 146, 255], reason: '(0,2)');
      expect(image.get(1, 2), <int>[144, 5, 240, 255], reason: '(1,2)');
      expect(image.get(2, 2), <int>[108, 85, 39, 255], reason: '(2,2)');
      expect(image.get(3, 2), <int>[13, 110, 224, 255], reason: '(3,2)');
      expect(image.get(0, 3), <int>[166, 149, 137, 255], reason: '(0,3)');
      expect(image.get(1, 3), <int>[235, 49, 131, 255], reason: '(1,3)');
      expect(image.get(2, 3), <int>[5, 89, 127, 255], reason: '(2,3)');
      expect(image.get(3, 3), <int>[19, 253, 157, 255], reason: '(3,3)');
    });
  });
}
