// An image from bytes the app already holds: an app icon from the system, a
// photo just taken, a chart drawn in memory. No file, no URL, no storage key.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final Uint8List png = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  test('DVImage.memory keeps the bytes and names its source', () {
    final DVImage image = DVImage.memory(png, alt: 'Termux');
    expect(image.source, DVImageSource.memory);
    expect(image.alt, 'Termux');
    expect(image.bytes, png);
  });

  test('it is a data URI, so it serialises like every other image', () {
    final DVImage image = DVImage.memory(png, mimeType: 'image/webp');
    expect(image.reference, 'data:image/webp;base64,${base64Encode(png)}');
    final DVImage? back = DVImage.fromJson(jsonDecode(jsonEncode(image.toJson())));
    expect(back?.source, DVImageSource.memory);
    expect(back?.bytes, png);
  });

  test('bytes is null for an image that is not in memory', () {
    expect(const DVImage.network('https://example.com/a.png').bytes, isNull);
  });

  test('empty bytes are refused rather than drawn as a broken image', () {
    expect(() => DVImage.memory(Uint8List(0)), throwsArgumentError);
  });
}
