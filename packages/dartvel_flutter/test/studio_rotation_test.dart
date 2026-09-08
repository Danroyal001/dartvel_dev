// A rotated layer in a page document.
//
// DVModifier could fade a box, round it, border it and paint a gradient
// through it, and had no way to turn one. A design's tilted badge, its angled
// price flash and its rotated decorative rule all came through square --
// rendered, plausible, and not the design. The Figma importer had nowhere to
// put the rotation Figma gives it, so it dropped it.
//
// Degrees, not radians. The number in the document, the number a designer
// reads in an inspector, the number Figma reports and the number in the
// exported source are then all the same one, and the conversion happens
// exactly where the widget is built. The parameter is named for its unit so
// somebody reaching for Transform.rotate's radians sees the difference before
// they run it.
import 'dart:math' as math;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/tilted');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box();
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

double? angleOf(WidgetTester tester) {
  final Iterable<Transform> found = tester.widgetList<Transform>(
    find.byType(Transform),
  );
  for (final Transform transform in found) {
    // The rotation is the only transform this page asks for; a Transform
    // some other widget introduced would have an identity-ish matrix for
    // rotation, so read the one that actually turns something.
    final double angle = math.atan2(
      transform.transform.storage[1],
      transform.transform.storage[0],
    );
    if (angle.abs() > 0.0001) return angle;
  }
  return null;
}

void main() {
  group('the modifier', () {
    testWidgets('turns the widget by the degrees it was given',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DVBox(const DVText('tilted'), const DVModifier().rotate(45)),
        ),
      );

      expect(angleOf(tester), closeTo(math.pi / 4, 0.0001));
    });

    testWidgets('a negative angle turns the other way',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DVBox(const DVText('tilted'), const DVModifier().rotate(-90)),
        ),
      );

      expect(angleOf(tester), closeTo(-math.pi / 2, 0.0001));
    });

    testWidgets('no rotation wraps nothing', (WidgetTester tester) async {
      // A Transform around every box would be a layer in the tree that does
      // nothing, on every page, for the one design in ten that tilts
      // something.
      await tester.pumpWidget(
        MaterialApp(
          home: DVBox(const DVText('flat'), const DVModifier().padding(4)),
        ),
      );

      expect(angleOf(tester), isNull);
    });
  });

  group('the page document', () {
    testWidgets('a rotation property turns the box',
        (WidgetTester tester) async {
      await pump(tester, pageWith(<String, Object?>{'rotation': 30}));

      expect(angleOf(tester), closeTo(math.pi / 6, 0.0001));
    });

    testWidgets('a rotation of zero is not a rotation',
        (WidgetTester tester) async {
      await pump(tester, pageWith(<String, Object?>{'rotation': 0}));

      expect(angleOf(tester), isNull);
    });

    testWidgets('something that is not a number is ignored, not thrown on',
        (WidgetTester tester) async {
      // A document can carry anything; a page that will not render because of
      // one bad value is worse than one drawn square.
      await pump(tester, pageWith(<String, Object?>{'rotation': 'sideways'}));

      expect(angleOf(tester), isNull);
    });

    test('it exports as the degrees somebody wrote', () {
      final DVPageDocument document =
          pageWith(<String, Object?>{'rotation': 45});

      expect(document.toDartSource(), contains('.rotate(45.0)'));
    });

    test('no rotation exports no call', () {
      final DVPageDocument document = pageWith(<String, Object?>{'rotation': 0});

      expect(document.toDartSource(), isNot(contains('.rotate(')));
    });
  });
}
