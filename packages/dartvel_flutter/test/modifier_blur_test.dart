// A blurred layer, which the chain could not draw.
//
// DVModifier could fade a box, round it, border it, tilt it and paint a
// gradient through it, and had no way to blur one. Two different designs came
// through wrong because of it: a soft-focus decorative shape rendered sharp,
// and -- far more commonly -- a frosted card over a photograph rendered as a
// flat translucent panel. Both are rendered, plausible, and not the design.
//
// Two methods rather than one, because they are not the same picture. A layer
// blur softens the box and what is in it; a background blur leaves the box
// sharp and blurs whatever is behind it, which is the whole of the frosted
// effect. A single blur() would have to guess which, and the wrong guess
// looks like a bug in the renderer rather than a mistake in the chain.
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, DVModifier modifier) =>
    tester.pumpWidget(
      MaterialApp(home: DVBox(const DVText('inside'), modifier)),
    );

void main() {
  testWidgets('a layer blur reaches the filter with the sigma it was given',
      (WidgetTester tester) async {
    await pump(tester, const DVModifier().blur(8));

    final ImageFiltered filtered =
        tester.widget<ImageFiltered>(find.byType(ImageFiltered));
    expect(
      filtered.imageFilter,
      ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
    );
  });

  testWidgets('a background blur blurs behind rather than the box itself',
      (WidgetTester tester) async {
    await pump(tester, const DVModifier().backdropBlur(20));

    final BackdropFilter behind =
        tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(behind.filter, ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20));
    // And the box stays sharp: a background blur that also softened its own
    // content would be a layer blur under another name.
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('a background blur is bounded by the box it belongs to',
      (WidgetTester tester) async {
    // An unclipped BackdropFilter blurs the whole screen behind it, which is
    // the one failure mode here that looks deliberate: the page goes soft and
    // nothing points at the card that asked for it.
    await pump(tester, const DVModifier().rounded(12).backdropBlur(20));

    final ClipRRect clip = tester.widget<ClipRRect>(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(ClipRRect),
      ).first,
    );
    expect(clip.borderRadius, BorderRadius.circular(12));
  });

  testWidgets('a box that asked for neither pays for neither',
      (WidgetTester tester) async {
    // A filter layer in every box in every application, for the one design in
    // ten that blurs something, is the cost this check exists to keep off.
    await pump(tester, const DVModifier().padding(8));

    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a zero sigma is not a blur', (WidgetTester tester) async {
    // Blurring by nothing is a layer that costs what a real blur costs and
    // changes no pixel, and a design exported with 0 is saying it does not
    // blur rather than asking for an expensive no-op.
    await pump(tester, const DVModifier().blur(0).backdropBlur(0));

    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('merging keeps a blur the other side set',
      (WidgetTester tester) async {
    await pump(
      tester,
      const DVModifier()
          .padding(8)
          .merge(const DVModifier().blur(4).backdropBlur(6)),
    );

    expect(
      tester.widget<ImageFiltered>(find.byType(ImageFiltered)).imageFilter,
      ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
      ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
    );
  });
}
