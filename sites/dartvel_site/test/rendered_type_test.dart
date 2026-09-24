// The sizes a reader actually sees are on the scale.
//
// `type_scale_test.dart` reads the source, which catches a number written
// beside the word fontSize and misses every other route to one: a size held
// in a local, passed as an argument, or resolved per breakpoint two lines
// above the call. The largest type on the site reached a widget that way and
// went unchecked for exactly that reason.
//
// So this builds the pages and walks what came out.
import 'package:dartvel_site/components/site.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sizes that belong to something other than the site's own type.
///
/// Material draws a few things of its own inside a page, and the scale is a
/// statement about the site's copy rather than about a tooltip.
const Set<double> kNotOurs = <double>{};

void main() {
  setUpAll(() async {
    await IndexPageGeneratedPage.loadLibrary();
    await FeaturesPageGeneratedPage.loadLibrary();
    await DocsPageGeneratedPage.loadLibrary();
    await CloudPageGeneratedPage.loadLibrary();
    await StudioPageGeneratedPage.loadLibrary();
  });

  setUp(dvResetDeferredPages);

  final Map<String, Widget> pages = <String, Widget>{
    'landing': const IndexPageGeneratedPage(),
    'features': const FeaturesPageGeneratedPage(),
    'docs': const DocsPageGeneratedPage(),
    'cloud': const CloudPageGeneratedPage(),
    'studio': const StudioPageGeneratedPage(),
  };

  for (final MapEntry<String, Widget> page in pages.entries) {
    for (final Size size in <Size>[const Size(1400, 2400), const Size(390, 2400)]) {
      testWidgets('${page.key} at ${size.width.round()} sets type only on '
          'the scale', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          theme: dartvelSiteTheme(Brightness.light),
          home: Scaffold(body: page.value),
        ));
        for (int frame = 0; frame < 6; frame += 1) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(tester.takeException(), isNull);

        final Set<double> off = <double>{};
        for (final Element element in find.byType(RichText).evaluate()) {
          final RichText text = element.widget as RichText;
          text.text.visitChildren((InlineSpan span) {
            final double? fontSize = span.style?.fontSize;
            if (fontSize != null &&
                !kTypeScale.contains(fontSize) &&
                !kNotOurs.contains(fontSize)) {
              off.add(fontSize);
            }
            return true;
          });
        }
        expect(off, isEmpty,
            reason: 'rendered at ${off.join(', ')}, and the scale is '
                '${kTypeScale.join(', ')}');
      });
    }
  }
}
