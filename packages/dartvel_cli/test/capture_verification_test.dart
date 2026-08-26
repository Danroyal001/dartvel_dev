// Whether a screenshot shows an application.
//
// Every runtime-verification job asserted `test -s capture.png`, which a blank
// screen satisfies. `import -window root` on an Xvfb display always produces a
// full-size PNG: if the app crashed before its first frame, the capture is
// 1280x900 of black, weighs a few kilobytes, and passes. That is how a browser
// extension job went green on a screenshot of Chrome's first-run dialog and
// then on a blank page.
//
// These assert on what is in the image.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/capture_verification.dart';
import 'package:test/test.dart';

/// A minimal 8-bit truecolour PNG encoder, so these tests do not depend on the
/// decoder under test to build their fixtures.
List<int> encodePng(int width, int height, List<List<int>> pixels) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      final p = pixels[y * width + x];
      raw..addByte(p[0])..addByte(p[1])..addByte(p[2]);
    }
  }
  final idat = ZLibCodec().encode(raw.toBytes());

  Uint8List chunk(String type, List<int> data) {
    final out = BytesBuilder();
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    final body = <int>[...ascii.encode(type), ...data];
    out.add(body);
    final crcValue = ByteData(4)..setUint32(0, _crc32(body));
    out.add(crcValue.buffer.asUint8List());
    return out.toBytes();
  }

  final ihdr = BytesBuilder();
  final dims = ByteData(8)
    ..setUint32(0, width)
    ..setUint32(4, height);
  ihdr.add(dims.buffer.asUint8List());
  ihdr..addByte(8)..addByte(2)..addByte(0)..addByte(0)..addByte(0);

  return <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', ihdr.toBytes()),
    ...chunk('IDAT', idat),
    ...chunk('IEND', const <int>[]),
  ];
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> solid(int w, int h, List<int> colour) =>
    encodePng(w, h, List<List<int>>.generate(w * h, (_) => colour));

void main() {
  group('reading the image', () {
    test('a PNG reports its own dimensions', () {
      final result = verifyCapture(solid(1280, 900, <int>[0, 0, 0]));
      expect(result.width, 1280);
      expect(result.height, 900);
    });

    test('bytes that are not a PNG are not a capture', () {
      expect(verifyCapture(ascii.encode('not an image')).ok, isFalse);
      expect(verifyCapture(ascii.encode('not an image')).reasons.first,
          contains('PNG'));
    });
  });

  group('rejecting an empty screen', () {
    test('a screen of one colour is not an application', () {
      // The exact shape of a crashed app under `import -window root`.
      final verdict = verifyCapture(solid(1280, 900, <int>[0, 0, 0]));

      expect(verdict.ok, isFalse);
      expect(verdict.distinctColours, 1);
      expect(verdict.reasons.join(' '), contains('one colour'));
    });

    test('white is as empty as black', () {
      expect(verifyCapture(solid(800, 600, <int>[255, 255, 255])).ok, isFalse);
    });

    test('a capture dominated by its background is still empty', () {
      // A window that opened and painted nothing but its own chrome: a
      // handful of pixels differ, and the eye would call it blank.
      final pixels = List<List<int>>.generate(
          800 * 600, (_) => <int>[18, 18, 18]);
      for (var i = 0; i < 40; i++) {
        pixels[i] = <int>[200, 30, 30];
      }

      final verdict = verifyCapture(encodePng(800, 600, pixels));

      expect(verdict.ok, isFalse);
      expect(verdict.dominantFraction, greaterThan(0.99));
      expect(verdict.reasons.join(' '), contains('background'));
    });
  });

  group('accepting a rendered application', () {
    List<int> renderedUi() {
      // A background, a header band, and text-like speckle: few enough
      // colours to be a real UI, spread widely enough not to be blank.
      final pixels = List<List<int>>.generate(400 * 300, (int i) {
        final y = i ~/ 400;
        if (y < 60) return <int>[33, 90, 160];
        if (y % 7 == 0) return <int>[40, 40, 40];
        return <int>[245, 245, 245];
      });
      return encodePng(400, 300, pixels);
    }

    test('a rendered screen passes', () {
      final verdict = verifyCapture(renderedUi());

      expect(verdict.ok, isTrue, reason: verdict.reasons.join('; '));
      expect(verdict.distinctColours, greaterThan(1));
      expect(verdict.dominantFraction, lessThan(0.99));
    });

    test('an expected colour must actually be present', () {
      expect(
        verifyCapture(renderedUi(), expectColour: <int>[33, 90, 160]).ok,
        isTrue,
      );
      final missing =
          verifyCapture(renderedUi(), expectColour: <int>[255, 0, 255]);
      expect(missing.ok, isFalse);
      expect(missing.reasons.join(' '), contains('expected colour'));
    });

    test('a capture smaller than a window is not a screen', () {
      final verdict = verifyCapture(renderedUi(), minWidth: 640, minHeight: 480);

      expect(verdict.ok, isFalse);
      expect(verdict.reasons.join(' '), contains('400x300'));
    });
  });
}
