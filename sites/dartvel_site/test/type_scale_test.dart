// Every size on the site is on one scale.
//
// Fourteen distinct sizes were in use, including 12.5, 13.5 and 19. Each one
// is invisible on its own, which is exactly why they accumulate: somebody
// needed a label slightly smaller than the one above it and wrote 13.5. The
// result is a page where nothing is wrong and everything is slightly off,
// and it is one of the reliable marks of an interface assembled rather than
// designed.
//
// The scale is not a rule imposed from outside: it is the sizes this site
// actually needed, with the near-duplicates collapsed.
import 'dart:io';

import 'package:dartvel_site/components/site.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `fontSize` the site's own code asks for, and where.
List<(String, int, String)> sizesNamed() {
  final List<(String, int, String)> found = <(String, int, String)>[];
  for (final String dir in <String>['lib/pages', 'lib/components']) {
    for (final FileSystemEntity entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Compiled samples quote the samples project's own source. The sizes
      // in them belong to that code, and rewriting them here would make the
      // docs disagree with the file they were taken from.
      if (entity.path.endsWith('components/docs_samples.dart')) continue;
      final String source = entity.readAsStringSync();
      // A plain size, and the two halves of a responsive one. Without the
      // second pattern the largest type on the site went unchecked: a
      // headline is written as value<double>(mobile: 34, desktop: 50), and
      // neither number is next to the word fontSize.
      for (final RegExp pattern in <RegExp>[
        RegExp(r'fontSize[:(]\s*([0-9]+(?:\.[0-9]+)?)'),
        RegExp(r'fontSize\([^)]*?(?:mobile|desktop|tablet):\s*'
            r'([0-9]+(?:\.[0-9]+)?)'),
        RegExp(r'(?:mobile|desktop|tablet):\s*([0-9]+(?:\.[0-9]+)?)\s*\)\)\s*\n?\s*\.fontWeight'),
      ]) {
        for (final RegExpMatch match in pattern.allMatches(source)) {
          found.add((
            entity.path,
            '\n'.allMatches(source.substring(0, match.start)).length + 1,
            match.group(1)!,
          ));
        }
      }
    }
  }
  return found;
}

void main() {
  test('the scale has no two steps a reader cannot tell apart', () {
    // A 1-point step is not a step, it is two sizes nobody decided between.
    for (int i = 1; i < kTypeScale.length; i++) {
      expect(kTypeScale[i] - kTypeScale[i - 1], greaterThanOrEqualTo(1.0),
          reason: '${kTypeScale[i - 1]} and ${kTypeScale[i]}');
    }
    expect(kTypeScale, orderedEquals(<double>[...kTypeScale]..sort()));
  });

  test('every size the site sets is on the scale', () {
    final List<(String, int, String)> named = sizesNamed();
    expect(named, isNotEmpty, reason: 'the scan found no sizes at all');

    final List<String> off = <String>[
      for (final (String file, int line, String value) in named)
        if (!kTypeScale.contains(double.parse(value))) '$file:$line  $value',
    ];
    expect(off, isEmpty,
        reason: 'off the scale (${kTypeScale.join(', ')}):\n${off.join('\n')}');
  });

  test('every step on the scale is used, so it is a scale and not a wish list',
      () {
    final Set<double> used = <double>{
      for (final (String, int, String) entry in sizesNamed())
        double.parse(entry.$3),
    };
    expect(kTypeScale.toSet().difference(used), isEmpty,
        reason: 'declared and never used');
  });
}
