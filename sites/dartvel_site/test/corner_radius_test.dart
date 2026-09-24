// Every corner on the site is one of a handful of radii.
//
// Nine values were in use: 3, 6, 8, 9, 10, 11, 12, 14 and a pill. Three of
// them were doing the same job at one point apart, which is what a radius
// chosen by feel looks like once there are enough of them. Nobody sees it
// directly. Everybody sees the page it adds up to.
import 'dart:io';

import 'package:dartvel_site/components/site.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every corner radius the site's own code sets, and where.
List<(String, int, double)> radiiNamed() {
  final List<(String, int, double)> found = <(String, int, double)>[];
  for (final String dir in <String>['lib/pages', 'lib/components']) {
    for (final FileSystemEntity entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Compiled samples quote the samples project's own source.
      if (entity.path.endsWith('components/docs_samples.dart')) continue;
      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in RegExp(
        r'(?:\.rounded|(?:BorderRadius|Radius)\.circular)\(\s*([0-9]+(?:\.[0-9]+)?)',
      ).allMatches(source)) {
        found.add((
          entity.path,
          '\n'.allMatches(source.substring(0, match.start)).length + 1,
          double.parse(match.group(1)!),
        ));
      }
    }
  }
  return found;
}

void main() {
  test('every corner is on the list, or derived from one on it', () {
    final List<(String, int, double)> named = radiiNamed();
    expect(named, isNotEmpty);

    // A value one point under a listed radius is the concentric case: a
    // shape clipped inside a framed one, taking its frame's radius less the
    // border between them. That is a decision. A 9 beside a 10 is not.
    bool legal(double value) =>
        kRadii.contains(value) ||
        kRadii.any((double outer) => insideBorder(outer) == value);

    final List<String> off = <String>[
      for (final (String file, int line, double value) in named)
        if (!legal(value)) '$file:$line  $value',
    ];
    expect(off, isEmpty,
        reason: 'off the list (${kRadii.join(', ')}, or one less than one of '
            'them where it sits inside a border):\n${off.join('\n')}');
  });

  test('the list itself has no two steps a reader cannot tell apart', () {
    for (int i = 1; i < kRadii.length; i++) {
      expect(kRadii[i] - kRadii[i - 1], greaterThanOrEqualTo(2.0),
          reason: '${kRadii[i - 1]} and ${kRadii[i]}');
    }
  });

  test('the concentric rule is what it says it is', () {
    expect(insideBorder(12), 11);
    expect(insideBorder(14, 4), 10);
  });
}
