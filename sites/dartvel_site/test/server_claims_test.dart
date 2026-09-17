// Three claims the owner struck from the site, kept out.
//
// A byte count for the server binary: it grows with the backend, and a
// company with a thousand backend functions ships a bigger file than a demo
// with one. "No build_runner and no generated files": Dartvel does generate
// code, in dartvel dev and dartvel build, and a line that reads as "nothing
// is generated" is wrong. "Linux x64" on the marketing pages: the web-server
// build is specified for the OS and CPU it is built on, so the pitch does not
// narrow it to one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> pitchPages = <String>[
  'lib/pages/index.dart',
  'lib/pages/features.dart',
  'lib/pages/cloud.dart',
];

void main() {
  for (final String path in pitchPages) {
    test('$path makes none of the struck server claims', () {
      final List<String> lines = File(path)
          .readAsLinesSync()
          .where((String l) => !l.trimLeft().startsWith('//'))
          .toList();
      final String source = lines.join('\n');
      expect(source, isNot(matches(RegExp(r'\d+(?:\.\d+)?\s*MB\b'))),
          reason: 'a binary size in MB');
      expect(source, isNot(matches(RegExp(r'\bno build_runner\b', caseSensitive: false))),
          reason: 'denies code generation');
      expect(source, isNot(contains('Linux x64')), reason: 'narrows the server to Linux x64');
    });
  }
}
