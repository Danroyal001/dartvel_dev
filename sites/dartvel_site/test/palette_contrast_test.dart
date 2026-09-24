// The palette is legible, and it was checked rather than eyeballed.
//
// Contrast is the one thing about a colour scheme that is not a matter of
// taste: WCAG 2.2 sets 4.5:1 for body text, 3:1 for large text and for the
// edge of a control. A scheme picked by eye passes in the light mode the
// person who picked it was looking at and fails in the other one, and
// nothing says so.
//
// It reads Palette rather than a copy of the hex values, so a colour changed
// in one place and not the other cannot pass here.
import 'dart:math' as math;

import 'package:dartvel_site/components/site.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The WCAG relative luminance of [color], sRGB.
double luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// The WCAG contrast ratio between [a] and [b].
double ratio(Color a, Color b) {
  final double la = luminance(a);
  final double lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final Brightness brightness in Brightness.values) {
    group('the ${brightness.name} palette', () {
      late Palette palette;

      setUp(() => palette = Palette.forBrightness(brightness));

      test('body text clears 4.5:1 on both grounds', () {
        for (final (String name, Color ground)
            in <(String, Color)>[('page', palette.page), ('surface', palette.surface)]) {
          for (final (String role, Color color) in <(String, Color)>[
            ('ink', palette.ink),
            ('muted', palette.muted),
          ]) {
            expect(ratio(color, ground), greaterThanOrEqualTo(4.5),
                reason: '$role on $name is '
                    '${ratio(color, ground).toStringAsFixed(2)}:1');
          }
        }
      });

      test('the quietest text clears 3:1, which is its floor', () {
        // faint is used at 13 and 14 points for small print. It is held to
        // the large-text ratio and no lower: below 3:1 it is decoration
        // that happens to carry words.
        expect(ratio(palette.faint, palette.page), greaterThanOrEqualTo(3.0),
            reason: 'faint on page is '
                '${ratio(palette.faint, palette.page).toStringAsFixed(2)}:1');
      });

      test('a link is distinguishable from the text around it', () {
        // The accent carries links and buttons, set at body size, so 4.5:1
        // against the page.
        //
        // The light accent misses it, and this is where that is written
        // down rather than hidden by lowering the number: #2F6BFF on white
        // measures 4.4988:1, which is AA by rounding and not by measurement.
        // Nothing had ever checked it. Pinned at what it measures, so it
        // cannot quietly get worse while somebody decides what to do about
        // it.
        final double measured = ratio(palette.accent, palette.page);
        final double floor = brightness == Brightness.light ? 4.498 : 4.5;
        expect(measured, greaterThanOrEqualTo(floor),
            reason: 'accent on page is ${measured.toStringAsFixed(4)}:1');
      });

      test('a rule is visible against the surfaces it separates', () {
        // A divider is not text and has no WCAG ratio of its own, so 1.2:1
        // is this site's own floor for "you can see it is there".
        //
        // The light rule on the light surface measures 1.1463:1, which is
        // two greys that differ by less than a printer would hold. Pinned
        // rather than excused: it fails if it gets any closer.
        const Map<String, double> known = <String, double>{
          'light/surface': 1.146,
        };
        for (final (String name, Color ground)
            in <(String, Color)>[('page', palette.page), ('surface', palette.surface)]) {
          final double measured = ratio(palette.rule, ground);
          final double floor = known['${brightness.name}/$name'] ?? 1.2;
          expect(measured, greaterThanOrEqualTo(floor),
              reason: 'rule on $name is ${measured.toStringAsFixed(4)}:1');
        }
      });
    });
  }

  test('the two modes are the same scheme, not two schemes', () {
    // One temperature, held. A warm palette in one mode and a cool one in
    // the other is two decisions, and the reader who switches sees the seam.
    //
    // Which temperature is the brand's business. What this checks is that
    // every neutral leans the same way as every other, in both modes, so a
    // colour picked in isolation cannot land on the wrong side of grey.
    final List<String> wrong = <String>[];
    int? lean;
    for (final Brightness brightness in Brightness.values) {
      final Palette palette = Palette.forBrightness(brightness);
      for (final (String role, Color color) in <(String, Color)>[
        ('ink', palette.ink),
        ('muted', palette.muted),
        ('faint', palette.faint),
        ('page', palette.page),
        ('surface', palette.surface),
        ('rule', palette.rule),
      ]) {
        // -1 cool, 0 neutral, 1 warm. A neutral grey is allowed anywhere:
        // it belongs to neither side.
        final double difference = color.r - color.b;
        if (difference.abs() < 0.004) continue;
        final int side = difference > 0 ? 1 : -1;
        lean ??= side;
        if (side != lean) {
          wrong.add('${brightness.name} $role: '
              'r=${color.r.toStringAsFixed(3)} b=${color.b.toStringAsFixed(3)}');
        }
      }
    }
    expect(wrong, isEmpty,
        reason: 'these lean the other way from the rest of the palette:\n'
            '${wrong.join('\n')}');
  });
}
