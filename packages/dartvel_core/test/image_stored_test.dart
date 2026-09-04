// An image the application holds, rather than one it points at.
//
// DVImage could name a URL, a bundled asset or a path on disk. All three are
// references to something outside the application's own storage, and for an
// imported design that is the whole problem: a Figma import writes the URL
// Figma hands back, those expire, and an application that looked right on the
// day it was imported shows broken images a fortnight later.
//
// A stored image names a key in DV.FileStorage instead. The bytes are the
// application's own -- nothing to expire, nothing to bundle at build time,
// and it works on every target because the storage adapter does.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a stored image names a key rather than an address', () {
    const DVImage image = DVImage.stored('figma/1-2/logo.png', alt: 'Logo');

    expect(image.source, DVImageSource.stored);
    expect(image.reference, 'figma/1-2/logo.png');
    expect(image.alt, 'Logo');
  });

  test('it survives a round trip through a model\'s JSON', () {
    // Page documents and model fields are stored as JSON, so an image that
    // cannot be read back is an image that only works until it is saved.
    const DVImage image = DVImage.stored('figma/1-2/logo.png', width: 64);

    final DVImage? read = DVImage.fromJson(image.toJson());

    expect(read, isNotNull);
    expect(read!.source, DVImageSource.stored);
    expect(read.reference, 'figma/1-2/logo.png');
    expect(read.width, 64);
  });

  test('a bare string is still a URL, as an existing API sends it', () {
    // The reading that was there before this: unchanged, because a column
    // full of URLs must not start being read as storage keys.
    expect(DVImage.fromJson('https://example.com/a.png')?.source,
        DVImageSource.network);
  });

  test('a source nobody knows is still read as a URL', () {
    // Tempting to refuse it now that a misspelled "stored" would be fetched
    // as an address. It stays lenient: fromJson is on the path that loads
    // models from data the application does not control, and throwing there
    // takes down a page load over one unexpected string. A key is written
    // programmatically by the importer, never typed, so the reader is the
    // wrong place to catch a typo.
    expect(
      DVImage.fromJson(<String, Object?>{
        'reference': 'https://example.com/a.png',
        'source': 'cdn',
      })?.source,
      DVImageSource.network,
    );
  });
}
