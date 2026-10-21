// DVVideoFrameView: raw RGBA frames from a native decoder, drawn by Flutter.
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVVideoFrame solid(int width, int height, List<int> rgba) => DVVideoFrame(
    width: width,
    height: height,
    rgba: Uint8List.fromList(
        List<int>.generate(width * height * 4, (int i) => rgba[i % 4])));

/// Decoding happens off the test's fake clock; wait, in real time, until
/// the image of [width] by [height] is drawn.
Future<RawImage> drawn(WidgetTester tester, int width, int height) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final Finder found = find.byType(RawImage);
    if (found.evaluate().isNotEmpty) {
      final RawImage image = tester.widget<RawImage>(found);
      if (image.image?.width == width && image.image?.height == height) return image;
    }
  }
  fail('no ${width}x$height image was drawn');
}

void main() {
  testWidgets('draws each frame as an image of the frame size', (WidgetTester tester) async {
    final ValueNotifier<DVVideoFrame?> frames = ValueNotifier<DVVideoFrame?>(null);
    await tester.pumpWidget(MaterialApp(home: DVVideoFrameView(frames)));
    expect(find.byType(RawImage), findsNothing);

    frames.value = solid(4, 2, <int>[255, 0, 0, 255]);
    final RawImage first = await drawn(tester, 4, 2);
    expect(first.fit, BoxFit.contain);

    frames.value = solid(8, 6, <int>[0, 0, 255, 255]);
    await drawn(tester, 8, 6);

    frames.value = null;
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
  });

  test('a frame whose bytes do not match its size is refused', () {
    expect(() => DVVideoFrame(width: 4, height: 4, rgba: Uint8List(10)),
        throwsArgumentError);
  });
}
