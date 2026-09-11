// DVImageView asks for the variant its slot needs, and a link prefetches
// exactly that one.
//
// NextFaster's images are served at a fixed set of widths, and its links warm
// the srcset entry the visitor's screen will pick. Here the widget works out
// the width from its own layout and the screen's pixel ratio, and the link
// prefetch works it out from what the build recorded -- through the same
// function, so the image the link fetched is the one the page asks for, under
// the same cache key.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const DVImageVariants built = DVImageVariants(
  endpoint: true,
  remoteHosts: <String>['cdn.example.com'],
  assetWidths: <String, int>{'assets/assets/hero.png': 1600},
);

Future<ImageProvider> providerIn(
  WidgetTester tester,
  DVImage image, {
  double slot = 320,
  double devicePixelRatio = 1,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: devicePixelRatio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: slot, child: DVImageView(image)),
        ),
      ),
    ),
  );
  return tester.widget<Image>(find.byType(Image)).image;
}

void main() {
  tearDown(DVImageView.resetVariants);

  group('with no variants built', () {
    testWidgets('an image is fetched as it always was, with no layout pass',
        (WidgetTester tester) async {
      final ImageProvider provider =
          await providerIn(tester, const DVImage.asset('assets/hero.png'));

      expect(provider, const AssetImage('assets/hero.png'));
      // A LayoutBuilder throws inside intrinsic sizing, so an application
      // that configured nothing must not get one it did not ask for.
      expect(find.byType(LayoutBuilder), findsNothing);
    });
  });

  group('with variants built', () {
    setUp(() => DVImageView.variants = built);

    testWidgets('an asset asks for the written variant its slot needs',
        (WidgetTester tester) async {
      expect(
        await providerIn(tester, const DVImage.asset('assets/hero.png')),
        const NetworkImage('assets/_dartvel/img/384/assets/assets/hero.png'),
      );
    });

    testWidgets('a denser screen asks for a larger one',
        (WidgetTester tester) async {
      expect(
        await providerIn(tester, const DVImage.asset('assets/hero.png'),
            devicePixelRatio: 2),
        const NetworkImage('assets/_dartvel/img/640/assets/assets/hero.png'),
      );
    });

    testWidgets('a slot wider than the image uses the image itself',
        (WidgetTester tester) async {
      expect(
        await providerIn(tester, const DVImage.asset('assets/hero.png'),
            slot: 1000, devicePixelRatio: 2),
        const AssetImage('assets/hero.png'),
      );
    });

    testWidgets('an allowed remote image goes through the server',
        (WidgetTester tester) async {
      expect(
        await providerIn(
            tester, const DVImage.network('https://cdn.example.com/a.jpg'),
            slot: 700),
        const NetworkImage(
            '_dartvel/image?src=https%3A%2F%2Fcdn.example.com%2Fa.jpg&w=750&q=75'),
      );
    });

    testWidgets('a remote image from a host nobody allowed is fetched as is',
        (WidgetTester tester) async {
      expect(
        await providerIn(
            tester, const DVImage.network('https://elsewhere.org/a.jpg')),
        const NetworkImage('https://elsewhere.org/a.jpg'),
      );
    });

    testWidgets('an unbounded slot uses the width the image declares',
        (WidgetTester tester) async {
      // A pixel ratio of 1, set rather than assumed: the test view's default
      // is 3, and the widget is right to use whichever the screen has.
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: <Widget>[
              DVImageView(DVImage.asset('assets/hero.png', width: 100)),
            ]),
          ),
        ),
      );
      expect(tester.widget<Image>(find.byType(Image)).image,
          const NetworkImage('assets/_dartvel/img/128/assets/assets/hero.png'));
    });
  });

  group('the link prefetches the variant the page will ask for', () {
    const String manifest = '''
{"routes": {"/docs": {"scripts": [], "images": [
  {"url": "assets/_dartvel/img/384/assets/assets/hero.png", "as": "fetch",
   "variant": {"src": "assets/assets/hero.png", "width": 320}}
]}}}
''';

    test('at this screen\'s pixel ratio, not the build\'s', () {
      expect(
        dvPrefetchImages(manifest, '/docs',
            variants: built, devicePixelRatio: 1),
        <String>['assets/_dartvel/img/384/assets/assets/hero.png'],
      );
      expect(
        dvPrefetchImages(manifest, '/docs',
            variants: built, devicePixelRatio: 2),
        <String>['assets/_dartvel/img/640/assets/assets/hero.png'],
      );
    });

    test('under the key the widget will look it up by', () {
      for (final double ratio in <double>[1, 2, 3]) {
        final String url = dvPrefetchImages(manifest, '/docs',
                variants: built, devicePixelRatio: ratio)
            .single;
        expect(
          DVRoutePrefetch.providerFor(url),
          dvImageVariantProvider(
                  const DVImage.asset('assets/hero.png'), 320 * ratio, built) ??
              const AssetImage('assets/hero.png'),
          reason: 'at $ratio',
        );
      }
    });

    test('a build with no variants prefetches the recorded address', () {
      expect(dvPrefetchImages(manifest, '/docs'),
          <String>['assets/_dartvel/img/384/assets/assets/hero.png']);
    });
  });
}
