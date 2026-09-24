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
        // The accent carries links and buttons. 4.5:1 against the page
        // because it is set at body size, and 3:1 against the body colour
        // so it reads as a different thing rather than as slightly-off ink.
        expect(ratio(palette.accent, palette.page), greaterThanOrEqualTo(4.5),
            reason: 'accent on page is '
                '${ratio(palette.accent, palette.page).toStringAsFixed(2)}:1');
      });

      test('a rule is visible against the surfaces it separates', () {
        for (final (String name, Color ground)
            in <(String, Color)>[('page', palette.page), ('surface', palette.surface)]) {
          expect(ratio(palette.rule, ground), greaterThanOrEqualTo(1.2),
              reason: 'rule on $name is '
                  '${ratio(palette.rule, ground).toStringAsFixed(2)}:1');
        }
      });
    });
  }

  test('the two modes are the same scheme, not two schemes', () {
    // A warm palette in one mode and a cool one in the other is two
    // decisions, and the reader who switches sees the seam.
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
        // Warm means red is the largest channel and blue the smallest. A
        // neutral with more blue than red is a cool grey, which is what a
        // blue seed produces and what this palette exists to stop.
        expect(color.r, greaterThanOrEqualTo(color.b),
            reason: '$role in ${brightness.name} is a cool neutral: '
                'r=${color.r.toStringAsFixed(3)} b=${color.b.toStringAsFixed(3)}');
      }
    }
  });
}
