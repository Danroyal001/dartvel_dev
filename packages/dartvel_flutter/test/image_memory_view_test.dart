// DVBox.image draws an image from bytes, and a rebuild reuses the decoded bytes.
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1x1 transparent PNG.
final Uint8List _onePixel = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  test('a memory image becomes a MemoryImage with the same bytes', () {
    final ImageProvider<Object>? provider = DVImageRender.providerFor(DVImage.memory(_onePixel));
    expect(provider, isA<MemoryImage>());
    expect((provider! as MemoryImage).bytes, _onePixel);
  });

  test('the same image twice is the same provider, so the cache is not missed', () {
    final DVImage image = DVImage.memory(_onePixel);
    expect(DVImageRender.providerFor(image), equals(DVImageRender.providerFor(DVImage.memory(_onePixel))));
  });

  testWidgets('DVBox.image draws it', (WidgetTester tester) async {
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: DVBox.image(DVImage.memory(_onePixel, alt: 'dot'), width: 24, height: 24)));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
