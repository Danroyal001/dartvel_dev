// Every source in these packages also runs on the web, where shifts are
// 32-bit: `1 << 32` is 0 there and `Random.nextInt(0)` throws. The crash
// reporter hit this first (crash_web_numbers_test.dart); the offline store's
// mutation ids hit it again in a browser app, so every save failed.
//
// This guard reads the package sources and fails on any `nextInt(1 << 32)`.
// Draw two 16-bit halves instead, as dvCrashReportId does.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no package source asks Random for a number below 1 << 32', () {
    final Directory packages = Directory('..');
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in packages.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll('\\', '/');
      if (!path.contains('/lib/')) continue;
      if (path.contains('/.dart_tool/') || path.contains('/build/')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int index = 0; index < lines.length; index++) {
        final String line = lines[index];
        if (line.trimLeft().startsWith('//')) continue;
        if (RegExp(r'nextInt\(\s*1\s*<<\s*32\s*\)').hasMatch(line)) {
          offenders.add('$path:${index + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'nextInt(1 << 32) is nextInt(0) on the web and throws');
  });
}
