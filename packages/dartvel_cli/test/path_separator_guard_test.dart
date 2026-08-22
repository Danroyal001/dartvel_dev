// `replaceAll('\\', '/')` is the two-character string backslash-backslash, so
// it only matches *doubled* separators. Windows paths have single ones, so it
// silently does nothing — and the path travels on into route derivation, file
// discovery and generated string literals.
//
// It cost six failed Windows builds to find, because on posix every one of
// these lines is a no-op and every test passes.
//
// This guards the signature rather than any single site: the mistake is easy
// to write, reads as correct, and is invisible on the platform it is written on.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no generator normalises separators with a doubled backslash', () {
    // The literal being searched for is the four characters ' \ \ ' as they
    // appear in source — a Dart string holding two backslashes.
    final broken = <String>[];

    for (final packageDir in Directory('..').listSync().whereType<Directory>()) {
      final lib = Directory('${packageDir.path}/lib');
      if (!lib.existsSync()) continue;

      for (final file in lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final line in source.split('\n')) {
          // A non-raw string containing exactly two backslash characters,
          // being used to match a separator.
          if (line.contains(r"replaceAll('\\\\'") ||
              line.contains(r'replaceAll("\\\\"')) {
            broken.add('${file.path}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      broken,
      isEmpty,
      reason: 'use r\'\\\' to match a single backslash; '
          '\'\\\\\\\\\' matches two and silently does nothing:\n'
          '${broken.join('\n')}',
    );
  });
}
