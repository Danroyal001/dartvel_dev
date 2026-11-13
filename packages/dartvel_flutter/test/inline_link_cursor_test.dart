// A link inside running text shows the pointing hand, like every other link
// (owner, 13 Nov 2026: "Verify on Credly" on sigmadev.digital/danieleffiong
// showed the text cursor). The site's inline links are DVNavLinks in a
// WidgetSpan of a Text.rich, and every Dartvel page is selectable.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bool external in <bool>[false, true]) {
    testWidgets('an ${external ? 'external' : 'internal'} link inside a selectable sentence shows the pointer', (WidgetTester tester) async {
      final Widget link = external
          ? DVNavLink.external('https://www.credly.com/badges/x', padding: EdgeInsets.zero, child: const Text('Verify on Credly'))
          : DVNavLink(to: const DVRouteTarget('/docs'), padding: EdgeInsets.zero, child: const Text('Verify on Credly'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: Text.rich(TextSpan(children: <InlineSpan>[
              const TextSpan(text: 'AWS Certified Solutions Architect, valid to May 2028. '),
              WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: link),
            ])),
          ),
        ),
      ));
      await tester.pump();
      final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Verify on Credly')));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    });
  }
}
