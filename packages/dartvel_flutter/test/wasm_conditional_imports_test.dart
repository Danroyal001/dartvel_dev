// dart2wasm has no dart:html, so `if (dart.library.html)` is false in a
// `dartvel.web.renderer: wasm` build and the import falls back to its
// non-web stub without a word. The SEO head on client-side navigation went
// that way: correct under dart2js, silently memory-only under wasm. The web
// branch is chosen with `dart.library.js_interop`, true under both.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no web code is selected by dart.library.html', () {
    final List<String> offenders = <String>[];
    for (final String root in <String>['lib', '../dartvel_core/lib']) {
      final Directory dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final List<String> lines = entity.readAsLinesSync();
        for (int index = 0; index < lines.length; index++) {
          final String line = lines[index];
          if (line.trimLeft().startsWith('//')) continue;
          if (RegExp(r'if\s*\(\s*dart\.library\.(html|js)\s*\)').hasMatch(line)) {
            offenders.add('${entity.path}:${index + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
