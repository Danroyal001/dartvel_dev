// `.height()` is a box height and `.lineHeight()` is a multiple of the font
// size, and the two are one keystroke apart.
//
// The site wrote `.height(1.06)` on its own h1 and got a headline laid out
// into a box one pixel tall. It clipped rather than overflowed -- a fixed
// height is a fixed height, and Flutter only draws the yellow stripes for a
// flex that could not fit its children -- so nothing failed. Analysis saw a
// double passed to a method that takes a double. The build succeeded, the
// tests passed, and every paragraph of prose on the front page was invisible.
//
// Seventeen of them, on four pages, between 1.05 and 1.65: nobody has ever
// wanted a box 1.65 pixels tall while also choosing a font for it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a text height under three points is a line height', () {
    test('it refuses one, and says which method was meant', () {
      expect(
        () => const DVModifier().fontSize(54).height(1.06),
        throwsA(isA<AssertionError>().having(
          (AssertionError e) => e.message.toString(),
          'message',
          allOf(contains('lineHeight'), contains('1.06')),
        )),
      );
    });

    test('the order it is written in does not matter', () {
      expect(
        () => const DVModifier().height(1.6).fontSize(19),
        throwsA(isA<AssertionError>()),
      );
    });

    test('any text styling is enough to mean it', () {
      expect(() => const DVModifier().fontWeight(FontWeight.w800).height(1.05),
          throwsA(isA<AssertionError>()));
      expect(() => const DVModifier().letterSpacing(0.4).height(1.2),
          throwsA(isA<AssertionError>()));
    });
  });

  group('a box height is left alone', () {
    // The reason the rule is not simply "under three". A rule, a divider and
    // a progress bar are all a box two pixels tall, and they carry no font.
    test('a hairline rule', () {
      expect(
          const DVModifier().backgroundColor(const Color(0xFFE6EAF2)).height(1),
          isA<DVModifier>());
      expect(const DVModifier().height(2), isA<DVModifier>());
      expect(const DVModifier().height(0.5), isA<DVModifier>());
    });

    test('a real height on text, which is a box that holds it', () {
      expect(const DVModifier().fontSize(19).height(48), isA<DVModifier>());
    });

    test('lineHeight itself, which is what was meant all along', () {
      expect(const DVModifier().fontSize(19).lineHeight(1.65),
          isA<DVModifier>());
    });
  });
}
