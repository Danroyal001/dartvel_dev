// The idle backfill (backfill.dart) is off unless an application opts in.
//
// Built for Dartvel 3.47.9 (#303), it builds every row a lazy list holds back
// while the page is idle, so a screen reader and the browser's find reach
// them. On long lists it kept the main thread busy and the heap high: on
// sigmadev.digital's 177-tool catalogue (390 px, 4x CPU) the JS heap peaked
// at 50-58 MB against 15-21 MB, and the first 15 s after the first frame ran
// at 3.6-7.4 fps against 39-48 fps. So it ships off; an application turns it
// on with `dartvel.web.lazyBackfill: true` in pubspec.yaml, which the build
// hands the app as the DARTVEL_LAZY_BACKFILL define.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/lists/backfill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(DVLazyBackfill.reset);

  test('on only on the web and only when the application opts in', () {
    expect(dvLazyBackfillDefault(isWeb: true, optedIn: false), isFalse);
    expect(dvLazyBackfillDefault(isWeb: true, optedIn: true), isTrue);
    expect(dvLazyBackfillDefault(isWeb: false, optedIn: true), isFalse);
    expect(dvLazyBackfillDefault(isWeb: false, optedIn: false), isFalse);
  });

  test('a build with no opt-in has it off, and reset goes back to that', () {
    expect(DVLazyBackfill.optedIn, isFalse);
    expect(DVLazyBackfill.enabled, isFalse);
    DVLazyBackfill.enabled = true;
    DVLazyBackfill.reset();
    expect(DVLazyBackfill.enabled, isFalse);
  });

  testWidgets('with no opt-in a long page builds nothing ahead', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long page'),
        child: DVBox.list(<Widget>[
          const Text('Site header'),
          DVBox.list(<Widget>[for (int i = 0; i < 80; i++) Text('Paragraph $i')], spacing: 12),
          const Text('Footer made by somebody'),
        ], spacing: 0).scrollable(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(DVLazyBackfill.pending, isFalse, reason: 'nothing registered to build while idle');
    expect(DVLazyBackfill.step(), isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Footer made by somebody', skipOffstage: false), findsNothing);
  });
}
