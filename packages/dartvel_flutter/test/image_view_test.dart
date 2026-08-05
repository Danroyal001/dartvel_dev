import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders each source through the matching provider',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(DVImage.network('https://example.com/a.png')),
      ),
    );
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<NetworkImage>().having(
        (NetworkImage provider) => provider.url,
        'url',
        'https://example.com/a.png',
      ),
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(DVImage.asset('assets/a.png')),
      ),
    );
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<AssetImage>().having(
        (AssetImage provider) => provider.assetName,
        'assetName',
        'assets/a.png',
      ),
    );
  });

  testWidgets('a null image renders the placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(null, placeholder: Text('no cover')),
      ),
    );

    expect(find.text('no cover'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('alt text becomes an image semantics label',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(
          DVImage.network('https://example.com/a.png', alt: 'A red bicycle'),
        ),
      ),
    );

    final SemanticsNode node = tester.getSemantics(
      find.bySemanticsLabel('A red bicycle'),
    );
    expect(node.label, 'A red bicycle');
    expect(node.flagsCollection.isImage, isTrue);
    handle.dispose();
  });

  testWidgets('an image with no alt text is not announced',
      (WidgetTester tester) async {
    // Reading out a file name is worse for a screen reader than silence.
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(DVImage.network('https://example.com/a.png')),
      ),
    );

    expect(find.byType(ExcludeSemantics), findsOneWidget);
    handle.dispose();
  });

  testWidgets('intrinsic size reserves space before the image loads',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DVImageView(
          DVImage.network('https://example.com/a.png', width: 120, height: 90),
        ),
      ),
    );

    final Image rendered = tester.widget<Image>(find.byType(Image));
    expect(rendered.width, 120);
    expect(rendered.height, 90);
  });
}
