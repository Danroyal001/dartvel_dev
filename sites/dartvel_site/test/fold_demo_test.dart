// The UI page shows DVBox.twoPane and DVBox.threePane working, not just
// described: a reader picks a posture and watches the panes move off the
// creases.
import 'package:dartvel_site/components/fold_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: FoldDemo())),
  ));
}

/// The pane's rectangle in the simulated screen's own coordinates.
Rect paneIn(WidgetTester tester, String label) {
  final Rect screen = tester.getRect(find.byKey(FoldDemo.screenKey));
  final Rect pane = tester.getRect(find.byKey(FoldDemo.paneKey(label)));
  final double scale = screen.width / FoldDemo.screenSize.width;
  return Rect.fromLTWH((pane.left - screen.left) / scale,
      (pane.top - screen.top) / scale, pane.width / scale, pane.height / scale);
}

bool crosses(Rect pane, Rect crease) =>
    pane.left < crease.right && pane.right > crease.left;

void main() {
  testWidgets('on a tri-fold each of three panes has a panel of its own',
      (WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('threePane'));
    await tester.tap(find.text('Tri-fold'));
    await tester.pumpAndSettle();

    final List<Rect> panes = <Rect>[
      for (final String l in <String>['List', 'Detail', 'Inspector'])
        paneIn(tester, l),
    ];
    for (final Rect crease in FoldDemo.creases(FoldDemoPosture.triFold)) {
      for (final Rect pane in panes) {
        expect(crosses(pane, crease), isFalse,
            reason: '$pane lies across the crease at $crease');
      }
    }
    expect(panes[0].right, lessThanOrEqualTo(panes[1].left));
    expect(panes[1].right, lessThanOrEqualTo(panes[2].left));
  });

  testWidgets('folded once, twoPane puts one pane each side',
      (WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('twoPane'));
    await tester.tap(find.text('Folded once'));
    await tester.pumpAndSettle();

    final Rect crease = FoldDemo.creases(FoldDemoPosture.oneFold).single;
    final Rect list = paneIn(tester, 'List');
    final Rect detail = paneIn(tester, 'Detail');
    expect(list.right, lessThanOrEqualTo(crease.left));
    expect(detail.left, greaterThanOrEqualTo(crease.right));
    expect(find.byKey(FoldDemo.paneKey('Inspector')), findsNothing);
  });

  testWidgets('the demo code matches what is shown', (WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('threePane'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DVBox.threePane('), findsOneWidget);
    await tester.tap(find.text('twoPane'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DVBox.twoPane('), findsOneWidget);
  });
}
