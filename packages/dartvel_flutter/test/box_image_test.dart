// Images and videos are DVBox's, and a bundled one is typed.
//
// DVImageView was a second way to say what DVBox already says, and
// DVImage.asset('assets/logo.png') put a path in a string, which nothing
// checks. A page names a bundled file through the generated DVAsset, and
// shows it with DVBox.image, a background image or a background video.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `dartvel routes` generates for a project's bundled files.
enum _Asset implements DVAssetRef {
  logoSmall('assets/images/logo-small.png', DVAssetKind.image),
  marketingVideo('assets/video/marketing.mp4', DVAssetKind.video);

  const _Asset(this.path, this.kind);

  @override
  final String path;

  @override
  final DVAssetKind kind;
}

void main() {
  testWidgets('DVBox.image shows a bundled image', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVBox.image(_Asset.logoSmall, width: 120, height: 40),
    ));

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName,
        'assets/images/logo-small.png');
  });

  testWidgets('DVBox.image shows an image a model holds',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVBox.image(const DVImage.network('https://example.com/a.png')),
    ));

    expect(find.byType(Image), findsOneWidget);
  });

  test('asking for a video as an image says which asset and what it is', () {
    expect(
      () => DVBox.image(_Asset.marketingVideo),
      throwsA(isA<ArgumentError>().having((ArgumentError e) => '$e', 'it says',
          allOf(contains('marketingVideo'), contains('is a video')))),
    );
  });

  testWidgets('a background image is a modifier, and takes an asset',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const DVBox(DVText('Hero'))
          .modifier(const DVModifier().backgroundImage(_Asset.logoSmall)),
    ));

    // The file is not in a test bundle, and the decoration is what is
    // being asserted rather than the pixels.
    tester.takeException();
    final DecoratedBox box = tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ).firstWhere((DecoratedBox b) =>
        (b.decoration as BoxDecoration).image != null);
    final DecorationImage image = (box.decoration as BoxDecoration).image!;
    expect((image.image as AssetImage).assetName,
        'assets/images/logo-small.png');
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('a background video plays behind its box',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const DVBox(DVText('Hero')).modifier(
          const DVModifier().backgroundVideo(_Asset.marketingVideo)),
    ));
    await tester.pump();

    tester.takeException();
    expect(find.byType(DVBackgroundVideo), findsOneWidget);
    expect(
        tester
            .widget<DVBackgroundVideo>(find.byType(DVBackgroundVideo))
            .source
            .reference,
        'assets/video/marketing.mp4');
  });

  test('a background video refuses anything but a video', () {
    expect(
      () => const DVModifier().backgroundVideo(_Asset.logoSmall),
      throwsA(isA<ArgumentError>()),
    );
  });
}
