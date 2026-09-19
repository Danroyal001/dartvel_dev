// Foldables: the fold as the screen reports it, and a two-pane box that
// splits on it.
//
// Android foldables and Apple's iPhone Duo put a fold or a hinge through the
// middle of the screen. Flutter reports it as a DisplayFeature on MediaQuery;
// context.screen.folds reads it, and DVBox.twoPane puts one pane on each side
// of it, so no text lands in the crease.
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A book-style hinge down the middle of an 820 by 800 window.
const ui.DisplayFeature bookHinge = ui.DisplayFeature(
  bounds: Rect.fromLTWH(400, 0, 20, 800),
  type: ui.DisplayFeatureType.hinge,
  state: ui.DisplayFeatureState.postureHalfOpened,
);

/// A fold across the middle, the phone half-open on a table.
const ui.DisplayFeature tabletopFold = ui.DisplayFeature(
  bounds: Rect.fromLTWH(0, 400, 820, 0),
  type: ui.DisplayFeatureType.fold,
  state: ui.DisplayFeatureState.postureHalfOpened,
);

/// A camera cutout is a display feature and is not a fold.
const ui.DisplayFeature cutout = ui.DisplayFeature(
  bounds: Rect.fromLTWH(390, 0, 40, 30),
  type: ui.DisplayFeatureType.cutout,
  state: ui.DisplayFeatureState.unknown,
);

/// A window of [size] with [features], on a test surface of the same size.
Widget window(
  Widget child, {
  Size size = const Size(820, 800),
  List<ui.DisplayFeature> features = const <ui.DisplayFeature>[],
}) {
  final TestFlutterView view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = size;
  view.devicePixelRatio = 1;
  return MediaQuery(
    data: MediaQueryData(size: size, displayFeatures: features),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

void main() {
  tearDown(() =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  group('context.screen.folds', () {
    testWidgets('reads a hinge, and ignores a camera cutout',
        (WidgetTester tester) async {
      late DVScreenInfo screen;
      await tester.pumpWidget(window(
        Builder(builder: (BuildContext context) {
          screen = context.screen;
          return const SizedBox();
        }),
        features: const <ui.DisplayFeature>[bookHinge, cutout],
      ));

      expect(screen.folds, hasLength(1));
      final DVFold fold = screen.folds.single;
      expect(fold.bounds, const Rect.fromLTWH(400, 0, 20, 800));
      expect(fold.isVertical, isTrue);
      expect(fold.occludes, isTrue, reason: 'a hinge covers 20 points');
      expect(fold.state, DVFoldState.halfOpened);
      expect(screen.isSpanned, isTrue);
      expect(screen.posture, DVPosture.book);
    });

    testWidgets('a fold across the screen, half open, is tabletop',
        (WidgetTester tester) async {
      late DVScreenInfo screen;
      await tester.pumpWidget(window(
        Builder(builder: (BuildContext context) {
          screen = context.screen;
          return const SizedBox();
        }),
        features: const <ui.DisplayFeature>[tabletopFold],
      ));

      expect(screen.folds.single.isVertical, isFalse);
      expect(screen.folds.single.occludes, isFalse,
          reason: 'a fold has no width and hides nothing');
      expect(screen.posture, DVPosture.tabletop);
    });

    testWidgets('a plain phone has no folds and lies flat',
        (WidgetTester tester) async {
      late DVScreenInfo screen;
      await tester.pumpWidget(window(
        Builder(builder: (BuildContext context) {
          screen = context.screen;
          return const SizedBox();
        }),
        size: const Size(390, 844),
      ));

      expect(screen.folds, isEmpty);
      expect(screen.isSpanned, isFalse);
      expect(screen.posture, DVPosture.flat);
    });

    testWidgets('a widget rebuilds when the phone is unfolded',
        (WidgetTester tester) async {
      int builds = 0;
      final Widget reader = Builder(builder: (BuildContext context) {
        builds++;
        return Text('${context.screen.folds.length}');
      });
      await tester.pumpWidget(window(reader));
      await tester.pumpWidget(
          window(reader, features: const <ui.DisplayFeature>[bookHinge]));

      expect(find.text('1'), findsOneWidget);
      expect(builds, 2);
    });
  });

  group('DVBox.twoPane', () {
    const Key first = ValueKey<String>('first');
    const Key second = ValueKey<String>('second');
    const Widget panes = DVBox.twoPane(<Widget>[
      SizedBox.expand(key: first),
      SizedBox.expand(key: second),
    ]);

    testWidgets('puts one pane each side of a hinge, and nothing in it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          window(panes, features: const <ui.DisplayFeature>[bookHinge]));

      expect(tester.getRect(find.byKey(first)),
          const Rect.fromLTWH(0, 0, 400, 800));
      expect(tester.getRect(find.byKey(second)),
          const Rect.fromLTWH(420, 0, 400, 800));
    });

    testWidgets('splits top and bottom on a fold across the screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          window(panes, features: const <ui.DisplayFeature>[tabletopFold]));

      expect(tester.getRect(find.byKey(first)),
          const Rect.fromLTWH(0, 0, 820, 400));
      expect(tester.getRect(find.byKey(second)),
          const Rect.fromLTWH(0, 400, 820, 400));
    });

    testWidgets('side by side on a tablet with no fold',
        (WidgetTester tester) async {
      await tester.pumpWidget(window(panes, size: const Size(1000, 700)));

      expect(tester.getRect(find.byKey(first)).left, 0);
      expect(tester.getRect(find.byKey(second)).top, 0);
      expect(tester.getRect(find.byKey(second)).left, greaterThan(490));
    });

    testWidgets('stacked on a phone with no fold, so neither pane is lost',
        (WidgetTester tester) async {
      await tester.pumpWidget(window(
        const DVBox.twoPane(<Widget>[
          SizedBox(key: first, height: 100),
          SizedBox(key: second, height: 100),
        ]),
        size: const Size(390, 844),
      ));

      expect(tester.getRect(find.byKey(first)).top, 0);
      expect(tester.getRect(find.byKey(second)).top,
          greaterThanOrEqualTo(100));
    });

    testWidgets('each pane is its own screen, with no fold through it',
        (WidgetTester tester) async {
      final List<int> seen = <int>[];
      await tester.pumpWidget(window(
        DVBox.twoPane(<Widget>[
          for (int i = 0; i < 2; i++)
            Builder(builder: (BuildContext context) {
              seen.add(context.screen.folds.length);
              return const SizedBox.expand();
            }),
        ]),
        features: const <ui.DisplayFeature>[bookHinge],
      ));

      expect(seen, <int>[0, 0]);
    });
  });
}
