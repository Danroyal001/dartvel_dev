// DVImageView writes each image's slot into the page, where the build's
// capture reads it.
//
// The capture sees which file a page fetched and cannot see how wide it was
// drawn: the 384-wide variant says only that the slot was somewhere under
// 384. The link prefetch needs the slot itself, to pick the file for a denser
// screen than the build's, and this is the one place it is written down. The
// capture reads `JSON.stringify(globalThis.__dartvelImages)`; this reads the
// same object, in a real page.
//
// Run with: flutter test --platform chrome test/image_layout_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double? recorded(String src) => globalContext
    .getProperty<JSObject?>('__dartvelImages'.toJS)
    ?.getProperty<JSNumber?>(src.toJS)
    ?.toDartDouble;

Widget slot(double width, DVImage image) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: DVImageView(image)),
        ),
      ),
    );

void main() {
  setUp(() {
    globalContext.delete('__dartvelImages'.toJS);
    DVImageView.variants = const DVImageVariants(
      assetWidths: <String, int>{'assets/assets/hero.png': 1600},
    );
  });
  tearDown(DVImageView.resetVariants);

  testWidgets('an image records the slot it was laid out in',
      (WidgetTester tester) async {
    await tester.pumpWidget(slot(320, const DVImage.asset('assets/hero.png')));

    expect(recorded('assets/assets/hero.png'), 320);
  });

  testWidgets('the widest slot is kept, since one file has to paint them all',
      (WidgetTester tester) async {
    await tester.pumpWidget(slot(500, const DVImage.asset('assets/hero.png')));
    await tester.pumpWidget(slot(200, const DVImage.asset('assets/hero.png')));

    expect(recorded('assets/assets/hero.png'), 500);
  });

  testWidgets('nothing is recorded where there are no variants',
      (WidgetTester tester) async {
    DVImageView.resetVariants();

    await tester.pumpWidget(slot(320, const DVImage.asset('assets/hero.png')));

    expect(recorded('assets/assets/hero.png'), isNull);
  });
}
