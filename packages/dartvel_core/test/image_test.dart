import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVImage', () {
    test('round-trips through JSON', () {
      const image = DVImage.network(
        'https://example.com/cover.png',
        alt: 'A cover',
        width: 800,
        height: 600,
      );

      final restored = DVImage.fromJson(image.toJson());

      expect(restored, image);
      expect(restored!.source, DVImageSource.network);
    });

    test('reads a bare URL string', () {
      // An existing API commonly stores an image column as a plain URL.
      final image = DVImage.fromJson('https://example.com/a.png');

      expect(image, isNotNull);
      expect(image!.source, DVImageSource.network);
      expect(image.reference, 'https://example.com/a.png');
    });

    test('accepts url and src as aliases for reference', () {
      expect(
        DVImage.fromJson(<String, Object?>{'url': 'a.png'})?.reference,
        'a.png',
      );
      expect(
        DVImage.fromJson(<String, Object?>{'src': 'b.png'})?.reference,
        'b.png',
      );
    });

    test('null and empty resolve to no image rather than an empty one', () {
      expect(DVImage.fromJson(null), isNull);
      expect(DVImage.fromJson(''), isNull);
    });

    test('a map with no reference is an error, not a blank image', () {
      expect(
        () => DVImage.fromJson(<String, Object?>{'alt': 'no source'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DVImage.fromJson(42),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an unknown source falls back to network rather than throwing', () {
      final image = DVImage.fromJson(<String, Object?>{
        'reference': 'https://example.com/a.png',
        'source': 'cdn',
      });

      expect(image!.source, DVImageSource.network);
    });

    test('asset and file sources survive serialization', () {
      for (final DVImage image in <DVImage>[
        const DVImage.asset('assets/a.png'),
        const DVImage.file('/tmp/a.png'),
      ]) {
        expect(DVImage.fromJson(image.toJson()), image);
      }
    });
  });
}
