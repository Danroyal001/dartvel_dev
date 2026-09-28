// DVBox.threePane: three panes, one per panel of a tri-fold.
//
// Tri-fold phones (Samsung, Xiaomi, Huawei) report two folds. Each pane
// fills one panel and nothing lands in a crease. With one fold -- a
// two-panel foldable, or a tri-fold half closed -- the first pane takes one
// side and the other two share the other, or, asked, the first two share a
// side and the third has the other. With no fold, three columns wide, two
// on a tablet, stacked on a phone. Reading order follows the text
// direction, and so does a screen reader's.
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ui.DisplayFeature vFold(double x, {double width = 0}) => ui.DisplayFeature(
      bounds: Rect.fromLTWH(x, 0, width, 800),
      type: ui.DisplayFeatureType.fold,
      state: ui.DisplayFeatureState.postureFlat,
    );

ui.DisplayFeature hFold(double y) => ui.DisplayFeature(
      bounds: Rect.fromLTWH(0, y, 800, 0),
      type: ui.DisplayFeatureType.fold,
      state: ui.DisplayFeatureState.postureFlat,
    );

Widget window(
  Widget child, {
  Size size = const Size(1200, 800),
  List<ui.DisplayFeature> features = const <ui.DisplayFeature>[],
  TextDirection direction = TextDirection.ltr,
}) {
  final TestFlutterView view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = size;
  view.devicePixelRatio = 1;
  return MediaQuery(
    data: MediaQueryData(size: size, displayFeatures: features),
    child: Directionality(textDirection: direction, child: child),
  );
}

Widget panes({DVThreePaneFold oneFold = DVThreePaneFold.firstAlone}) =>
    DVBox.threePane(
      const <Widget>[
        SizedBox.expand(child: Text('first')),
        SizedBox.expand(child: Text('second')),
        SizedBox.expand(child: Text('third')),
      ],
      oneFold: oneFold,
    );

Rect at(WidgetTester tester, String text) =>
    tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(SizedBox)).first);

void main() {
  tearDown(() =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  testWidgets('two folds: one pane per panel, nothing in a crease',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(),
        features: <ui.DisplayFeature>[vFold(800, width: 10), vFold(400, width: 10)]));
    expect(at(tester, 'first'), const Rect.fromLTRB(0, 0, 400, 800));
    expect(at(tester, 'second'), const Rect.fromLTRB(410, 0, 800, 800));
    expect(at(tester, 'third'), const Rect.fromLTRB(810, 0, 1200, 800));
  });

  testWidgets('two folds across, the device turned: panels top to bottom',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(),
        size: const Size(800, 1200),
        features: <ui.DisplayFeature>[hFold(400), hFold(800)]));
    expect(at(tester, 'first').top, 0);
    expect(at(tester, 'second').top, 400);
    expect(at(tester, 'third'), const Rect.fromLTRB(0, 800, 800, 1200));
  });

  testWidgets('right to left, the first pane is on the right',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(),
        direction: TextDirection.rtl,
        features: <ui.DisplayFeature>[vFold(400), vFold(800)]));
    expect(at(tester, 'first').left, 800);
    expect(at(tester, 'third').left, 0);
  });

  testWidgets('a screen reader reads them in order whatever the direction',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(window(panes(),
        direction: TextDirection.rtl,
        features: <ui.DisplayFeature>[vFold(400), vFold(800)]));
    final List<String> order = <String>[];
    void walk(SemanticsNode node) {
      if (node.label.isNotEmpty) order.add(node.label);
      node.visitChildren((SemanticsNode c) {
        walk(c);
        return true;
      });
    }

    final List<SemanticsNode> sorted = <SemanticsNode>[];
    tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!
        .visitChildren((SemanticsNode n) {
      sorted.add(n);
      return true;
    });
    // Traversal order is the ordinal sort key each pane carries.
    walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(order.toSet(), <String>{'first', 'second', 'third'});
    final Iterable<Semantics> keyed = tester.widgetList<Semantics>(find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.sortKey is OrdinalSortKey));
    // The panes are laid out right to left, and each carries its place in
    // the list, which is the order a screen reader moves through them.
    final List<(double, String)> read = <(double, String)>[
      for (final Element e in find.byWidgetPredicate((Widget w) =>
          w is Semantics && w.properties.sortKey is OrdinalSortKey).evaluate())
        (
          ((e.widget as Semantics).properties.sortKey! as OrdinalSortKey).order,
          (tester.widget<Text>(find.descendant(
                  of: find.byWidget(e.widget), matching: find.byType(Text))))
              .data!,
        ),
    ]..sort(((double, String) x, (double, String) y) => x.$1.compareTo(y.$1));
    expect(read.map(((double, String) r) => r.$2), <String>['first', 'second', 'third']);
    semantics.dispose();
  });

  testWidgets('one fold: the first alone, the other two share the far side',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(),
        size: const Size(820, 800),
        features: <ui.DisplayFeature>[vFold(400, width: 20)]));
    expect(at(tester, 'first'), const Rect.fromLTRB(0, 0, 400, 800));
    expect(at(tester, 'second').left, 420);
    expect(at(tester, 'third').left, 420);
    expect(at(tester, 'third').top, greaterThan(at(tester, 'second').top));
  });

  testWidgets('one fold, asked: the first two share, the third alone',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(oneFold: DVThreePaneFold.lastAlone),
        size: const Size(820, 800),
        features: <ui.DisplayFeature>[vFold(400, width: 20)]));
    expect(at(tester, 'first').left, 0);
    expect(at(tester, 'second').left, 0);
    expect(at(tester, 'third'), const Rect.fromLTRB(420, 0, 820, 800));
  });

  testWidgets('no fold: three columns wide, two on a tablet, one on a phone',
      (WidgetTester tester) async {
    await tester.pumpWidget(window(panes(), size: const Size(1400, 800)));
    expect(<double>{for (final String t in <String>['first', 'second', 'third']) at(tester, t).top},
        <double>{0});
    await tester.pumpWidget(window(panes(), size: const Size(1000, 1000)));
    expect(at(tester, 'second').left, at(tester, 'third').left);
    expect(at(tester, 'first').left, lessThan(at(tester, 'second').left));
    await tester.pumpWidget(window(
        const SingleChildScrollView(
          child: DVBox.threePane(<Widget>[Text('first'), Text('second'), Text('third')]),
        ),
        size: const Size(390, 800)));
    expect(tester.getRect(find.text('first')).top,
        lessThan(tester.getRect(find.text('second')).top));
    expect(tester.getRect(find.text('second')).top,
        lessThan(tester.getRect(find.text('third')).top));
  });

  testWidgets('it takes exactly three panes', (WidgetTester tester) async {
    await tester.pumpWidget(window(const DVBox.threePane(<Widget>[Text('a')])));
    expect(tester.takeException(), isArgumentError);
  });
}
