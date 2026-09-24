// The drawn brand and the SVG brand are the same brand.
//
// assets/brand holds the originals and tool/brand_art.dart redraws them in
// Dart, because nothing on the PATH here renders an SVG gradient correctly
// and an export that quietly loses it is worse than no export. Two
// descriptions of one artwork is a thing that drifts, and the way it drifts
// is silent: the SVG in a README and the PNG on the page stop being the same
// logo and both still look fine on their own.
//
// So this reads the numbers out of both and compares them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/brand_art.dart';

const String kBrand = '../../assets/brand';

String svg(String name) => File('$kBrand/$name').readAsStringSync();

/// Every `#RRGGBB` in [source], in the order it appears.
List<String> hexes(String source) => <String>[
      for (final RegExpMatch m
          in RegExp(r'#[0-9A-Fa-f]{6}').allMatches(source))
        m.group(0)!.toUpperCase(),
    ];

String hexOf(Color color) =>
    '#${((color.r * 255).round() << 16 | (color.g * 255).round() << 8 | (color.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('the gradient is the same three stops in both', () {
    final List<String> drawn = kBrandStops.map(hexOf).toList();
    for (final String file in <String>[
      'dartvel-mark.svg',
      'dartvel-badge.svg',
      'dartvel-badge-maskable.svg',
      'dartvel-logo.svg',
      'dartvel-logo-on-dark.svg',
      'dartvel-social-card.svg',
    ]) {
      final List<String> found = hexes(svg(file));
      for (final String stop in drawn) {
        expect(found, contains(stop), reason: '$file is missing $stop');
      }
    }
  });

  test('the ink and the paper are the same in both', () {
    expect(hexes(svg('dartvel-mark.svg')), contains(hexOf(kInk)));
    expect(hexes(svg('dartvel-logo-on-dark.svg')), contains(hexOf(kPaper)));
    expect(hexes(svg('dartvel-social-card.svg')), contains(hexOf(kCardMuted)));
  });

  test('no file still carries a colour from the blue brand', () {
    // The exact shades that were there before, by name, so a file somebody
    // forgot is named here rather than found by eye later.
    const List<String> was = <String>[
      '#7A3BFF', '#2F6BFF', '#1FB6F5', '#0B1020', '#F2F5FA', '#9AA7BD',
    ];
    for (final FileSystemEntity entity in Directory(kBrand).listSync()) {
      if (entity is! File || !entity.path.endsWith('.svg')) continue;
      final List<String> found = hexes(entity.readAsStringSync());
      for (final String old in was) {
        expect(found, isNot(contains(old)), reason: entity.path);
      }
    }
  });

  test('the D is the same path in both', () {
    // The path data the SVGs carry, compared against the bounds the drawn
    // one reports. A number changed in one place moves the box.
    final Rect bounds = dartvelD().getBounds();
    expect(bounds.left, 112);
    expect(bounds.top, 100);
    expect(bounds.right, 400);
    expect(bounds.bottom, 412);

    const String d =
        'M112 100 H256 C336 100 400 170 400 256 C400 342 336 412 256 412 '
        'H112 Z M176 170 H256 L320 256 L256 342 H176 L240 256 Z';
    for (final String file in <String>[
      'dartvel-mark.svg',
      'dartvel-badge.svg',
      'dartvel-badge-maskable.svg',
      'dartvel-logo.svg',
      'dartvel-social-card.svg',
    ]) {
      expect(svg(file), contains(d), reason: file);
    }
  });

  test('the boxes match the viewBoxes', () {
    expect(svg('dartvel-mark.svg'),
        contains('viewBox="0 0 ${kMarkBox.width.round()} ${kMarkBox.height.round()}"'));
    expect(svg('dartvel-logo.svg'),
        contains('viewBox="0 0 ${kLockupBox.width.round()} ${kLockupBox.height.round()}"'));
    expect(svg('dartvel-social-card.svg'),
        contains('viewBox="0 0 ${kCardBox.width.round()} ${kCardBox.height.round()}"'));
  });

  test('every raster the README lists is on disk and is not empty', () {
    for (final String name in <String>[
      'dartvel-mark-16.png', 'dartvel-mark-32.png', 'dartvel-mark-64.png',
      'dartvel-mark-128.png', 'dartvel-mark-256.png', 'dartvel-mark-512.png',
      'dartvel-mark-1024.png',
      'dartvel-badge-64.png', 'dartvel-badge-120.png', 'dartvel-badge-180.png',
      'dartvel-badge-256.png', 'dartvel-badge-512.png', 'dartvel-badge-1024.png',
      'dartvel-badge-maskable-512.png',
      'dartvel-logo-800.png', 'dartvel-logo-1600.png',
      'dartvel-logo-on-dark-1600.png',
      'dartvel-social-card-1200.png',
    ]) {
      expect(File('$kBrand/$name').existsSync(), isTrue, reason: name);
      expect(File('$kBrand/$name').lengthSync(), greaterThan(0), reason: name);
    }
  });
}
