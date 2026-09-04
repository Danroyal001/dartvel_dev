// Drawing an image the application holds itself.
//
// A stored image names a key in DV.FileStorage rather than an address, which
// is what an imported design needs: the URLs a Figma import is handed expire,
// and a page that looked right on the day it was imported shows broken images
// a fortnight later. The bytes have to come out of storage and onto the
// screen, on every target, without a URL.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-pixel PNG, which is the smallest thing a decoder will accept.
final Uint8List onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// The frame [provider] resolves to, so a test can assert on the picture
/// rather than on the class that produced it.
Future<ui.Image> resolve(ImageProvider<Object> provider) {
  final Completer<ui.Image> done = Completer<ui.Image>();
  provider.resolve(ImageConfiguration.empty).addListener(
        ImageStreamListener(
          (ImageInfo info, bool _) => done.complete(info.image),
          onError: done.completeError,
        ),
      );
  return done.future;
}

void main() {
  setUp(() {
    DV.FileStorage.configure(DVMemoryFileStorageAdapter());
    // Between tests, or a key read by one is served from the cache to the
    // next and the counting tests measure nothing. Live images as well as
    // cached ones: an image a previous test's widget still holds is not in
    // the cache and is still handed out.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('a stored image decodes the bytes in storage',
      (WidgetTester tester) async {
    // runAsync, because reading storage is real I/O and a widget test's clock
    // is not: without it the read never completes and the test sits until it
    // is killed.
    await tester.runAsync(() async {
      await DV.FileStorage.put('figma/logo.png', onePixelPng,
          contentType: 'image/png');

      final ui.Image frame = await resolve(const DVStoredImage('figma/logo.png'));

      expect(frame.width, 1);
      expect(frame.height, 1);
    });
  });

  testWidgets('the view draws one, by key', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await DV.FileStorage.put('figma/logo.png', onePixelPng);
    });

    await tester.pumpWidget(const MaterialApp(
      home: DVImageView(DVImage.stored('figma/logo.png', alt: 'Logo')),
    ));

    expect(tester.widget<Image>(find.byType(Image)).image,
        const DVStoredImage('figma/logo.png'));
  });

  testWidgets('a key with nothing behind it shows the placeholder, not a crash',
      (WidgetTester tester) async {
    // A document outlives the storage it was written against -- a page
    // restored onto a fresh install, an asset deleted -- and a missing key
    // must not take the page down with it.
    await tester.pumpWidget(const MaterialApp(
      home: DVImageView(
        DVImage.stored('figma/gone.png'),
        placeholder: Text('nothing here'),
      ),
    ));
    await tester.pump();

    expect(find.text('nothing here'), findsOneWidget);
  });

  testWidgets('it is announced by its alt text like any other image',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await DV.FileStorage.put('figma/logo.png', onePixelPng);
    });

    await tester.pumpWidget(const MaterialApp(
      home: DVImageView(DVImage.stored('figma/logo.png', alt: 'The logo')),
    ));

    expect(find.bySemanticsLabel('The logo'), findsOneWidget);
  });

  testWidgets('the same key twice is read once', (WidgetTester tester) async {
    // A page with the same logo in a header and a footer must not read it
    // twice, and a list of cards sharing an image must not read it per row.
    // This is why it is an ImageProvider: Flutter's own cache keys on it.
    await tester.runAsync(() async {
      var reads = 0;
      DV.FileStorage.configure(_CountingStorage(onePixelPng, () => reads++));

      await resolve(const DVStoredImage('figma/logo.png'));
      await resolve(const DVStoredImage('figma/logo.png'));

      expect(reads, 1);
    });
  });

  testWidgets('two keys are two images', (WidgetTester tester) async {
    // The other half of the same rule: sharing a cache entry between
    // different keys would draw one design's logo in another's place.
    await tester.runAsync(() async {
      var reads = 0;
      DV.FileStorage.configure(_CountingStorage(onePixelPng, () => reads++));

      await resolve(const DVStoredImage('figma/one.png'));
      await resolve(const DVStoredImage('figma/two.png'));

      expect(reads, 2);
    });
  });
}

class _CountingStorage implements DVFileStorageAdapter {
  _CountingStorage(this.bytes, this.onRead);

  final Uint8List bytes;
  final void Function() onRead;

  @override
  Future<List<int>> get(String key) async {
    onRead();
    return bytes;
  }

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<bool> exists(String key) async => true;

  @override
  Future<List<String>> list({String prefix = ''}) async => <String>[];
}
