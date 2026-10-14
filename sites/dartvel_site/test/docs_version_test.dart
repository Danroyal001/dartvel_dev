// A docs page that names the current release names the release that is
// current.
//
// The docs said "Dartvel 0.11.5 ships 24 spec sections", "(v0.11.5)" and
// "Maturity: v0.11.5" through two releases, because each was a number typed
// into a sentence. The current version is one constant, moved by
// tool/bump_version.dart with every other version, and a page that states it
// uses the constant. A version in history ("Since 0.11.5", "0.11.5 and
// earlier") is a fact about the past and stays written out.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_site/components/site.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kDartvelVersion is the version dartvel_dev publishes', () {
    final RegExpMatch? declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('../../packages/dartvel_dev/pubspec.yaml')
            .readAsStringSync());
    expect(kDartvelVersion, declared!.group(1));
  });

  test('the spec counts the docs state are the recorded ones', () {
    final Map<String, int> counted = <String, int>{};
    for (final Object? entry in (jsonDecode(
            File('../../docs/spec-status.json').readAsStringSync())
        as Map<String, Object?>)['sections']! as List<Object?>) {
      final Object? status = entry is Map ? entry['status'] : null;
      if (status is String) counted[status] = (counted[status] ?? 0) + 1;
    }
    expect(<int>[kSpecShipped, kSpecPartial, kSpecDesigned], <int>[
      counted['Shipped'] ?? 0,
      counted['Partial'] ?? 0,
      counted['Designed'] ?? 0,
    ]);
  });

  test('no docs or comparison page types a Dartvel version as current', () {
    // A Dartvel-shaped version, not an address (10.0.0.0/8, 0.0.0.0) or
    // another package's constraint (^0.19.7).
    final RegExp version =
        RegExp(r'(?<![\w.:^/])v?0\.\d{1,2}\.\d{1,2}(?!\d|\.\d|/)');
    final RegExp history = RegExp(
        r'(Since|since|before|Before|until|Until) v?0\.\d+\.\d+|0\.\d+\.\d+ and earlier');
    final List<String> typed = <String>[
      for (final String dir in <String>['lib/pages/docs', 'lib/pages/vs'])
        for (final FileSystemEntity e in Directory(dir).listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart'))
            for (final (int, String) line in e
                .readAsLinesSync()
                .indexed
                .where(((int, String) l) =>
                    version.hasMatch(l.$2.replaceAll(history, ''))))
              '${e.path}:${line.$1 + 1}: ${line.$2.trim()}',
    ];
    expect(typed, isEmpty, reason: typed.join('\n'));
  });
}
