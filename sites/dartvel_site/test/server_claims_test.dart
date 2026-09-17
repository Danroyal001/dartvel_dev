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
  'lib/pages/studio.dart',
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

  // The deployment docs named Linux x64 as the only host a server binary is
  // built for, which stopped being true when dartvel_shelf shipped its library
  // for the other five and CI built and ran the binary on each of them (the
  // web-server hosts workflow). The docs page says which hosts, so a reader on
  // a Mac or on Windows is not told to go and find a Linux machine.
  test('the deployment docs name every host the server binary runs on', () {
    final String source = File('lib/pages/docs/deploying.dart')
        .readAsLinesSync()
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(source, isNot(contains('Linux x64 only')));
    for (final String host in <String>[
      'Linux',
      'macOS',
      'Windows',
      'arm64',
      'x64',
      'server.exe',
    ]) {
      expect(source, contains(host), reason: 'the hosts note leaves out $host');
    }
  });
}
