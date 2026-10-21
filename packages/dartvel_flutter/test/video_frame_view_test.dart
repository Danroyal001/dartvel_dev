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

void main() {
  testWidgets('draws each frame as an image of the frame size', (WidgetTester tester) async {
    final ValueNotifier<DVVideoFrame?> frames = ValueNotifier<DVVideoFrame?>(null);
    await tester.pumpWidget(MaterialApp(home: DVVideoFrameView(frames)));
    expect(find.byType(RawImage), findsNothing);

    frames.value = solid(4, 2, <int>[255, 0, 0, 255]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    final RawImage drawn = tester.widget<RawImage>(find.byType(RawImage));
    expect((drawn.image!.width, drawn.image!.height), (4, 2));
    expect(drawn.fit, BoxFit.contain);

    frames.value = solid(8, 6, <int>[0, 0, 255, 255]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    final RawImage next = tester.widget<RawImage>(find.byType(RawImage));
    expect((next.image!.width, next.image!.height), (8, 6));

    frames.value = null;
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
  });

  test('a frame whose bytes do not match its size is refused', () {
    expect(() => DVVideoFrame(width: 4, height: 4, rgba: Uint8List(10)),
        throwsArgumentError);
  });
}
