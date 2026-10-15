// The chrome every page shares is drawn with Dartvel's own primitives.
//
// A framework's site laid out half in Row, Padding and SizedBox is an
// argument against the framework, and these files are the ones every page
// renders: the layout, the bands and bullets, and the code block.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final String path in <String>[
    'lib/pages/_layout.dart',
    'lib/pages/index.dart',
    'lib/components/site.dart',
    'lib/components/hero_demo.dart',
    'lib/components/highlight.dart',
  ]) {
    test('$path uses DVBox where it lays something out', () {
      final String code = File(path)
          .readAsLinesSync()
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final String raw in <String>[
        'Row(', 'Column(', 'Padding(', 'SizedBox(', 'Container(',
        'ColoredBox(', 'ListenableBuilder(', 'StatelessWidget', 'StatefulWidget',
      ]) {
        expect(RegExp('(?<![A-Za-z.])${RegExp.escape(raw)}').hasMatch(code),
            isFalse, reason: '$raw in $path');
      }
    });
  }
}
